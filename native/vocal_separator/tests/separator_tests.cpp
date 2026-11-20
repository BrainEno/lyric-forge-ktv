// Self-contained tests for the separator CLI: argument parsing, WAV I/O, the
// stdout protocol and the end-to-end command behaviour with a fake engine.
// Built and run in CI by .github/workflows/build-vocal-separator.yml.
#include "app.hpp"
#include "cli_options.hpp"
#include "report.hpp"
#include "wav_io.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace
{

int g_failures = 0;
int g_checks = 0;

#define CHECK(condition)                                                     \
    do                                                                       \
    {                                                                        \
        ++g_checks;                                                          \
        if (!(condition))                                                    \
        {                                                                    \
            ++g_failures;                                                    \
            std::cerr << __FILE__ << ":" << __LINE__ << ": CHECK failed: "   \
                      << #condition << std::endl;                            \
        }                                                                    \
    } while (0)

bool contains(const std::string &haystack, const std::string &needle)
{
    return haystack.find(needle) != std::string::npos;
}

std::filesystem::path temp_dir(const std::string &name)
{
    auto dir = std::filesystem::temp_directory_path() /
               ("lfsep-test-" + name);
    std::filesystem::remove_all(dir);
    std::filesystem::create_directories(dir);
    return dir;
}

void write_bytes(const std::filesystem::path &path,
                 const std::vector<std::uint8_t> &bytes)
{
    std::ofstream file(path, std::ios::binary);
    file.write(reinterpret_cast<const char *>(bytes.data()),
               static_cast<std::streamsize>(bytes.size()));
}

void put_u16(std::vector<std::uint8_t> &out, std::uint16_t v)
{
    out.push_back(static_cast<std::uint8_t>(v & 0xFF));
    out.push_back(static_cast<std::uint8_t>(v >> 8));
}

void put_u32(std::vector<std::uint8_t> &out, std::uint32_t v)
{
    for (int s = 0; s < 32; s += 8)
    {
        out.push_back(static_cast<std::uint8_t>((v >> s) & 0xFF));
    }
}

void put_tag(std::vector<std::uint8_t> &out, const char *tag)
{
    for (int i = 0; i < 4; ++i)
    {
        out.push_back(static_cast<std::uint8_t>(tag[i]));
    }
}

// A WAV with an arbitrary header, for formats the encoder never writes.
std::vector<std::uint8_t> make_wav(std::uint16_t format,
                                   std::uint16_t channels,
                                   std::uint32_t rate,
                                   std::uint16_t bits,
                                   const std::vector<std::uint8_t> &data,
                                   bool extensible = false,
                                   bool list_chunk = false)
{
    std::vector<std::uint8_t> fmt;
    put_u16(fmt, extensible ? 0xFFFE : format);
    put_u16(fmt, channels);
    put_u32(fmt, rate);
    put_u32(fmt, rate * channels * (bits / 8));
    put_u16(fmt, static_cast<std::uint16_t>(channels * (bits / 8)));
    put_u16(fmt, bits);
    if (extensible)
    {
        put_u16(fmt, 22);   // cbSize
        put_u16(fmt, bits); // valid bits
        put_u32(fmt, 0);    // channel mask
        put_u16(fmt, format);
        const std::uint8_t guid_tail[14] = {0x00, 0x00, 0x00, 0x00, 0x10, 0x00, 0x80,
                                            0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71};
        fmt.insert(fmt.end(), guid_tail, guid_tail + 14);
    }
    std::vector<std::uint8_t> out;
    put_tag(out, "RIFF");
    put_u32(out, 0); // patched below
    put_tag(out, "WAVE");
    if (list_chunk)
    {
        put_tag(out, "LIST");
        put_u32(out, 3); // odd size, followed by a pad byte
        out.push_back('a');
        out.push_back('b');
        out.push_back('c');
        out.push_back(0);
    }
    put_tag(out, "fmt ");
    put_u32(out, static_cast<std::uint32_t>(fmt.size()));
    out.insert(out.end(), fmt.begin(), fmt.end());
    put_tag(out, "data");
    put_u32(out, static_cast<std::uint32_t>(data.size()));
    out.insert(out.end(), data.begin(), data.end());
    const std::uint32_t riff = static_cast<std::uint32_t>(out.size() - 8);
    std::memcpy(out.data() + 4, &riff, 4);
    return out;
}

std::string to_utf8(const std::filesystem::path &path)
{
    const auto text = path.u8string();
    return std::string(text.begin(), text.end());
}

std::vector<std::string> lines_of(const std::string &text)
{
    std::vector<std::string> lines;
    std::istringstream stream(text);
    std::string line;
    while (std::getline(stream, line))
    {
        lines.push_back(line);
    }
    return lines;
}

// ---------------------------------------------------------------- CLI ----

void test_cli_requires_paths()
{
    auto result = lfsep::parse_cli({});
    CHECK(!result.ok);
    CHECK(contains(result.error, "--model"));

    result = lfsep::parse_cli({"--model", "m.onnx", "--input", "in.wav"});
    CHECK(!result.ok);
    CHECK(contains(result.error, "--output-dir"));
}

void test_cli_defaults_and_values()
{
    auto result = lfsep::parse_cli(
        {"--model", "m.onnx", "--input", "in.wav", "--output-dir", "out"});
    CHECK(result.ok);
    CHECK(result.options.provider == lfsep::Provider::automatic);
    CHECK(result.options.threads == 0);
    CHECK(result.options.vocals_index == 3);
    CHECK(result.options.accompaniment);
    CHECK(result.options.max_seconds == 1200.0);

    result = lfsep::parse_cli({"--model", "m", "--input", "i", "--output-dir",
                               "o", "--provider", "cpu", "--threads", "8",
                               "--vocals-index", "0", "--max-seconds", "90.5",
                               "--no-accompaniment"});
    CHECK(result.ok);
    CHECK(result.options.provider == lfsep::Provider::cpu);
    CHECK(result.options.threads == 8);
    CHECK(result.options.vocals_index == 0);
    CHECK(result.options.max_seconds == 90.5);
    CHECK(!result.options.accompaniment);

    result = lfsep::parse_cli(
        {"--model", "m", "--input", "i", "--output-dir", "o", "--provider",
         "directml"});
    CHECK(result.ok);
    CHECK(result.options.provider == lfsep::Provider::directml);
}

void test_cli_rejects_bad_values()
{
    const std::vector<std::string> base = {"--model", "m", "--input", "i",
                                           "--output-dir", "o"};
    auto with = [&](std::vector<std::string> extra) {
        std::vector<std::string> args = base;
        args.insert(args.end(), extra.begin(), extra.end());
        return lfsep::parse_cli(args);
    };
    CHECK(!with({"--provider", "cuda"}).ok);
    CHECK(!with({"--threads", "-1"}).ok);
    CHECK(!with({"--threads", "4x"}).ok);
    CHECK(!with({"--threads", "999"}).ok);
    CHECK(!with({"--vocals-index", "16"}).ok);
    CHECK(!with({"--max-seconds", "0"}).ok);
    CHECK(!with({"--max-seconds", "nan"}).ok);
    CHECK(!with({"--threads"}).ok);
    CHECK(contains(with({"--bogus"}).error, "unknown argument"));
}

void test_cli_help_and_version_need_no_paths()
{
    auto result = lfsep::parse_cli({"--version"});
    CHECK(result.ok);
    CHECK(result.options.show_version);
    result = lfsep::parse_cli({"-h"});
    CHECK(result.ok);
    CHECK(result.options.show_help);
    CHECK(std::string(lfsep::provider_name(lfsep::Provider::directml)) == "dml");
}

// ---------------------------------------------------------------- WAV ----

void test_wav_round_trip_pcm16()
{
    std::vector<float> samples = {0.0f, 0.5f, -0.5f, 1.0f, -1.0f, 0.25f};
    auto bytes = lfsep::encode_wav_pcm16(44100, 2, samples);
    CHECK(bytes.size() == 44 + samples.size() * 2);
    auto parsed = lfsep::parse_wav(bytes);
    CHECK(parsed.ok());
    CHECK(parsed.audio.sample_rate == 44100);
    CHECK(parsed.audio.channels == 2);
    CHECK(parsed.audio.frames() == 3);
    for (std::size_t i = 0; i < samples.size(); ++i)
    {
        CHECK(std::fabs(parsed.audio.interleaved[i] - samples[i]) < 1e-3f);
    }
}

void test_wav_encoder_clamps_and_drops_non_finite()
{
    auto bytes = lfsep::encode_wav_pcm16(
        8000, 1, {2.0f, -3.0f, std::nanf(""), INFINITY});
    auto parsed = lfsep::parse_wav(bytes);
    CHECK(parsed.ok());
    CHECK(std::fabs(parsed.audio.interleaved[0] - 32767.0f / 32768.0f) < 1e-6f);
    CHECK(std::fabs(parsed.audio.interleaved[1] + 32767.0f / 32768.0f) < 1e-6f);
    CHECK(parsed.audio.interleaved[2] == 0.0f);
    CHECK(parsed.audio.interleaved[3] == 0.0f);
}

void test_wav_reads_other_formats()
{
    // 24-bit PCM mono: +0.5 and -0.5.
    std::vector<std::uint8_t> pcm24 = {0x00, 0x00, 0x40, 0x00, 0x00, 0xC0};
    auto parsed = lfsep::parse_wav(make_wav(1, 1, 22050, 24, pcm24));
    CHECK(parsed.ok());
    CHECK(parsed.audio.frames() == 2);
    CHECK(std::fabs(parsed.audio.interleaved[0] - 0.5f) < 1e-6f);
    CHECK(std::fabs(parsed.audio.interleaved[1] + 0.5f) < 1e-6f);

    // 32-bit float stereo inside WAVE_FORMAT_EXTENSIBLE, after a LIST chunk.
    std::vector<std::uint8_t> f32;
    for (float v : {0.25f, -0.75f})
    {
        std::uint32_t raw;
        std::memcpy(&raw, &v, 4);
        put_u32(f32, raw);
    }
    parsed = lfsep::parse_wav(make_wav(3, 2, 44100, 32, f32, true, true));
    CHECK(parsed.ok());
    CHECK(parsed.audio.channels == 2);
    CHECK(parsed.audio.frames() == 1);
    CHECK(parsed.audio.interleaved[0] == 0.25f);
    CHECK(parsed.audio.interleaved[1] == -0.75f);

    // 8-bit unsigned PCM.
    parsed = lfsep::parse_wav(make_wav(1, 1, 8000, 8, {128, 255, 0}));
    CHECK(parsed.ok());
    CHECK(parsed.audio.interleaved[0] == 0.0f);
    CHECK(parsed.audio.interleaved[2] == -1.0f);
}

void test_wav_tolerates_streaming_data_size()
{
    auto bytes = lfsep::encode_wav_pcm16(44100, 2, {0.1f, 0.2f, 0.3f, 0.4f});
    // FFmpeg writing to a pipe leaves 0xFFFFFFFF as the data size.
    bytes[40] = bytes[41] = bytes[42] = bytes[43] = 0xFF;
    auto parsed = lfsep::parse_wav(bytes);
    CHECK(parsed.ok());
    CHECK(parsed.audio.frames() == 2);
}

void test_wav_rejects_invalid_input()
{
    CHECK(lfsep::parse_wav({}).error == lfsep::WavError::not_riff);
    std::vector<std::uint8_t> text(64, 'x');
    CHECK(lfsep::parse_wav(text).error == lfsep::WavError::not_riff);

    auto adpcm = make_wav(2, 1, 8000, 4, {1, 2, 3, 4});
    CHECK(lfsep::parse_wav(adpcm).error == lfsep::WavError::unsupported_format);

    auto surround = make_wav(1, 6, 48000, 16, std::vector<std::uint8_t>(24, 0));
    auto parsed = lfsep::parse_wav(surround);
    CHECK(parsed.error == lfsep::WavError::unsupported_format);
    CHECK(contains(parsed.message, "6 channels"));

    auto empty_data = make_wav(1, 2, 44100, 16, {1, 2});
    CHECK(lfsep::parse_wav(empty_data).error == lfsep::WavError::truncated);

    std::vector<std::uint8_t> no_fmt;
    put_tag(no_fmt, "RIFF");
    put_u32(no_fmt, 12);
    put_tag(no_fmt, "WAVE");
    put_tag(no_fmt, "data");
    put_u32(no_fmt, 0);
    CHECK(lfsep::parse_wav(no_fmt).error == lfsep::WavError::missing_format);
}

void test_wav_file_io_is_atomic()
{
    auto dir = temp_dir("io");
    auto path = dir / "out.wav";
    std::string error;
    CHECK(lfsep::write_wav_pcm16(path, 44100, 2, {0.5f, -0.5f}, &error));
    CHECK(error.empty());
    CHECK(std::filesystem::exists(path));
    CHECK(!std::filesystem::exists(dir / "out.wav.partial"));
    auto parsed = lfsep::read_wav(path);
    CHECK(parsed.ok());
    CHECK(parsed.audio.frames() == 1);
    // Overwrite keeps working.
    CHECK(lfsep::write_wav_pcm16(path, 44100, 1, {0.1f, 0.2f, 0.3f}, &error));
    CHECK(lfsep::read_wav(path).audio.frames() == 3);
    CHECK(lfsep::read_wav(dir / "missing.wav").error ==
          lfsep::WavError::open_failed);
    CHECK(!lfsep::write_wav_pcm16(dir / "no" / "such" / "dir.wav", 44100, 1,
                                  {0.0f}, &error));
    CHECK(!error.empty());
    std::filesystem::remove_all(dir);
}

void test_stereo_helpers()
{
    lfsep::AudioBuffer mono;
    mono.sample_rate = 44100;
    mono.channels = 1;
    mono.interleaved = {0.1f, 0.2f};
    std::vector<float> left;
    std::vector<float> right;
    CHECK(lfsep::split_stereo(mono, &left, &right));
    CHECK(left == right);
    CHECK(left.size() == 2);

    lfsep::AudioBuffer stereo;
    stereo.channels = 2;
    stereo.interleaved = {1.0f, 2.0f, 3.0f, 4.0f};
    CHECK(lfsep::split_stereo(stereo, &left, &right));
    CHECK((left == std::vector<float>{1.0f, 3.0f}));
    CHECK((right == std::vector<float>{2.0f, 4.0f}));
    CHECK((lfsep::interleave_stereo(left, right) == stereo.interleaved));

    lfsep::AudioBuffer quad;
    quad.channels = 4;
    quad.interleaved = std::vector<float>(8, 0.0f);
    CHECK(!lfsep::split_stereo(quad, &left, &right));
}

// ----------------------------------------------------------- protocol ----

void test_protocol_lines()
{
    CHECK(lfsep::progress_line(0.5) == "LF_PROGRESS 0.5000");
    CHECK(lfsep::progress_line(-1) == "LF_PROGRESS 0.0000");
    CHECK(lfsep::progress_line(7) == "LF_PROGRESS 1.0000");
    CHECK(lfsep::progress_line(std::nan("")) == "LF_PROGRESS 0.0000");
    CHECK(lfsep::stage_line("separate") == "LF_STAGE separate");
    CHECK(lfsep::provider_line("dml") == "LF_PROVIDER dml");
    CHECK(lfsep::fallback_line("dml\nbroken") == "LF_FALLBACK dml broken");
    CHECK(lfsep::error_line(3, "bad\tinput") == "LF_ERROR 3 bad input");
    lfsep::StemStats stats;
    stats.mix_rms = 0.25;
    stats.vocals_rms = 0.125;
    stats.accompaniment_rms = 0.2;
    stats.seconds = 12.5;
    CHECK(lfsep::stats_line(stats) ==
          "LF_STATS mix_rms=0.250000 vocals_rms=0.125000 "
          "accompaniment_rms=0.200000 seconds=12.500");
    CHECK(lfsep::rms({}) == 0.0);
    CHECK(std::fabs(lfsep::rms({0.5f, -0.5f}) - 0.5) < 1e-9);
    CHECK((lfsep::subtract({1.0f, 0.5f}, {0.25f, 0.5f}) ==
           std::vector<float>{0.75f, 0.0f}));
}

// -------------------------------------------------------------- app ----

struct FakeEngine
{
    int calls = 0;
    lfsep::ExitCode code = lfsep::ExitCode::ok;
    bool wrong_length = false;
    bool throws = false;
    std::string provider_seen;

    lfsep::EngineResult operator()(const lfsep::EngineRequest &request,
                                   const lfsep::EngineCallbacks &callbacks)
    {
        ++calls;
        provider_seen = lfsep::provider_name(request.options->provider);
        if (throws)
        {
            throw std::runtime_error("boom");
        }
        callbacks.stage("load-model");
        callbacks.provider("cpu");
        callbacks.stage("separate");
        callbacks.progress(0.5);
        lfsep::EngineResult result;
        result.code = code;
        if (code != lfsep::ExitCode::ok)
        {
            result.error = "fake failure";
            return result;
        }
        // "Vocals" are half of the mix, so the accompaniment is the other half.
        for (float v : *request.left)
        {
            result.vocals_left.push_back(v * 0.5f);
        }
        for (float v : *request.right)
        {
            result.vocals_right.push_back(v * 0.5f);
        }
        if (wrong_length)
        {
            result.vocals_left.pop_back();
        }
        return result;
    }
};

std::filesystem::path write_tone(const std::filesystem::path &dir,
                                 int rate,
                                 double seconds,
                                 int channels)
{
    const std::size_t frames = static_cast<std::size_t>(rate * seconds);
    std::vector<float> samples(frames * channels);
    for (std::size_t i = 0; i < frames; ++i)
    {
        const float v = 0.4f * std::sin(2.0f * 3.14159265f * 440.0f * i / rate);
        for (int c = 0; c < channels; ++c)
        {
            samples[i * channels + c] = v;
        }
    }
    auto path = dir / ("tone-" + std::to_string(rate) + "-" +
                       std::to_string(channels) + ".wav");
    write_bytes(path, lfsep::encode_wav_pcm16(rate, channels, samples));
    return path;
}

int run(const std::vector<std::string> &args,
        FakeEngine &engine,
        std::string *out_text,
        std::string *err_text = nullptr)
{
    std::ostringstream out;
    std::ostringstream err;
    const int code = lfsep::run_app(
        args, out, err,
        [&engine](const lfsep::EngineRequest &r, const lfsep::EngineCallbacks &c) {
            return engine(r, c);
        });
    *out_text = out.str();
    if (err_text != nullptr)
    {
        *err_text = err.str();
    }
    return code;
}

void test_app_writes_stems_and_protocol()
{
    auto dir = temp_dir("app");
    auto input = write_tone(dir, 44100, 2.0, 1);
    auto out_dir = dir / "stems";
    FakeEngine engine;
    std::string out;
    const int code = run({"--model", "m.onnx", "--input", input.string(),
                          "--output-dir", out_dir.string()},
                         engine, &out);
    CHECK(code == 0);
    CHECK(engine.calls == 1);
    CHECK(engine.provider_seen == "auto");

    const auto lines = lines_of(out);
    CHECK(!lines.empty());
    CHECK(lines.front() == "LF_STAGE load-model");
    CHECK(contains(out, "LF_PROVIDER cpu"));
    CHECK(contains(out, "LF_PROGRESS 0.5000"));
    CHECK(contains(out, "LF_STAGE write"));
    CHECK(contains(out, "LF_PROGRESS 1.0000"));
    CHECK(contains(out, "seconds=2.000"));
    CHECK(lines.back().rfind("LF_DONE vocals=", 0) == 0);
    CHECK(contains(lines.back(), "accompaniment="));

    auto vocals = lfsep::read_wav(out_dir / "vocals.wav");
    auto accompaniment = lfsep::read_wav(out_dir / "accompaniment.wav");
    CHECK(vocals.ok());
    CHECK(accompaniment.ok());
    CHECK(vocals.audio.channels == 2);
    CHECK(vocals.audio.sample_rate == 44100);
    CHECK(vocals.audio.frames() == 88200);
    CHECK(accompaniment.audio.frames() == 88200);
    // Halves of a 0.4 sine: both stems peak near 0.2.
    float peak = 0.0f;
    for (float v : accompaniment.audio.interleaved)
    {
        peak = std::max(peak, std::fabs(v));
    }
    CHECK(std::fabs(peak - 0.2f) < 0.01f);

    // vocals_rms is half of mix_rms in the stats line.
    const auto stats = lines[lines.size() - 2];
    CHECK(stats.rfind("LF_STATS ", 0) == 0);
    CHECK(contains(stats, "mix_rms=0.28"));
    CHECK(contains(stats, "vocals_rms=0.14"));
    std::filesystem::remove_all(dir);
}

void test_app_without_accompaniment()
{
    auto dir = temp_dir("novocal");
    auto input = write_tone(dir, 44100, 1.5, 2);
    FakeEngine engine;
    std::string out;
    CHECK(run({"--model", "m", "--input", input.string(), "--output-dir",
               (dir / "o").string(), "--no-accompaniment"},
              engine, &out) == 0);
    CHECK(std::filesystem::exists(dir / "o" / "vocals.wav"));
    CHECK(!std::filesystem::exists(dir / "o" / "accompaniment.wav"));
    CHECK(!contains(out, "accompaniment="));
    std::filesystem::remove_all(dir);
}

void test_app_input_errors()
{
    auto dir = temp_dir("input");
    FakeEngine engine;
    std::string out;
    std::string err;

    CHECK(run({"--model", "m", "--input", (dir / "nope.wav").string(),
               "--output-dir", dir.string()},
              engine, &out, &err) == 3);
    CHECK(contains(out, "LF_ERROR 3 cannot read input WAV (open_failed)"));
    CHECK(contains(err, "lyricforge-separator:"));

    auto wrong_rate = write_tone(dir, 16000, 2.0, 1);
    CHECK(run({"--model", "m", "--input", wrong_rate.string(), "--output-dir",
               dir.string()},
              engine, &out) == 3);
    CHECK(contains(out, "must be 44100 Hz, got 16000 Hz"));

    auto short_clip = write_tone(dir, 44100, 0.5, 1);
    CHECK(run({"--model", "m", "--input", short_clip.string(), "--output-dir",
               dir.string()},
              engine, &out) == 3);
    CHECK(contains(out, "shorter than one second"));

    auto clip = write_tone(dir, 44100, 3.0, 1);
    CHECK(run({"--model", "m", "--input", clip.string(), "--output-dir",
               dir.string(), "--max-seconds", "2"},
              engine, &out) == 3);
    CHECK(contains(out, "longer than --max-seconds"));
    CHECK(engine.calls == 0);
    std::filesystem::remove_all(dir);
}

void test_app_engine_errors()
{
    auto dir = temp_dir("engine");
    auto input = write_tone(dir, 44100, 1.0, 1);
    std::string out;
    const std::vector<std::string> args = {"--model", "m", "--input",
                                           input.string(), "--output-dir",
                                           (dir / "o").string()};

    FakeEngine model_error;
    model_error.code = lfsep::ExitCode::model;
    CHECK(run(args, model_error, &out) == 4);
    CHECK(contains(out, "LF_ERROR 4 fake failure"));
    CHECK(!std::filesystem::exists(dir / "o" / "vocals.wav"));

    FakeEngine short_stem;
    short_stem.wrong_length = true;
    CHECK(run(args, short_stem, &out) == 6);
    CHECK(contains(out, "wrong length"));

    FakeEngine throwing;
    throwing.throws = true;
    CHECK(run(args, throwing, &out) == 6);
    CHECK(contains(out, "LF_ERROR 6 boom"));
    std::filesystem::remove_all(dir);
}

void test_app_usage_help_version()
{
    FakeEngine engine;
    std::string out;
    std::string err;
    CHECK(run({"--input"}, engine, &out, &err) == 2);
    CHECK(contains(out, "LF_ERROR 2 missing value for --input"));
    CHECK(contains(err, "Usage:"));

    CHECK(run({"--help"}, engine, &out) == 0);
    CHECK(contains(out, "Usage:"));
    CHECK(contains(out, "--provider auto|dml|cpu"));

    CHECK(run({"--version"}, engine, &out) == 0);
    CHECK(out == std::string("lyricforge-separator ") +
                     lfsep::kSeparatorVersion + " " +
                     lfsep::kSeparatorRevision + "\n");
    CHECK(engine.calls == 0);
}

void test_app_handles_utf8_paths()
{
    auto dir = temp_dir("utf8");
    // "人声" (vocals) / "歌曲" (song) in UTF-8.
    const std::string song_dir = to_utf8(dir) + "/\xE6\xAD\x8C\xE6\x9B\xB2";
    std::filesystem::create_directories(lfsep::path_from_utf8(song_dir));
    auto input = write_tone(lfsep::path_from_utf8(song_dir), 44100, 1.0, 1);
    FakeEngine engine;
    std::string out;
    const std::string out_dir = song_dir + "/\xE4\xBA\xBA\xE5\xA3\xB0";
    CHECK(run({"--model", "m", "--input", to_utf8(input), "--output-dir",
               out_dir},
              engine, &out) == 0);
    CHECK(std::filesystem::exists(lfsep::path_from_utf8(out_dir) / "vocals.wav"));
    std::filesystem::remove_all(dir);
}

} // namespace

int main()
{
    const std::vector<std::pair<const char *, std::function<void()>>> tests = {
        {"cli requires paths", test_cli_requires_paths},
        {"cli defaults and values", test_cli_defaults_and_values},
        {"cli rejects bad values", test_cli_rejects_bad_values},
        {"cli help and version", test_cli_help_and_version_need_no_paths},
        {"wav round trip", test_wav_round_trip_pcm16},
        {"wav clamps", test_wav_encoder_clamps_and_drops_non_finite},
        {"wav other formats", test_wav_reads_other_formats},
        {"wav streaming size", test_wav_tolerates_streaming_data_size},
        {"wav invalid", test_wav_rejects_invalid_input},
        {"wav file io", test_wav_file_io_is_atomic},
        {"stereo helpers", test_stereo_helpers},
        {"protocol lines", test_protocol_lines},
        {"app writes stems", test_app_writes_stems_and_protocol},
        {"app without accompaniment", test_app_without_accompaniment},
        {"app input errors", test_app_input_errors},
        {"app engine errors", test_app_engine_errors},
        {"app usage", test_app_usage_help_version},
        {"app utf8 paths", test_app_handles_utf8_paths},
    };
    for (const auto &[name, test] : tests)
    {
        const int before = g_failures;
        test();
        std::cout << (g_failures == before ? "ok   " : "FAIL ") << name
                  << std::endl;
    }
    std::cout << g_checks << " checks, " << g_failures << " failures"
              << std::endl;
    return g_failures == 0 ? 0 : 1;
}
