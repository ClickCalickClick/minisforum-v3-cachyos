#!/usr/bin/env python3
"""Patch a decompiled Minisforum DSDT (dsdt.dsl) in place so the kernel's
st_lsm6dsx driver binds the accelerometer:

  * EisaId ("SMOCF05") -> EisaId ("SMO8B30")   (_HID and _CID of Device STS)
  * DefinitionBlock OEM revision += 0x10         (the kernel only loads an
                                                 override with a higher rev)

Refuses (exit 1) if the table does not look like the one this was worked out
on, rather than guessing.
"""
import re
import sys

path = sys.argv[1]
src = open(path, encoding="latin-1").read()

n = src.count('EisaId ("SMOCF05")')
if n not in (1, 2):
    sys.exit(f"expected 1-2 'EisaId (\"SMOCF05\")' entries, found {n}")
src = src.replace('EisaId ("SMOCF05")', 'EisaId ("SMO8B30")')

m = re.search(r'^DefinitionBlock \([^)]*,\s*0x([0-9A-Fa-f]{8})\s*\)', src, re.M)
if not m:
    sys.exit("DefinitionBlock header not found")
old = int(m.group(1), 16)
src = src[:m.start(1)] + f"{old + 0x10:08X}" + src[m.end(1):]

open(path, "w", encoding="latin-1").write(src)
print(f"patched {n} id(s); OEM revision 0x{old:08X} -> 0x{old + 0x10:08X}")
