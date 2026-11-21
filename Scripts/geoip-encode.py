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

import ipaddress
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


def encode(source, destination, version="v4"):
    rows = []
    with open(source, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            start, end, code = line.split(",")
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
            if len(code) != 2:
                raise ValueError(f"unexpected country code: {code}")
            rows.append((first, last, code))

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
    if len(sys.argv) not in (3, 4):
        raise SystemExit(
            f"usage: {sys.argv[0]} <dbip.csv> <output.bin.z> [v4|v6]"
        )
    version = sys.argv[3] if len(sys.argv) == 4 else "v4"
    if version not in ("v4", "v6"):
        raise SystemExit("version must be v4 or v6")
    encode(sys.argv[1], sys.argv[2], version)
