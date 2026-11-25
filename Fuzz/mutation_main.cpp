// Fallback driver for toolchains without the libFuzzer runtime (the local
// CommandLineTools do not ship it). It mutates a seeded corpus and calls the
// same LLVMFuzzerTestOneInput invariants under ASan/UBSan, so the escaping is
// still exercised for a fixed amount of time.

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <random>
#include <vector>

extern "C" int LLVMFuzzerTestOneInput(std::uint8_t const* data, std::size_t size);

namespace {

using Corpus = std::vector<std::vector<std::uint8_t>>;

Corpus makeSeeds()
{
    return {
        {'p', 'l', 'a', 'i', 'n'},
        {'a', '"', 'b', '\\', 'c'},
        {0x0a, 0x09, 0x0d, 0x08, 0x0c},
        {0xc3, 0xa9, 0xe2, 0x9c, 0x93},
        {0xf0, 0x9f, 0x8c, 0x8d},
        {0xe0, 0xa0, 0x80, 0xed, 0x9f, 0xbf, 0xf0, 0x90, 0x80, 0x80, 0xf4, 0x8f, 0xbf, 0xbf},
        {'b', 'a', 'd', 0xff, 0xfe, 0xe0, 0x80, 0x80, 0xed, 0xa0, 0x80},
        {'~', '/', 'D', 'o', 'w', 'n', 'l', 'o', 'a', 'd', 's'},
        {'~', 'a', 'l', 'i', 'c', 'e', '/', 'x', '.', 't', 'o', 'r', 'r', 'e', 'n', 't'},
        {' ', '\t', '\n'},
        {},
    };
}

void mutate(std::vector<std::uint8_t>& input, std::mt19937& rng)
{
    auto const choice = rng() % 6;
    switch (choice)
    {
    case 0: // flip a bit
        if (!input.empty())
            input[rng() % input.size()] ^= std::uint8_t(1u << (rng() % 8));
        break;
    case 1: // overwrite a byte
        if (!input.empty())
            input[rng() % input.size()] = std::uint8_t(rng() % 256);
        break;
    case 2: // insert a byte
        input.insert(input.begin() + std::ptrdiff_t(rng() % (input.size() + 1)),
                     std::uint8_t(rng() % 256));
        break;
    case 3: // erase a byte
        if (!input.empty())
            input.erase(input.begin() + std::ptrdiff_t(rng() % input.size()));
        break;
    case 4: // append a short random blob
    {
        auto const count = std::size_t(1 + rng() % 16);
        for (std::size_t i = 0; i < count; ++i)
            input.push_back(std::uint8_t(rng() % 256));
        break;
    }
    default: // duplicate a slice
        if (!input.empty())
        {
            auto const start = std::size_t(rng() % input.size());
            auto const length = std::size_t(1 + rng() % (input.size() - start));
            std::vector<std::uint8_t> slice(input.begin() + std::ptrdiff_t(start),
                                            input.begin() + std::ptrdiff_t(start + length));
            input.insert(input.end(), slice.begin(), slice.end());
        }
        break;
    }
    if (input.size() > 8192)
        input.resize(8192);
}

} // namespace

int main(int argc, char** argv)
{
    long parsed = 30;
    if (argc > 1 && argv[1] && *argv[1])
    {
        char* end = nullptr;
        parsed = std::strtol(argv[1], &end, 10);
        if (end == argv[1] || parsed <= 0 || parsed > 86400)
            parsed = 30;
    }
    int const seconds = static_cast<int>(parsed);

    std::mt19937 rng(0xC0FFEEu);
    Corpus corpus = makeSeeds();
    auto const deadline = std::chrono::steady_clock::now() + std::chrono::seconds(seconds);
    std::uint64_t iterations = 0;

    while (std::chrono::steady_clock::now() < deadline)
    {
        std::vector<std::uint8_t> input = corpus[rng() % corpus.size()];
        auto const rounds = 1 + rng() % 8;
        for (std::uint32_t round = 0; round < rounds; ++round)
            mutate(input, rng);

        LLVMFuzzerTestOneInput(input.data(), input.size());
        ++iterations;

        // Grow the corpus slowly so later mutations can start from deeper input.
        if (iterations % 1024 == 0 && corpus.size() < 512)
            corpus.push_back(input);
    }

    std::fprintf(stderr, "mutation fuzzing: %llu iterazioni\n",
                 static_cast<unsigned long long>(iterations));
    return 0;
}
