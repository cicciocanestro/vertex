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

The table is IPv4 only: IPv6 endpoints are reported without a flag.
"""

import struct
import sys
import zlib


def varint(value):
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
    return (
        (int(parts[0]) << 24)
        | (int(parts[1]) << 16)
        | (int(parts[2]) << 8)
        | int(parts[3])
    )


def encode(source, destination):
    rows = []
    with open(source, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            start, end, code = line.split(",")
            if ":" in start:
                continue  # IPv6 is not part of this table
            if len(code) != 2:
                raise ValueError(f"unexpected country code: {code}")
            rows.append((ipv4(start), ipv4(end), code))

    rows.sort(key=lambda row: row[0])
    codes = sorted({row[2] for row in rows})
    if len(codes) > 255:
        raise SystemExit("more than 255 country codes")

    index = {code: position for position, code in enumerate(codes)}
    payload = bytearray(struct.pack("<H", len(codes)))
    for code in codes:
        payload += code.encode("ascii")

    previous = 0
    for start, end, code in rows:
        if start < previous:
            raise SystemExit("rows are not sorted")
        payload += varint(start - previous)
        previous = start
        payload += varint(end - start)
        payload.append(index[code])

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
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} <dbip.csv> <country-v4.bin.z>")
    encode(sys.argv[1], sys.argv[2])
