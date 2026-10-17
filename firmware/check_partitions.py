#!/usr/bin/env python3
import csv, sys
rows = [r for r in csv.reader(open(sys.argv[1])) if r and not r[0].startswith("#")]
parts = [(r[0].strip(), int(r[3], 16), int(r[4], 16)) for r in rows]
end = 0x8000 + 0x1000
for name, off, size in parts:
    assert off % 0x1000 == 0 and size % 0x1000 == 0, f"{name} not 4 KiB aligned"
    assert off >= end, f"{name} overlaps previous partition (starts 0x{off:X}, previous ends 0x{end:X})"
    end = off + size
assert end <= 0x800000, f"table ends at 0x{end:X} > 8 MiB"
d = {n: (o, s) for n, o, s in parts}
assert d["main.avm"][0] == 0x250000, "main.avm must stay at 0x250000 (installer appOffset)"
assert d["boot.avm"][0] == 0x1D0000
assert d["apps"][0] + d["apps"][1] == 0x800000, "apps must fill the flash"
print(f"OK: {len(parts)} partitions, ends at 0x{end:X}")
