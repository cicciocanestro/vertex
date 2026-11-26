// libFuzzer harness for the UTF-8 validation and JSON escaping used by the
// snapshot encoder. Build with Scripts/run-fuzz.sh.
//
// The harness asserts the invariants the encoder relies on, so a fuzz failure
// is a real bug in the escaping, not just a crash.

#include "vertex_strings.hpp"

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>
#include <unistd.h>

namespace {

[[noreturn]] void fail(char const* why)
{
    std::fprintf(stderr, "invariant violated: %s\n", why);
    std::abort();
}

bool is_hex_digit(unsigned char c) noexcept
{
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

struct ScopedTempFallback
{
    std::string root;
    std::string fallback;

    ScopedTempFallback()
    {
        char tmpl[] = "/tmp/vertex-fuzz.XXXXXX";
        if (char* created = ::mkdtemp(tmpl))
        {
            root = created;
            fallback = root + "/downloads";
        }
        else
        {
            fallback = "/tmp/vertex-fuzz-fallback";
        }
    }

    ~ScopedTempFallback()
    {
        if (!root.empty())
        {
            std::error_code ec;
            std::filesystem::remove_all(root, ec);
        }
    }
};

std::string const& fuzz_fallback_path()
{
    static ScopedTempFallback const instance;
    return instance.fallback;
}

} // namespace

extern "C" int LLVMFuzzerTestOneInput(std::uint8_t const* data, std::size_t size)
{
    std::string const input(reinterpret_cast<char const*>(data), size);
    std::string const escaped = vertex::json_escape(input);

    // Every backslash must introduce a valid RFC 8259 escape sequence; quotes
    // and raw control bytes (< 0x20) must never appear unescaped.
    for (std::size_t i = 0; i < escaped.size();)
    {
        unsigned char const c = static_cast<unsigned char>(escaped[i]);
        if (c == '\\')
        {
            if (i + 1 >= escaped.size())
                fail("dangling escape at end of output");
            unsigned char const next = static_cast<unsigned char>(escaped[i + 1]);
            switch (next)
            {
            case '"':
            case '\\':
            case '/':
            case 'b':
            case 'f':
            case 'n':
            case 'r':
            case 't':
                i += 2;
                break;
            case 'u':
                if (i + 5 >= escaped.size()
                    || !is_hex_digit(static_cast<unsigned char>(escaped[i + 2]))
                    || !is_hex_digit(static_cast<unsigned char>(escaped[i + 3]))
                    || !is_hex_digit(static_cast<unsigned char>(escaped[i + 4]))
                    || !is_hex_digit(static_cast<unsigned char>(escaped[i + 5])))
                {
                    fail("invalid \\uXXXX escape in output");
                }
                i += 6;
                break;
            default:
                fail("invalid escape character in output");
            }
            continue;
        }
        if (c == '"')
            fail("unescaped quote in output");
        if (c < 0x20)
            fail("raw control byte in output");
        ++i;
    }

    // Malformed input becomes U+FFFD, so the output is always valid UTF-8.
    if (!vertex::is_valid_utf8(escaped))
        fail("escaped output is not valid UTF-8");

    // With nothing to escape, the string must pass through unchanged.
    bool needsEscape = false;
    for (unsigned char c : input)
    {
        if (c < 0x20 || c == '"' || c == '\\' || c >= 0x80)
        {
            needsEscape = true;
            break;
        }
    }
    if (!needsEscape && escaped != input)
        fail("plain ASCII input was modified");

    // Path normalization must never crash, never return an empty string when a
    // fallback exists, and never smuggle a NUL byte into a save path. The real
    // callers pass C strings, so the fuzz input is cut at the first NUL: an
    // embedded NUL is outside the function's contract.
    std::string const pathInput = input.substr(0, input.find('\0'));
    std::string const& fallback = fuzz_fallback_path();
    std::string const normalized = vertex::normalized_save_path(pathInput, fallback);
    if (normalized.empty())
        fail("path normalization returned an empty string");
    if (normalized.find('\0') != std::string::npos)
        fail("NUL byte in normalized path");
    if (pathInput.empty() && normalized != fallback)
        fail("empty request did not use the fallback");

    // Exercise tracker URL validation against arbitrary inputs too.
    (void)vertex::is_valid_tracker_url_syntax(pathInput);

    return 0;
}
