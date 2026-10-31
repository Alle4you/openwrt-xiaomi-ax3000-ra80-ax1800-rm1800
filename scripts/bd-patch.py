#!/usr/bin/env python3
# Changes one byte of a Qualcomm board data file (bdwlan) and fixes the 16-bit
# XOR checksum at offset 0xa, so the XOR of all 16-bit words stays 0xffff.
#
# Usage: bd-patch.py <input> <output> <offset> <value>
# Example (Xiaomi AX3000 RA80): bd-patch.py bdwlan.b24 bdwlan.b24.patched 0x45c 0x00
import struct
import sys


def xor16(b):
    v = 0
    for (w,) in struct.iter_unpack('<H', b):
        v ^= w
    return v


src, dst, off, val = sys.argv[1], sys.argv[2], int(sys.argv[3], 0), int(sys.argv[4], 0)
d = bytearray(open(src, 'rb').read())
assert xor16(d) == 0xffff, 'checksum of the input file does not match'
w = off & ~1
old = struct.unpack_from('<H', d, w)[0]
d[off] = val
new = struct.unpack_from('<H', d, w)[0]
ck = struct.unpack_from('<H', d, 0xa)[0] ^ old ^ new
struct.pack_into('<H', d, 0xa, ck)
assert xor16(d) == 0xffff
open(dst, 'wb').write(d)
print(f'{src.split("/")[-1]}: [0x{off:x}] 0x{old:04x} -> 0x{new:04x}, checksum 0x{ck:04x}')
