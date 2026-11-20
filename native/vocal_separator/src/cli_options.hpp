// Command line of lyricforge-separator.
//
//   lyricforge-separator --model <htdemucs.onnx> --input <mix.wav>
//                        --output-dir <dir> [--provider auto|dml|cpu]
//                        [--threads N] [--vocals-index N]
//                        [--max-seconds S] [--no-accompaniment]
//   lyricforge-separator --version | --help
//
// Exit codes are part of the contract with the app (see ExitCode).
#ifndef LFSEP_CLI_OPTIONS_HPP
#define LFSEP_CLI_OPTIONS_HPP

#include <string>
#include <vector>

namespace lfsep
{

// Bumped whenever the produced stem can change for the same input, so the app
// knows a cached stem is stale. Must match the separator manifest.
constexpr const char *kSeparatorRevision = "htdemucs-ft-vocals-onnx-v1";
constexpr const char *kSeparatorVersion = "1.0.0";
constexpr int kRequiredSampleRate = 44100;

enum class ExitCode : int
{
    ok = 0,
    usage = 2,
    input = 3,
    model = 4,
    output = 5,
    internal = 6,
};

enum class Provider
{
    automatic,
    directml,
    cpu,
};

const char *provider_name(Provider provider);

struct CliOptions
{
    std::string model;
    std::string input;
    std::string output_dir;
    Provider provider = Provider::automatic;
    int threads = 0; // 0 = let ONNX Runtime decide
    int vocals_index = 3; // htdemucs order: drums, bass, other, vocals
    double max_seconds = 1200.0;
    bool accompaniment = true;
    bool show_help = false;
    bool show_version = false;
};

struct ParseResult
{
    bool ok = false;
    std::string error;
    CliOptions options;
};

// Parses the arguments after the program name.
ParseResult parse_cli(const std::vector<std::string> &args);

std::string usage_text();

} // namespace lfsep

#endif // LFSEP_CLI_OPTIONS_HPP
