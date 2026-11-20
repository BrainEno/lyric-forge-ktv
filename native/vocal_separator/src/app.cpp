#include "app.hpp"

#include "report.hpp"
#include "wav_io.hpp"

#include <cmath>
#include <exception>
#include <filesystem>
#include <system_error>

namespace lfsep
{
namespace
{

int finish_with_error(std::ostream &out,
                      std::ostream &err,
                      ExitCode code,
                      const std::string &message)
{
    out << error_line(static_cast<int>(code), message) << std::endl;
    err << "lyricforge-separator: " << message << std::endl;
    return static_cast<int>(code);
}

// UTF-8 text of [path] for the LF_DONE line. The app only treats LF_DONE as
// a completion marker; it already knows where the stems are written.
std::string utf8_of(const std::filesystem::path &path)
{
#if defined(__cpp_lib_char8_t)
    const auto text = path.u8string();
    return std::string(text.begin(), text.end());
#else
    return path.u8string();
#endif
}

} // namespace

int run_app(const std::vector<std::string> &args,
            std::ostream &out,
            std::ostream &err,
            const Engine &engine)
{
    const ParseResult parsed = parse_cli(args);
    if (!parsed.ok)
    {
        err << usage_text();
        return finish_with_error(out, err, ExitCode::usage, parsed.error);
    }
    const CliOptions &options = parsed.options;
    if (options.show_help)
    {
        out << usage_text();
        return static_cast<int>(ExitCode::ok);
    }
    if (options.show_version)
    {
        out << "lyricforge-separator " << kSeparatorVersion << " "
            << kSeparatorRevision << std::endl;
        return static_cast<int>(ExitCode::ok);
    }

    const WavReadResult input = read_wav(path_from_utf8(options.input));
    if (!input.ok())
    {
        return finish_with_error(out, err, ExitCode::input,
                                 std::string("cannot read input WAV (") +
                                     wav_error_name(input.error) + "): " +
                                     input.message);
    }
    if (input.audio.sample_rate != kRequiredSampleRate)
    {
        return finish_with_error(
            out, err, ExitCode::input,
            "input must be " + std::to_string(kRequiredSampleRate) +
                " Hz, got " + std::to_string(input.audio.sample_rate) + " Hz");
    }
    const double seconds = input.audio.seconds();
    if (seconds < 1.0)
    {
        return finish_with_error(out, err, ExitCode::input,
                                 "input is shorter than one second");
    }
    if (seconds > options.max_seconds)
    {
        return finish_with_error(out, err, ExitCode::input,
                                 "input is longer than --max-seconds");
    }

    std::vector<float> left;
    std::vector<float> right;
    if (!split_stereo(input.audio, &left, &right))
    {
        return finish_with_error(out, err, ExitCode::input,
                                 "only mono and stereo input is supported");
    }

    const std::filesystem::path output_dir = path_from_utf8(options.output_dir);
    std::error_code ec;
    std::filesystem::create_directories(output_dir, ec);
    if (ec || !std::filesystem::is_directory(output_dir))
    {
        return finish_with_error(out, err, ExitCode::output,
                                 "cannot create output directory");
    }

    EngineCallbacks callbacks;
    callbacks.progress = [&out](double fraction) {
        out << progress_line(fraction) << std::endl;
    };
    callbacks.stage = [&out](const std::string &stage) {
        out << stage_line(stage) << std::endl;
    };
    callbacks.provider = [&out](const std::string &provider) {
        out << provider_line(provider) << std::endl;
    };
    callbacks.fallback = [&out](const std::string &reason) {
        out << fallback_line(reason) << std::endl;
    };

    EngineRequest request;
    request.options = &options;
    request.left = &left;
    request.right = &right;

    EngineResult result;
    try
    {
        result = engine(request, callbacks);
    }
    catch (const std::exception &error)
    {
        return finish_with_error(out, err, ExitCode::internal, error.what());
    }
    if (result.code != ExitCode::ok)
    {
        return finish_with_error(out, err, result.code, result.error);
    }
    if (result.vocals_left.size() != left.size() ||
        result.vocals_right.size() != right.size())
    {
        return finish_with_error(out, err, ExitCode::internal,
                                 "engine returned a stem of the wrong length");
    }

    callbacks.stage("write");
    const std::filesystem::path vocals_path = output_dir / "vocals.wav";
    std::string write_error;
    if (!write_wav_pcm16(vocals_path, kRequiredSampleRate, 2,
                         interleave_stereo(result.vocals_left,
                                           result.vocals_right),
                         &write_error))
    {
        return finish_with_error(out, err, ExitCode::output,
                                 "vocals.wav: " + write_error);
    }

    StemStats stats;
    stats.seconds = seconds;
    stats.mix_rms = std::sqrt((std::pow(rms(left), 2) + std::pow(rms(right), 2)) / 2);
    stats.vocals_rms = std::sqrt((std::pow(rms(result.vocals_left), 2) +
                                  std::pow(rms(result.vocals_right), 2)) /
                                 2);

    std::string done = "LF_DONE vocals=" + utf8_of(vocals_path);
    if (options.accompaniment)
    {
        const std::vector<float> accompaniment_left =
            subtract(left, result.vocals_left);
        const std::vector<float> accompaniment_right =
            subtract(right, result.vocals_right);
        stats.accompaniment_rms =
            std::sqrt((std::pow(rms(accompaniment_left), 2) +
                       std::pow(rms(accompaniment_right), 2)) /
                      2);
        const std::filesystem::path accompaniment_path =
            output_dir / "accompaniment.wav";
        if (!write_wav_pcm16(accompaniment_path, kRequiredSampleRate, 2,
                             interleave_stereo(accompaniment_left,
                                               accompaniment_right),
                             &write_error))
        {
            return finish_with_error(out, err, ExitCode::output,
                                     "accompaniment.wav: " + write_error);
        }
        done += " accompaniment=" + utf8_of(accompaniment_path);
    }

    out << progress_line(1.0) << std::endl;
    out << stats_line(stats) << std::endl;
    out << done << std::endl;
    return static_cast<int>(ExitCode::ok);
}

} // namespace lfsep
