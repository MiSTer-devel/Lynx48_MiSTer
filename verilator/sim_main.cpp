// Headless Verilator simulator for the Camputers Lynx core (rtl/lynx_core.sv).
// Runs at the hardware clk_sys rate (48 MHz) with the hardware clock enables.
//
//   ./obj_dir/Vlynx_sim --model 48 --frames 150 --shots 150 --outdir out
//   ./obj_dir/Vlynx_sim --model 96 --type 'PRINT 2+2\n@120' --frames 200 --shots 200
//
// Frames are PNG files, OUTDIR/frame_NNNNN.png, the active picture only.
#include "Vlynx_sim.h"
#include "verilated.h"
#include <zlib.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <algorithm>
#include <map>
#include <set>
#include <string>
#include <vector>
#include <sys/stat.h>

static Vlynx_sim* top;
static uint64_t cycles = 0;
static const uint64_t CLK_HZ = 48000000;

static int model = 0, run_frames = 100, every = 0;
static std::set<int> shots;
static std::string outdir = "out", rom_path, rom128_path, wav_path, tape_path;
static std::vector<uint8_t> tape_img;
static bool tape_log = false, no_overlay = false;
static int ack_delay = 0;
static bool turbo = false, quiet = false, pc_trace = false;
static std::map<int, std::pair<uint32_t, uint32_t>> dumps;

// ---------------------------------------------------------------- PNG
static void put32(std::vector<uint8_t>& v, uint32_t x) {
  v.push_back(x >> 24); v.push_back(x >> 16); v.push_back(x >> 8); v.push_back(x);
}
static void chunk(FILE* f, const char* type, const std::vector<uint8_t>& data) {
  std::vector<uint8_t> b; put32(b, data.size());
  b.insert(b.end(), type, type + 4); b.insert(b.end(), data.begin(), data.end());
  uint32_t crc = crc32(0, b.data() + 4, b.size() - 4);
  put32(b, crc); fwrite(b.data(), 1, b.size(), f);
}
static bool write_png(const std::string& path, int w, int h, const std::vector<uint8_t>& rgb, int stride) {
  FILE* f = fopen(path.c_str(), "wb"); if (!f) return false;
  static const uint8_t sig[8] = {137, 80, 78, 71, 13, 10, 26, 10}; fwrite(sig, 1, 8, f);
  std::vector<uint8_t> ihdr; put32(ihdr, w); put32(ihdr, h);
  ihdr.push_back(8); ihdr.push_back(2); ihdr.push_back(0); ihdr.push_back(0); ihdr.push_back(0);
  chunk(f, "IHDR", ihdr);
  std::vector<uint8_t> raw; raw.reserve((w * 3 + 1) * h);
  for (int y = 0; y < h; y++) { raw.push_back(0); raw.insert(raw.end(), &rgb[y * stride * 3], &rgb[y * stride * 3] + w * 3); }
  uLongf zl = compressBound(raw.size()); std::vector<uint8_t> z(zl);
  compress2(z.data(), &zl, raw.data(), raw.size(), 6); z.resize(zl);
  chunk(f, "IDAT", z); chunk(f, "IEND", {}); fclose(f); return true;
}

// ---------------------------------------------------------------- video capture
static const int FB_W = 1024, FB_H = 400;
static std::vector<uint8_t> fb(FB_W * FB_H * 3);
static int vx = 0, vy = 0, max_x = 0, frame = 0, last_w = 0, last_h = 0;
static bool prev_hb = true, prev_vs = false, line_px = false;

static void video_step() {
  if (!top->ce_pix) return;
  bool active = !top->HBlank && !top->VBlank;
  if (active) {
    if (vx < FB_W && vy < FB_H) {
      uint8_t* p = &fb[(vy * FB_W + vx) * 3];
      p[0] = top->rgb >> 16; p[1] = top->rgb >> 8; p[2] = top->rgb;
    }
    vx++; line_px = true;
  }
  if (top->HBlank && !prev_hb) {           // end of a line
    if (line_px) { if (vx > max_x) max_x = vx; vy++; }
    vx = 0; line_px = false;
  }
  prev_hb = top->HBlank;
}

// ---------------------------------------------------------------- keyboard (PS/2 set 2 into matrix.v)
// The Lynx keyboard is used positionally: a PC key gives the Lynx key in the same place
// (rtl/matrix.v). Characters are typed with the Lynx's shift states (MAME camplynx.cpp).
struct PS2 { uint8_t code; bool ext, press; };
struct Sched { int frame; PS2 ev; };
static std::vector<Sched> sched;
static int ps2_toggle = 0;

static bool char_code(char c, uint8_t& code, bool& shift) {
  static const uint8_t lc[26] = {0x1C,0x32,0x21,0x23,0x24,0x2B,0x34,0x33,0x43,0x3B,0x42,0x4B,0x3A,
                                 0x31,0x44,0x4D,0x15,0x2D,0x1B,0x2C,0x3C,0x2A,0x1D,0x22,0x35,0x1A};
  static const uint8_t dc[10] = {0x45,0x16,0x1E,0x26,0x25,0x2E,0x36,0x3D,0x3E,0x46};
  shift = false;
  if (c >= 'A' && c <= 'Z') { code = lc[c - 'A']; return true; }            // unshifted = capitals
  if (c >= 'a' && c <= 'z') { code = lc[c - 'a']; shift = true; return true; }
  if (c >= '0' && c <= '9') { code = dc[c - '0']; return true; }
  // Lynx shifted digits: 1 ! 2 " 3 # 4 $ 5 % 6 & 7 ' 8 ( 9 ) 0 _
  const char* sh = "_!\"#$%&'()";
  if (const char* p = strchr(sh, c)) { if (c) { code = dc[p - sh]; shift = true; return true; } }
  switch (c) {
    case ' ':  code = 0x29; return true;
    case '\n': code = 0x5A; return true;
    case ':':  code = 0x52; return true;  case '*': code = 0x52; shift = true; return true;
    case ';':  code = 0x4C; return true;  case '+': code = 0x4C; shift = true; return true;
    case ',':  code = 0x41; return true;  case '<': code = 0x41; shift = true; return true;
    case '.':  code = 0x49; return true;  case '>': code = 0x49; shift = true; return true;
    case '/':  code = 0x4A; return true;  case '?': code = 0x4A; shift = true; return true;
    case '-':  code = 0x4E; return true;  case '=': code = 0x4E; shift = true; return true;
    case '@':  code = 0x55; return true;  case '\\': code = 0x55; shift = true; return true;
    case '[':  code = 0x54; return true;  case '^': code = 0x54; shift = true; return true;
    case ']':  code = 0x5B; return true;
  }
  return false;
}

// a key goes down, stays down 3 frames, up, then 2 frames gap
static void schedule_text(int f, const std::string& t) {
  for (size_t i = 0; i < t.size(); i++) {
    char c = t[i];
    if (c == '\\' && i + 1 < t.size() && t[i + 1] == 'n') { c = '\n'; i++; }
    if (c == '\\' && i + 1 < t.size() && t[i + 1] == 'e') {          // \e: ESC
      i++; sched.push_back({f, {0x76, false, true}}); sched.push_back({f + 4, {0x76, false, false}}); f += 6; continue; }
    uint8_t code; bool shift;
    if (!char_code(c, code, shift)) { fprintf(stderr, "cannot type '%c'\n", c); continue; }
    if (shift) sched.push_back({f, {0x12, false, true}});
    sched.push_back({f + (shift ? 1 : 0), {code, false, true}});
    sched.push_back({f + 4, {code, false, false}});
    if (shift) sched.push_back({f + 4, {0x12, false, false}});
    f += c == '\n' ? 30 : 6;   // BASIC is busy for a while after Return
  }
}

static void key_event(const PS2& e) {
  ps2_toggle ^= 1;
  top->ps2_key = (ps2_toggle << 10) | (e.press << 9) | (e.ext << 8) | e.code;
}

// ---------------------------------------------------------------- helpers
static std::vector<uint8_t> read_file(const std::string& p) {
  std::vector<uint8_t> d; FILE* f = fopen(p.c_str(), "rb");
  if (!f) { fprintf(stderr, "cannot open %s\n", p.c_str()); exit(1); }
  fseek(f, 0, SEEK_END); d.resize(ftell(f)); fseek(f, 0, SEEK_SET);
  if (fread(d.data(), 1, d.size(), f) != d.size()) { fprintf(stderr, "short read %s\n", p.c_str()); exit(1); }
  fclose(f); return d;
}

static void tick() {
  top->clk = 0; top->eval();
  top->clk = 1; top->eval();
  cycles++;
}

static void download_rom(const std::vector<uint8_t>& d, bool sel128) {
  top->rom_sel128 = sel128;
  for (size_t i = 0; i < d.size() && i < (sel128 ? 32768u : 65536u); i++) {
    top->rom_addr = i; top->rom_data = d[i]; top->rom_wr = 1; tick();
    top->rom_wr = 0; tick();
  }
}

// audio: 6-bit DAC sampled at 48 kHz
static FILE* wav = nullptr; static uint32_t wav_n = 0;
static void wav_hdr(FILE* f, uint32_t n) {
  auto w32 = [&](uint32_t x) { fwrite(&x, 4, 1, f); }; auto w16 = [&](uint16_t x) { fwrite(&x, 2, 1, f); };
  fwrite("RIFF", 1, 4, f); w32(36 + n * 2); fwrite("WAVEfmt ", 1, 8, f); w32(16); w16(1); w16(1);
  w32(48000); w32(96000); w16(2); w16(16); fwrite("data", 1, 4, f); w32(n * 2);
}

static void usage() {
  printf("Vlynx_sim options:\n"
         "  --model 48|96|96s|128   machine (default 48)\n"
         "  --frames N              frames to run (default 100)\n"
         "  --shots A,B,..          save frames A, B .. as PNG\n"
         "  --every N               save every Nth frame\n"
         "  --outdir DIR            output directory (default out)\n"
         "  --type 'TEXT@FRAME'     type TEXT from FRAME (\\n = Return); repeatable\n"
         "  --rom FILE              download FILE as boot.rom (index 0) before reset\n"
         "  --rom128 FILE           download FILE as boot1.rom (index 40h)\n"
         "  --tape FILE.tap         play a Lynx TAP through rtl/lynx_tap.sv (motor-driven)\n"
         "  --tape-log              log motor changes and tape position\n"
         "  --no-overlay            OSD Tape overlay Off\n"
         "  --turbo                 CPU 4x\n"
         "  --wav FILE              write the DAC as a 48 kHz WAV\n"
         "  --disk FILE.LDF         mount a disk image (read only)\n"
         "  --until-idle N          stop N frames after the tape motor last stopped (once it ran)\n"
         "  --final FILE.PNG        save the last frame\n"
         "  --quiet                 no per-frame log\n");
}

static std::string disk_path, final_png;
static int until_idle = 0;
static std::vector<uint8_t> disk_img;
// SD block interface, as hps_io: ack, 512 bytes into the buffer, ack low
static void sd_service() {
  if (!top->sd_rd && !top->sd_wr) return;
  bool rd = top->sd_rd; size_t off = (size_t)top->sd_lba * 512;
  printf("frame %d: sd %s lba %u\n", frame, rd ? "read" : "write", top->sd_lba);
  top->sd_ack = 1; tick(); tick();
  for (int i = 0; i < 512 && rd; i++) {
    top->sd_buff_addr = i; top->sd_buff_dout = off + i < disk_img.size() ? disk_img[off + i] : 0;
    top->sd_buff_wr = 1; tick(); top->sd_buff_wr = 0; tick();
  }
  for (int i = 0; i < 1100 && !rd; i++) tick();
  top->sd_ack = 0; tick(); tick();
}

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    auto next = [&]() -> std::string { if (i + 1 >= argc) { usage(); exit(1); } return argv[++i]; };
    if (a == "--help" || a == "-h") { usage(); return 0; }
    else if (a == "--model") {
      std::string m = next();
      model = m == "48" ? 0 : m == "96" ? 1 : m == "96s" ? 2 : m == "128" ? 3 : -1;
      if (model < 0) { usage(); return 1; }
    }
    else if (a == "--frames") run_frames = atoi(next().c_str());
    else if (a == "--every") every = atoi(next().c_str());
    else if (a == "--shots") { std::string s = next(); char* p = &s[0];
      for (char* t = strtok(p, ","); t; t = strtok(nullptr, ",")) shots.insert(atoi(t)); }
    else if (a == "--outdir") outdir = next();
    else if (a == "--type") { std::string s = next(); size_t at = s.rfind('@');
      if (at == std::string::npos) { usage(); return 1; }
      schedule_text(atoi(s.c_str() + at + 1), s.substr(0, at)); }
    else if (a == "--rom") rom_path = next();
    else if (a == "--rom128") rom128_path = next();
    else if (a == "--turbo") turbo = true;
    else if (a == "--tape") tape_path = next();
    else if (a == "--tape-log") tape_log = true;
    else if (a == "--no-overlay") no_overlay = true;
    else if (a == "--wav") wav_path = next();
    else if (a == "--disk") disk_path = next();
    else if (a == "--until-idle") until_idle = atoi(next().c_str());
    else if (a == "--final") final_png = next();
    else if (a == "--quiet") quiet = true;
    else if (a[0] == '+') {}
    else { fprintf(stderr, "unknown option %s\n", a.c_str()); usage(); return 1; }
  }
  { std::string c = "mkdir -p '" + outdir + "'"; if (system(c.c_str())) {} }

  top = new Vlynx_sim;
  top->model = model; top->turbo = turbo; top->reset = 1;
  top->joy0 = 0xFF; top->joy1 = 0xFF; top->tape_adc = 0; top->ps2_key = 0;
  if (!tape_path.empty()) tape_img = read_file(tape_path);
  top->tape_size = tape_img.size(); top->tape_ack = 0; top->tape_rewind = 1;
  top->is_wav = tape_img.size() > 12 && !memcmp(tape_img.data(), "RIFF", 4);
  for (int i = 0; i < 100; i++) tick();
  if (!rom_path.empty()) download_rom(read_file(rom_path), false);
  if (!rom128_path.empty()) download_rom(read_file(rom128_path), true);
  for (int i = 0; i < 1000; i++) tick();
  // the tape image through the download port, as hps_io sends it
  top->overlay_on = !no_overlay;
  top->dl_start = 1; tick(); top->dl_start = 0; top->dl_busy = 1;
  for (uint8_t b : tape_img) { top->dl_data = b; top->dl_wr = 1; tick(); top->dl_wr = 0; tick(); }
  top->dl_busy = 0; for (int i = 0; i < 20000; i++) tick();
  top->reset = 0; top->tape_rewind = 0;
  top->sd_ack = 0; top->sd_buff_wr = 0;
  if (!disk_path.empty()) { disk_img = read_file(disk_path); top->img_size = disk_img.size();
    top->img_mounted = 1; tick(); top->img_mounted = 0; }

  if (!wav_path.empty()) { wav = fopen(wav_path.c_str(), "wb"); wav_hdr(wav, 0); }
  uint64_t next_sample = 0;
  size_t si = 0;
  std::sort(sched.begin(), sched.end(), [](const Sched& a, const Sched& b) { return a.frame < b.frame; });

  while (frame < run_frames) {
    tick();
    video_step();
    sd_service();
    { static int pd = -1, pr = -1; if (!disk_img.empty() && (top->dos_run != pd || top->disk_read != pr)) {
        pd = top->dos_run; pr = top->disk_read;
        printf("frame %d: disk %s, dos_run %d, disk_read %d\n", frame, top->disk_cpm ? "CP/M" : "Lynx DOS", pd, pr); } }
    // tape image: answer a request a few clocks later (DDR3-like latency)
    top->tape_ack = 0;
    if (top->tape_req) { if (++ack_delay >= 8) { ack_delay = 0; top->tape_ack = 1;
        top->tape_data = top->tape_addr < tape_img.size() ? tape_img[top->tape_addr] : 0; } }
    else ack_delay = 0;
    if (tape_log) { static int pm = -1; if (top->motor != pm) { pm = top->motor;
        printf("frame %d: motor %s, TAPE %d (cf %04X), tape pos %u/%zu%s\n", frame, pm ? "on" : "off", top->tape_spd, top->dbg_cf, top->tape_pos, tape_img.size(),
               top->tape_eot ? " (end)" : ""); } }
    // one key event per 1000 clocks, so matrix.v sees each ps2_key toggle
    if (si < sched.size() && sched[si].frame <= frame && cycles % 1000 == 0) key_event(sched[si++].ev);
    if (wav && cycles >= next_sample) {
      int16_t s = (int16_t)((top->sound << 9) - 16384); fwrite(&s, 2, 1, wav); wav_n++;
      next_sample += CLK_HZ / 48000;
    }
    if (top->VSync && !prev_vs) {             // new frame
      last_w = max_x; last_h = vy;
      if (shots.count(frame) || (every && frame % every == 0)) {
        char name[512]; snprintf(name, sizeof name, "%s/frame_%05d.png", outdir.c_str(), frame);
        if (last_w > 0 && last_h > 0) write_png(name, std::min(last_w, FB_W), std::min(last_h, FB_H), fb, FB_W);
      }
      if (!quiet && frame % 25 == 0)
        printf("frame %d  %dx%d  pc~%04X  motor %d  %.2f s\n", frame, last_w, last_h, top->dbg_a,
               top->motor, cycles / (double)CLK_HZ);
      frame++; vy = 0; max_x = 0;
      { static int ran = 0, off_at = 0; if (top->motor) { ran = 1; off_at = frame; }
        if (until_idle && ran && frame - off_at >= until_idle) run_frames = frame; }
    }
    prev_vs = top->VSync;
  }
  if (!final_png.empty() && last_w > 0) write_png(final_png.c_str(), std::min(last_w, FB_W), std::min(last_h, FB_H), fb, FB_W);
  printf("done: %d frames, picture %dx%d, %.2f s emulated\n", frame, last_w, last_h, cycles / (double)CLK_HZ);
  if (wav) { fseek(wav, 0, SEEK_SET); wav_hdr(wav, wav_n); fclose(wav); }
  top->final(); delete top;
  return 0;
}
