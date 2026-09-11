#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Compile DWED's CP/M-style help directory without historical DOS binaries."""
import argparse
from pathlib import Path
import struct


def compile_help(source):
    # Match HELP.PAS's fixed 16-byte records and CRLF source offsets.
    if source.replace(b'\r\n', b'').find(b'\n') != -1:
        raise ValueError('help source must use CRLF line endings')
    topics = []
    offset = 0
    for line in source.split(b'\r\n'):
        if len(line) > 255:
            raise ValueError('help line exceeds historical short-string limit')
        if len(line) > 4 and line.startswith(b'///') and 48 <= line[3] <= 57:
            topics.append((line[4:16].upper().ljust(12, b' '), offset + len(line), line[3] - 48))
        offset += len(line) + 2
    count = ((len(topics) + 1 + 7) // 8) * 8
    header = bytearray()
    for name, offset, level in topics:
        offset += count * 16
        header += struct.pack('<12sHBB', name, offset >> 7, offset & 127, level)
    header += struct.pack('<12sHBB', b'$'.ljust(12, b' '), 0, 0, 0) * (count - len(topics))
    data = header + source
    data += b'\x1a' * (128 - len(data) % 128)
    return bytes(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    data = compile_help(args.source.read_bytes())
    (args.output / 'dwedhelp.hlp').write_bytes(data)
    rows = [','.join('$%02x' % b for b in data[i:i+16]) for i in range(0, len(data), 16)]
    (args.output / 'helpdata.inc').write_text(
        'const helpbin: array[0..%d] of byte = (\n' % (len(data)-1) + ',\n'.join(rows) + '\n);\n')


if __name__ == '__main__':
    main()
