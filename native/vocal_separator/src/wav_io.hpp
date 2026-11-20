// WAV reading and writing for the vocal separator.
//
// The app hands the separator a WAV that FFmpeg wrote (44.1 kHz, 16-bit,
// stereo), but the reader accepts the other common layouts too so the tool
// can be run by hand: 8/16/24/32-bit PCM, 32/64-bit float and
// WAVE_FORMAT_EXTENSIBLE wrappers of those, mono or stereo. Output is always
// 16-bit PCM, which every engine downstream (FFmpeg, whisper.cpp, Qwen) reads.
#ifndef LFSEP_WAV_IO_HPP
#define LFSEP_WAV_IO_HPP

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

namespace lfsep
{

enum class WavError
{
    none,
    open_failed,
    not_riff,
    missing_format,
    missing_data,
    unsupported_format,
    truncated,
    write_failed,
};

const char *wav_error_name(WavError error);

// Interleaved samples in [-1, 1].
struct AudioBuffer
{
    int sample_rate = 0;
    int channels = 0;
    std::vector<float> interleaved;

    std::size_t frames() const
    {
        return channels <= 0 ? 0 : interleaved.size() / channels;
    }

    double seconds() const
    {
        return sample_rate <= 0 ? 0.0
                                : static_cast<double>(frames()) / sample_rate;
    }
};

struct WavReadResult
{
    WavError error = WavError::none;
    std::string message;
    AudioBuffer audio;

    bool ok() const { return error == WavError::none; }
};

// Parses a complete WAV file held in memory.
WavReadResult parse_wav(const std::vector<std::uint8_t> &bytes);

// Reads [path] (see path_from_utf8 for non-ASCII names) and parses it.
WavReadResult read_wav(const std::filesystem::path &path);

// Encodes interleaved float samples as 16-bit PCM, clamping to [-1, 1].
std::vector<std::uint8_t> encode_wav_pcm16(int sample_rate,
                                           int channels,
                                           const std::vector<float> &interleaved);

// Writes [path] via a sibling temporary file and a rename, so a reader never
// sees a half-written stem. Returns false and fills [error] on failure.
bool write_wav_pcm16(const std::filesystem::path &path,
                     int sample_rate,
                     int channels,
                     const std::vector<float> &interleaved,
                     std::string *error);

// A filesystem path from UTF-8 text. On Windows narrow strings are in the
// ANSI code page, so a Chinese user name or song title would otherwise be
// mangled; the CLI converts its wide arguments to UTF-8 and back through this.
std::filesystem::path path_from_utf8(const std::string &utf8);

// Stereo view of [audio]: mono is duplicated, stereo is copied.
// Returns false for other channel counts.
bool split_stereo(const AudioBuffer &audio,
                  std::vector<float> *left,
                  std::vector<float> *right);

// Interleaves two equally long channels.
std::vector<float> interleave_stereo(const std::vector<float> &left,
                                     const std::vector<float> &right);

} // namespace lfsep

#endif // LFSEP_WAV_IO_HPP
