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
#include <string_view>

namespace vertex {

/// Returns the length in bytes (1..4) of a valid RFC 3629 UTF-8 code point at
/// `p` when at least that many bytes are available in `remaining`, or 0 when
/// the byte sequence is malformed (overlong, surrogate, or > U+10FFFF).
inline std::size_t utf8_sequence_length(unsigned char const* p, std::size_t remaining) noexcept
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
inline bool is_valid_utf8(std::string_view input) noexcept
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

/// Trims leading and trailing ASCII whitespace (` `, `\t`, `\n`, `\r`).
inline std::string trim_ascii_whitespace(std::string_view input)
{
    auto const first = input.find_first_not_of(" \t\n\r");
    if (first == std::string_view::npos)
        return {};
    auto const last = input.find_last_not_of(" \t\n\r");
    return std::string(input.substr(first, last - first + 1));
}

/// Validates a tracker URL syntax: RFC 3986 scheme `[A-Za-z][A-Za-z0-9+.-]*://`
/// followed by a non-empty host without ASCII whitespace or control bytes.
inline bool is_valid_tracker_url_syntax(std::string_view url) noexcept
{
    for (unsigned char const c : url)
    {
        if (c <= 0x20 || c == 0x7f)
            return false;
    }
    auto const pos = url.find("://");
    if (pos == std::string_view::npos || pos == 0)
        return false;

    auto const is_alpha = [](char c) noexcept {
        return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
    };
    auto const is_scheme_char = [&](char c) noexcept {
        return is_alpha(c) || (c >= '0' && c <= '9') || c == '+' || c == '.' || c == '-';
    };

    if (!is_alpha(url[0]))
        return false;
    for (std::size_t i = 1; i < pos; ++i)
    {
        if (!is_scheme_char(url[i]))
            return false;
    }

    std::string_view rest = url.substr(pos + 3);
    auto const slash = rest.find_first_of("/?#");
    std::string_view authority = slash == std::string_view::npos ? rest : rest.substr(0, slash);
    if (authority.empty())
        return false;

    auto const at = authority.rfind('@');
    std::string_view hostport = at == std::string_view::npos ? authority : authority.substr(at + 1);
    if (hostport.empty())
        return false;

    if (hostport.front() == '[')
    {
        auto const close = hostport.find(']');
        if (close == std::string_view::npos || close <= 1)
            return false;
        if (close + 1 < hostport.size() && hostport[close + 1] != ':')
            return false;
        return true;
    }

    auto const colon = hostport.find(':');
    std::string_view const host = colon == std::string_view::npos ? hostport : hostport.substr(0, colon);
    return !host.empty();
}

/// Trims whitespace, expands a leading `~`, and turns a file destination (for
/// example a dropped `.torrent`) into its folder. Kept here so the fuzz harness
/// can exercise it without linking libtorrent.
inline std::string normalized_save_path(
    std::string const& requested,
    std::string const& fallback)
{
    namespace fs = std::filesystem;
    auto expand_tilde = [](std::string& s) {
        // Expand only standalone "~" or "~/...": "~alice" refers to another user
        // or a literal directory name and must not be concatenated onto $HOME.
        if (s == "~" || s.rfind("~/", 0) == 0)
        {
            char const* home = std::getenv("HOME");
            if (home && *home)
                s = std::string(home) + s.substr(1);
        }
    };

    std::string trimmed_fallback = trim_ascii_whitespace(fallback);
    expand_tilde(trimmed_fallback);

    std::string candidate = trim_ascii_whitespace(requested);
    if (candidate.empty())
        candidate = trimmed_fallback;
    else
        expand_tilde(candidate);

    if (candidate.empty())
        return fallback;

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

    return candidate.empty() ? (trimmed_fallback.empty() ? fallback : trimmed_fallback) : candidate;
}

} // namespace vertex
