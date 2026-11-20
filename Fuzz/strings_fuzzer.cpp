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
#include <string>

namespace {

[[noreturn]] void fail(char const* why)
{
    std::fprintf(stderr, "invariant violated: %s\n", why);
    std::abort();
}

} // namespace

extern "C" int LLVMFuzzerTestOneInput(std::uint8_t const* data, std::size_t size)
{
    std::string const input(reinterpret_cast<char const*>(data), size);
    std::string const escaped = vertex::json_escape(input);

    // A backslash always introduces an escape pair; a quote must never appear
    // unescaped, and control bytes must be encoded as \u00XX or a short escape.
    for (std::size_t i = 0; i < escaped.size();)
    {
        unsigned char const c = static_cast<unsigned char>(escaped[i]);
        if (c == '\\')
        {
            if (i + 1 >= escaped.size())
                fail("dangling escape at end of output");
            i += 2;
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

    return 0;
}
