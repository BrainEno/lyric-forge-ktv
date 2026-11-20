#include "app.hpp"

#include <iostream>
#include <string>
#include <vector>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace
{

// Windows passes narrow arguments in the ANSI code page, which cannot hold a
// Chinese or Japanese path on most systems, so read the wide form and carry
// UTF-8 inside the program (paths are converted back in path_from_utf8).
std::string utf8_from_wide(const wchar_t *wide)
{
    const int length =
        WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr, nullptr);
    if (length <= 1)
    {
        return std::string();
    }
    std::string out(static_cast<std::size_t>(length - 1), '\0');
    WideCharToMultiByte(CP_UTF8, 0, wide, -1, out.data(), length, nullptr,
                        nullptr);
    return out;
}

} // namespace

int wmain(int argc, wchar_t **argv)
{
    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i)
    {
        args.push_back(utf8_from_wide(argv[i]));
    }
    return lfsep::run_app(args, std::cout, std::cerr, lfsep::run_demucs_onnx);
}

#else

int main(int argc, char **argv)
{
    std::vector<std::string> args(argv + 1, argv + argc);
    return lfsep::run_app(args, std::cout, std::cerr, lfsep::run_demucs_onnx);
}

#endif
