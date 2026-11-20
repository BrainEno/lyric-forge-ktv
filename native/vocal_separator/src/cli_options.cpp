#include "cli_options.hpp"

#include <cerrno>
#include <cmath>
#include <cstdlib>

namespace lfsep
{
namespace
{

bool parse_int(const std::string &text, int min, int max, int *out)
{
    if (text.empty())
    {
        return false;
    }
    char *end = nullptr;
    errno = 0;
    const long value = std::strtol(text.c_str(), &end, 10);
    if (errno != 0 || end == nullptr || *end != '\0' || value < min ||
        value > max)
    {
        return false;
    }
    *out = static_cast<int>(value);
    return true;
}

bool parse_seconds(const std::string &text, double *out)
{
    if (text.empty())
    {
        return false;
    }
    char *end = nullptr;
    errno = 0;
    const double value = std::strtod(text.c_str(), &end);
    if (errno != 0 || end == nullptr || *end != '\0' || !std::isfinite(value) ||
        value <= 0.0)
    {
        return false;
    }
    *out = value;
    return true;
}

ParseResult fail(std::string message)
{
    ParseResult result;
    result.error = std::move(message);
    return result;
}

} // namespace

const char *provider_name(Provider provider)
{
    switch (provider)
    {
    case Provider::automatic:
        return "auto";
    case Provider::directml:
        return "dml";
    case Provider::cpu:
        return "cpu";
    }
    return "unknown";
}

ParseResult parse_cli(const std::vector<std::string> &args)
{
    ParseResult result;
    CliOptions &options = result.options;

    for (std::size_t i = 0; i < args.size(); ++i)
    {
        const std::string &arg = args[i];
        if (arg == "--help" || arg == "-h")
        {
            options.show_help = true;
            continue;
        }
        if (arg == "--version")
        {
            options.show_version = true;
            continue;
        }
        if (arg == "--no-accompaniment")
        {
            options.accompaniment = false;
            continue;
        }

        const bool takes_value = arg == "--model" || arg == "--input" ||
                                 arg == "--output-dir" ||
                                 arg == "--provider" || arg == "--threads" ||
                                 arg == "--vocals-index" ||
                                 arg == "--max-seconds";
        if (!takes_value)
        {
            return fail("unknown argument: " + arg);
        }
        if (i + 1 >= args.size())
        {
            return fail("missing value for " + arg);
        }
        const std::string &value = args[++i];

        if (arg == "--model")
        {
            options.model = value;
        }
        else if (arg == "--input")
        {
            options.input = value;
        }
        else if (arg == "--output-dir")
        {
            options.output_dir = value;
        }
        else if (arg == "--provider")
        {
            if (value == "auto")
            {
                options.provider = Provider::automatic;
            }
            else if (value == "dml" || value == "directml")
            {
                options.provider = Provider::directml;
            }
            else if (value == "cpu")
            {
                options.provider = Provider::cpu;
            }
            else
            {
                return fail("--provider must be auto, dml or cpu");
            }
        }
        else if (arg == "--threads")
        {
            if (!parse_int(value, 0, 256, &options.threads))
            {
                return fail("--threads must be an integer from 0 to 256");
            }
        }
        else if (arg == "--vocals-index")
        {
            if (!parse_int(value, 0, 15, &options.vocals_index))
            {
                return fail("--vocals-index must be an integer from 0 to 15");
            }
        }
        else if (arg == "--max-seconds")
        {
            if (!parse_seconds(value, &options.max_seconds))
            {
                return fail("--max-seconds must be a positive number");
            }
        }
    }

    if (options.show_help || options.show_version)
    {
        result.ok = true;
        return result;
    }
    if (options.model.empty())
    {
        return fail("--model is required");
    }
    if (options.input.empty())
    {
        return fail("--input is required");
    }
    if (options.output_dir.empty())
    {
        return fail("--output-dir is required");
    }
    result.ok = true;
    return result;
}

std::string usage_text()
{
    return "Usage: lyricforge-separator --model <htdemucs.onnx> --input <mix.wav>\n"
           "                            --output-dir <dir> [options]\n"
           "\n"
           "Separates the lead vocal of a 44.1 kHz WAV with an htdemucs ONNX\n"
           "model and writes vocals.wav (and accompaniment.wav) as 16-bit PCM.\n"
           "\n"
           "Options:\n"
           "  --provider auto|dml|cpu  execution provider (default auto: DirectML,\n"
           "                           then CPU if DirectML is unavailable)\n"
           "  --threads N              CPU threads, 0 = ONNX Runtime default\n"
           "  --vocals-index N         vocals source index in the model (default 3)\n"
           "  --max-seconds S          refuse longer input (default 1200)\n"
           "  --no-accompaniment       only write vocals.wav\n"
           "  --version                print version and stem revision\n"
           "  --help                   print this text\n"
           "\n"
           "Progress is reported on stdout as LF_* lines. Exit codes: 0 ok,\n"
           "2 usage, 3 input, 4 model/provider, 5 output, 6 internal error.\n";
}

} // namespace lfsep
