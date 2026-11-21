#pragma once

// UTF-8 validation and JSON string escaping used by the snapshot encoder.
//
// Kept free of libtorrent so the same code can be compiled into the libFuzzer
// harness (Fuzz/strings_fuzzer.cpp) without pulling the engine.

#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
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

/// Trims whitespace, expands a leading `~`, and turns a file destination (for
/// example a dropped `.torrent`) into its folder. Kept here so the fuzz harness
/// can exercise it without linking libtorrent.
inline std::string normalized_save_path(
    std::string const& requested,
    std::string const& fallback)
{
    namespace fs = std::filesystem;
    std::string candidate = requested.empty() ? fallback : requested;

    // MEDIUM #7: trim and expand ~ exactly like Preferences.resolvedDownloadPath,
    // so the path the Swift side normalizes and the one the C++ side uses for
    // resume data and save_path can never drift apart.
    auto trim = [](std::string& s) {
        auto first = s.find_first_not_of(" \t\n\r");
        if (first == std::string::npos) { s.clear(); return; }
        auto last = s.find_last_not_of(" \t\n\r");
        s = s.substr(first, last - first + 1);
    };
    trim(candidate);
    if (!candidate.empty() && candidate[0] == '~')
    {
        char const* home = std::getenv("HOME");
        if (home && *home)
            candidate = std::string(home) + candidate.substr(1);
    }

    std::error_code ec;
    fs::path path(candidate);
    auto status = fs::status(path, ec);
    if (!ec)
    {
        if (fs::is_regular_file(status))
        {
            // A file was used as destination (often a .torrent): use its folder.
            candidate = path.parent_path().string();
        }
    }
    else if (path.extension() == ".torrent")
    {
        candidate = path.parent_path().string();
    }

    return candidate.empty() ? fallback : candidate;
}

} // namespace vertex
