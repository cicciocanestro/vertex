#!/usr/bin/env python3
"""Encode a DB-IP country CSV into the compact table Vertex ships.

Output format (little endian):
  uint32   size of the decompressed payload
  bytes    raw DEFLATE stream (no zlib/gzip wrapper, see `COMPRESSION_ZLIB`
           in Apple's Compression framework, which expects raw deflate)

Decompressed payload:
  uint16   number of country codes
  N x 2    ASCII country codes, sorted
  records  repeated until the end:
             varint  delta from the previous record's start address
             varint  address range length
             uint8   country code index

The same format is used for IPv6 (`country-v6.bin.z`): start deltas and range
lengths are varints over 128-bit unsigned values instead of 32-bit ones.
"""

import csv
import ipaddress
import struct
import sys
import zlib

MAX_DECOMPRESSED_BYTES = 16 * 1024 * 1024


def varint(value):
    if value < 0:
        raise ValueError(f"varint requires a non-negative integer, got {value}")
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def ipv4(text):
    parts = text.split(".")
    if len(parts) != 4:
        raise ValueError(f"not an IPv4 address: {text}")
    octets = [int(part) for part in parts]
    if any(octet < 0 or octet > 255 for octet in octets):
        raise ValueError(f"IPv4 octet out of range: {text}")
    return (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3]


def encode(source, destination, version="v4"):
    rows = []
    with open(source, "r", encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle)
        for line_num, fields in enumerate(reader, start=1):
            if not fields or (len(fields) == 1 and not fields[0].strip()):
                continue
            if len(fields) != 3:
                raise ValueError(f"line {line_num}: expected 3 CSV columns, got {len(fields)}")
            start = fields[0].strip()
            end = fields[1].strip()
            code = fields[2].strip().upper()
            is_v6 = ":" in start
            if version == "v6":
                if not is_v6:
                    continue
                first = int(ipaddress.IPv6Address(start))
                last = int(ipaddress.IPv6Address(end))
            else:
                if is_v6:
                    continue
                first = ipv4(start)
                last = ipv4(end)
            if last < first:
                raise ValueError(f"line {line_num}: invalid IP range (end < start): {start}..{end}")
            if len(code) != 2 or not code.isascii() or not code.isalpha():
                raise ValueError(f"line {line_num}: unexpected country code: {code!r}")
            rows.append((first, last, code))

    if not rows:
        raise SystemExit(f"no {version} rows found in {source}")

    rows.sort(key=lambda row: (row[0], row[1]))
    codes = sorted({row[2] for row in rows})
    if len(codes) > 256:
        raise SystemExit(f"more than 256 country codes ({len(codes)})")

    index = {code: position for position, code in enumerate(codes)}
    payload = bytearray(struct.pack("<H", len(codes)))
    for code in codes:
        payload += code.encode("ascii")

    previous_start = 0
    previous_end = -1
    for row_index, (start, end, code) in enumerate(rows):
        if end < start:
            raise SystemExit(f"row {row_index}: end ({end}) < start ({start})")
        if row_index > 0 and start < previous_start:
            raise SystemExit("rows are not sorted")
        if row_index > 0 and start <= previous_end:
            raise SystemExit(
                f"row {row_index}: overlapping IP ranges ({start}..{end} overlaps ..{previous_end})"
            )
        payload += varint(start - previous_start)
        previous_start = start
        previous_end = end
        payload += varint(end - start)
        payload.append(index[code])

    if len(payload) > MAX_DECOMPRESSED_BYTES:
        raise SystemExit(
            f"decompressed payload ({len(payload)} bytes) exceeds {MAX_DECOMPRESSED_BYTES} byte limit"
        )

    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
    compressed = compressor.compress(bytes(payload)) + compressor.flush()
    with open(destination, "wb") as handle:
        handle.write(struct.pack("<I", len(payload)))
        handle.write(compressed)

    print(
        f"rows={len(rows)} codes={len(codes)} "
        f"raw={len(payload)} bytes compressed={len(compressed)} bytes"
    )


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4):
        raise SystemExit(
            f"usage: {sys.argv[0]} <dbip.csv> <output.bin.z> [v4|v6]"
        )
    version = sys.argv[3] if len(sys.argv) == 4 else "v4"
    if version not in ("v4", "v6"):
        raise SystemExit("version must be v4 or v6")
    encode(sys.argv[1], sys.argv[2], version)
