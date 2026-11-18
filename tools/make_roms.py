#!/usr/bin/env python3
# Builds the ROM images from the single ROMs in roms/src (MAME names, sets lynx48k, lynx96k,
# lynx128k; dosrom.rom is the LynxDOS / XDOS disk ROM started with XROM). From Shaeon's
# tools/make_roms.py (github.com/shaeon/Lynx_MiSTer); also writes rtl/boot.hex and rtl/boot1.hex,
# the built-in images the core starts with when games/Lynx48/boot.rom / boot1.rom are absent.
#
#   python3 tools/make_roms.py
#
# boot.rom, 8 pages of 8K (Kyp's lynx.poseidon romP order):
#   0 48K-1  1 48K-2  2 96K-1  3 96K-2  4 96K-3 (4K + FF)  5 96K-3 Scorpion  6 XDOS  7 FF
# boot1.rom, 4 pages of 8K: 0 128K-1  1 128K-2  2 128K-3  3 XDOS
import hashlib, os, sys

here = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(here, '..', 'roms', 'src')

def page(name):
    d = open(os.path.join(src, name), 'rb').read()
    if len(d) > 8192:
        sys.exit(name + ': more than 8K')
    return d + b'\xff' * (8192 - len(d))

dos = page('dosrom.rom')
boot = b''.join([page('lynx48-1.ic46'), page('lynx48-2.ic45'),
                 page('lynx9646.ic46'), page('lynx9645.ic45'),
                 page('lynx9644.ic44'), page('skorprom.ic44'),
                 dos, b'\xff' * 8192])
boot1 = b''.join([page('lynx128-1.ic1'), page('lynx128-2.ic2'), page('lynx128-3.ic3'), dos])

for name, data in (('boot', boot), ('boot1', boot1)):
    open(os.path.join(here, '..', 'roms', name + '.rom'), 'wb').write(data)
    with open(os.path.join(here, '..', 'rtl', name + '.hex'), 'w') as f:
        f.write(''.join('%02X\n' % b for b in data))
    print('%-9s %6d bytes  sha1 %s' % (name + '.rom', len(data), hashlib.sha1(data).hexdigest()))
