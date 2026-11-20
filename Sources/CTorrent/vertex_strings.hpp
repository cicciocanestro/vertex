#pragma once

// UTF-8 validation and JSON string escaping used by the snapshot encoder.
//
// Kept free of libtorrent so the same code can be compiled into the libFuzzer
// harness (Fuzz/strings_fuzzer.cpp) without pulling the engine.

#include <cstddef>
#include <cstdio>
#include <string>

namespace vertex {

/// Returns the length in bytes (1..4) of a valid RFC 3629 UTF-8 code point at
/// `p` when at least that many bytes are available in `remaining`, or 0 when
/// the byte sequence is malformed (overlong, surrogate, or > U+10FFFF).
inline std::size_t utf8_sequence_length(unsigned char const* p, std::size_t remaining)
{
    if (remaining == 0)
        return 0;
    unsigned char const c = p[0];
    if (c < 0x80)
        return 1;

    if (c >= 0xC2 && c <= 0xDF)
    {
        if (remaining < 2)
            return 0;
        return (p[1] & 0xC0) == 0x80 ? 2 : 0;
    }

    if (c >= 0xE0 && c <= 0xEF)
    {
        if (remaining < 3)
            return 0;
        unsigned char const c1 = p[1];
        unsigned char const c2 = p[2];
        if ((c2 & 0xC0) != 0x80)
            return 0;
        if (c == 0xE0)
            return (c1 >= 0xA0 && c1 <= 0xBF) ? 3 : 0; // reject overlong
        if (c == 0xED)
            return (c1 >= 0x80 && c1 <= 0x9F) ? 3 : 0; // reject surrogates
        return (c1 & 0xC0) == 0x80 ? 3 : 0;
    }

    if (c >= 0xF0 && c <= 0xF4)
    {
        if (remaining < 4)
            return 0;
        unsigned char const c1 = p[1];
        unsigned char const c2 = p[2];
        unsigned char const c3 = p[3];
        if ((c2 & 0xC0) != 0x80 || (c3 & 0xC0) != 0x80)
            return 0;
        if (c == 0xF0)
            return (c1 >= 0x90 && c1 <= 0xBF) ? 4 : 0; // reject overlong
        if (c == 0xF4)
            return (c1 >= 0x80 && c1 <= 0x8F) ? 4 : 0; // reject > U+10FFFF
        return (c1 & 0xC0) == 0x80 ? 4 : 0;
    }

    return 0;
}

/// Validate UTF-8 strictly according to RFC 3629 without allocating.
/// Rejects overlong sequences, UTF-16 surrogates, and values above U+10FFFF.
inline bool is_valid_utf8(std::string const& input)
{
    auto const* bytes = reinterpret_cast<unsigned char const*>(input.data());
    std::size_t i = 0;
    std::size_t const n = input.size();
    while (i < n)
    {
        std::size_t const len = utf8_sequence_length(bytes + i, n - i);
        if (len == 0)
            return false;
        i += len;
    }
    return true;
}

inline std::string json_escape(std::string const& input)
{
    std::string out;
    out.reserve(input.size() + 16);
    auto const* bytes = reinterpret_cast<unsigned char const*>(input.data());
    std::size_t i = 0;
    std::size_t const n = input.size();

    while (i < n)
    {
        std::size_t const len = utf8_sequence_length(bytes + i, n - i);
        if (len == 1)
        {
            unsigned char const c = bytes[i];
            switch (c)
            {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20)
                {
                    char buffer[7];
                    std::snprintf(buffer, sizeof(buffer), "\\u%04x", c);
                    out += buffer;
                }
                else
                {
                    out += static_cast<char>(c);
                }
            }
            ++i;
        }
        else if (len > 1)
        {
            out.append(input, i, len);
            i += len;
        }
        else
        {
            out += "\\ufffd";
            ++i;
        }
    }
    return out;
}

} // namespace vertex
