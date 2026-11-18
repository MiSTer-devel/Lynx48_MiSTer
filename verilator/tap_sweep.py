#!/usr/bin/env python3
"""TAP library sweep: load every distinct .TAP in a directory in the sim and save the last frame.

  python3 tap_sweep.py DIR OUTDIR [-j 14] [--limit N] [--filter TEXT]

For each tape (deduplicated by content): the first file's name and type are read from the TAP;
the model is the 128K when the file name says 128K only, the 96K when it says 96K only, else the
48K (with TAPE 5 typed first, so the load is quick). LOAD "NAME" (B) / MLOAD "NAME" (M) is typed,
the sim runs with turbo until the motor has been off for 200 frames, and OUTDIR/NNN.png is the
last frame. OUTDIR/results.tsv: index, model, type, name, motor-off position / size, frames, file.
"""
import argparse, hashlib, os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

SIM = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'obj_dir', 'Vlynx_sim')


def first_file(d):
    i = 1 if d[:1] == b'\xa5' else 0
    if d[i:i + 1] != b'"':
        return None, 'A'
    j = d.find(b'"', i + 1)
    if j < 0 or j - i > 40:
        return None, '?'
    return d[i + 1:j].decode('latin-1'), chr(d[j + 1]) if j + 1 < len(d) else '?'


def model_for(name):
    m = re.findall(r'\(([0-9K\-]+)\)', name)
    tags = ' '.join(m)
    if '128K' in tags and '48K' not in tags and '96K' not in tags:
        return '128'
    if '96K' in tags and '48K' not in tags:
        return '96'
    return '48'


def run(job):
    idx, path, out = job
    d = open(path, 'rb').read()
    name, typ = first_file(d)
    model = model_for(os.path.basename(path))
    if name is None or typ not in 'BM' or any(c in name for c in '\\@'):
        return (idx, model, typ, name or '', 'skipped', 0, path)
    cmd = ('MLOAD' if typ == 'M' else 'LOAD') + ' "' + name + '"\\n'
    args = [SIM, '--model', model, '--turbo', '--tape-log', '--quiet', '--tape', path,
            '--until-idle', '200', '--frames', str(int(600 + len(d) * (0.12 if model == '128' else 0.06))),
            '--final', os.path.join(out, '%03d.png' % idx)]
    if model != '128':
        args += ['--type', 'TAPE 5\\n@150']
    args += ['--type', cmd + '@200']
    r = subprocess.run(args, capture_output=True, text=True)
    offs = re.findall(r'motor off, .*tape pos (\d+)/(\d+)', r.stdout)
    frames = re.findall(r'done: (\d+) frames', r.stdout)
    pos = '%s/%s' % offs[-1] if offs else 'never'
    return (idx, model, typ, name, pos, int(frames[0]) if frames else -1, path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dir'); ap.add_argument('out')
    ap.add_argument('-j', type=int, default=14)
    ap.add_argument('--limit', type=int, default=0)
    ap.add_argument('--filter', default='')
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    seen, files = set(), []
    for root, _, fs in os.walk(a.dir):
        for f in sorted(fs):
            if f.lower().endswith('.tap') and a.filter.lower() in f.lower():
                p = os.path.join(root, f)
                h = hashlib.sha1(open(p, 'rb').read()).hexdigest()
                if h not in seen:
                    seen.add(h); files.append(p)
    files.sort(key=lambda p: os.path.basename(p).lower())
    if a.limit:
        files = files[:a.limit]
    jobs = [(i, p, a.out) for i, p in enumerate(files)]
    with open(os.path.join(a.out, 'results.tsv'), 'w') as t, ThreadPoolExecutor(a.j) as ex:
        for r in ex.map(run, jobs):
            line = '\t'.join(str(x) for x in r)
            print(line, flush=True); t.write(line + '\n'); t.flush()


if __name__ == '__main__':
    main()
