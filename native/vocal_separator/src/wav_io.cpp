#include "wav_io.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <fstream>
#include <iterator>
#include <system_error>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace lfsep
{
namespace
{

constexpr std::uint16_t kFormatPcm = 1;
constexpr std::uint16_t kFormatFloat = 3;
constexpr std::uint16_t kFormatExtensible = 0xFFFE;

std::uint16_t read_u16(const std::uint8_t *p)
{
    return static_cast<std::uint16_t>(p[0] | (p[1] << 8));
}

std::uint32_t read_u32(const std::uint8_t *p)
{
    return static_cast<std::uint32_t>(p[0]) |
           (static_cast<std::uint32_t>(p[1]) << 8) |
           (static_cast<std::uint32_t>(p[2]) << 16) |
           (static_cast<std::uint32_t>(p[3]) << 24);
}

void write_u16(std::vector<std::uint8_t> &out, std::uint16_t value)
{
    out.push_back(static_cast<std::uint8_t>(value & 0xFF));
    out.push_back(static_cast<std::uint8_t>((value >> 8) & 0xFF));
}

void write_u32(std::vector<std::uint8_t> &out, std::uint32_t value)
{
    for (int shift = 0; shift < 32; shift += 8)
    {
        out.push_back(static_cast<std::uint8_t>((value >> shift) & 0xFF));
    }
}

void write_tag(std::vector<std::uint8_t> &out, const char *tag)
{
    for (int i = 0; i < 4; ++i)
    {
        out.push_back(static_cast<std::uint8_t>(tag[i]));
    }
}

WavReadResult failure(WavError error, std::string message)
{
    WavReadResult result;
    result.error = error;
    result.message = std::move(message);
    return result;
}

float decode_sample(const std::uint8_t *p, std::uint16_t format, int bits)
{
    if (format == kFormatFloat)
    {
        if (bits == 32)
        {
            float value;
            std::uint32_t raw = read_u32(p);
            std::memcpy(&value, &raw, sizeof(value));
            return value;
        }
        std::uint64_t raw = 0;
        for (int i = 7; i >= 0; --i)
        {
            raw = (raw << 8) | p[i];
        }
        double value;
        std::memcpy(&value, &raw, sizeof(value));
        return static_cast<float>(value);
    }
    switch (bits)
    {
    case 8:
        // 8-bit WAV is unsigned with a 128 midpoint.
        return (static_cast<int>(p[0]) - 128) / 128.0f;
    case 16:
        return static_cast<std::int16_t>(read_u16(p)) / 32768.0f;
    case 24:
    {
        std::int32_t value = p[0] | (p[1] << 8) | (p[2] << 16);
        if (value & 0x800000)
        {
            value |= ~0xFFFFFF;
        }
        return value / 8388608.0f;
    }
    default:
        return static_cast<std::int32_t>(read_u32(p)) / 2147483648.0f;
    }
}

} // namespace

const char *wav_error_name(WavError error)
{
    switch (error)
    {
    case WavError::none:
        return "none";
    case WavError::open_failed:
        return "open_failed";
    case WavError::not_riff:
        return "not_riff";
    case WavError::missing_format:
        return "missing_format";
    case WavError::missing_data:
        return "missing_data";
    case WavError::unsupported_format:
        return "unsupported_format";
    case WavError::truncated:
        return "truncated";
    case WavError::write_failed:
        return "write_failed";
    }
    return "unknown";
}

WavReadResult parse_wav(const std::vector<std::uint8_t> &bytes)
{
    if (bytes.size() < 12 || std::memcmp(bytes.data(), "RIFF", 4) != 0 ||
        std::memcmp(bytes.data() + 8, "WAVE", 4) != 0)
    {
        return failure(WavError::not_riff, "not a RIFF/WAVE file");
    }

    bool have_format = false;
    std::uint16_t format = 0;
    int channels = 0;
    int sample_rate = 0;
    int bits = 0;
    int block_align = 0;
    const std::uint8_t *data = nullptr;
    std::size_t data_size = 0;

    std::size_t offset = 12;
    while (offset + 8 <= bytes.size())
    {
        const std::uint8_t *chunk = bytes.data() + offset;
        const std::uint32_t declared = read_u32(chunk + 4);
        const std::size_t body = offset + 8;
        const std::size_t available = bytes.size() - body;

        if (std::memcmp(chunk, "fmt ", 4) == 0)
        {
            if (declared < 16 || declared > available)
            {
                return failure(WavError::missing_format, "fmt chunk is too short");
            }
            const std::uint8_t *f = bytes.data() + body;
            format = read_u16(f);
            channels = read_u16(f + 2);
            sample_rate = static_cast<int>(read_u32(f + 4));
            block_align = read_u16(f + 12);
            bits = read_u16(f + 14);
            if (format == kFormatExtensible)
            {
                if (declared < 40)
                {
                    return failure(WavError::unsupported_format,
                                   "extensible fmt chunk is too short");
                }
                // The first two bytes of the sub-format GUID carry the tag.
                format = read_u16(f + 24);
            }
            have_format = true;
        }
        else if (std::memcmp(chunk, "data", 4) == 0)
        {
            data = bytes.data() + body;
            // Streaming writers leave 0 or 0xFFFFFFFF here; use what exists.
            data_size = (declared == 0 || declared > available) ? available
                                                                : declared;
            if (have_format)
            {
                break;
            }
        }

        // Chunks are word aligned; a missing pad byte at the end is tolerated.
        std::size_t next = body + static_cast<std::size_t>(declared) +
                           (declared & 1u);
        if (next <= offset)
        {
            break;
        }
        offset = next;
    }

    if (!have_format)
    {
        return failure(WavError::missing_format, "no fmt chunk");
    }
    if (data == nullptr)
    {
        return failure(WavError::missing_data, "no data chunk");
    }

    const bool pcm_ok = format == kFormatPcm &&
                        (bits == 8 || bits == 16 || bits == 24 || bits == 32);
    const bool float_ok = format == kFormatFloat && (bits == 32 || bits == 64);
    if (!pcm_ok && !float_ok)
    {
        return failure(WavError::unsupported_format,
                       "unsupported sample format " + std::to_string(format) +
                           "/" + std::to_string(bits) + " bit");
    }
    if (channels < 1 || channels > 2)
    {
        return failure(WavError::unsupported_format,
                       "only mono and stereo are supported, got " +
                           std::to_string(channels) + " channels");
    }
    if (sample_rate <= 0)
    {
        return failure(WavError::unsupported_format, "invalid sample rate");
    }
    const int bytes_per_sample = bits / 8;
    if (block_align != bytes_per_sample * channels)
    {
        block_align = bytes_per_sample * channels;
    }

    const std::size_t frames = data_size / static_cast<std::size_t>(block_align);
    if (frames == 0)
    {
        return failure(WavError::truncated, "data chunk holds no complete frame");
    }

    WavReadResult result;
    result.audio.sample_rate = sample_rate;
    result.audio.channels = channels;
    result.audio.interleaved.resize(frames * static_cast<std::size_t>(channels));
    for (std::size_t i = 0; i < result.audio.interleaved.size(); ++i)
    {
        result.audio.interleaved[i] =
            decode_sample(data + i * bytes_per_sample, format, bits);
    }
    return result;
}

WavReadResult read_wav(const std::filesystem::path &path)
{
    std::ifstream file(path, std::ios::binary);
    if (!file)
    {
        return failure(WavError::open_failed, "cannot open input file");
    }
    std::vector<std::uint8_t> bytes((std::istreambuf_iterator<char>(file)),
                                    std::istreambuf_iterator<char>());
    return parse_wav(bytes);
}

std::vector<std::uint8_t> encode_wav_pcm16(int sample_rate,
                                           int channels,
                                           const std::vector<float> &interleaved)
{
    const std::uint32_t data_bytes =
        static_cast<std::uint32_t>(interleaved.size() * 2);
    std::vector<std::uint8_t> out;
    out.reserve(44 + data_bytes);
    write_tag(out, "RIFF");
    write_u32(out, 36 + data_bytes);
    write_tag(out, "WAVE");
    write_tag(out, "fmt ");
    write_u32(out, 16);
    write_u16(out, kFormatPcm);
    write_u16(out, static_cast<std::uint16_t>(channels));
    write_u32(out, static_cast<std::uint32_t>(sample_rate));
    write_u32(out, static_cast<std::uint32_t>(sample_rate * channels * 2));
    write_u16(out, static_cast<std::uint16_t>(channels * 2));
    write_u16(out, 16);
    write_tag(out, "data");
    write_u32(out, data_bytes);
    for (float sample : interleaved)
    {
        float clamped = std::isfinite(sample) ? std::clamp(sample, -1.0f, 1.0f)
                                              : 0.0f;
        long scaled = std::lround(clamped * 32767.0f);
        write_u16(out, static_cast<std::uint16_t>(static_cast<std::int16_t>(scaled)));
    }
    return out;
}

bool write_wav_pcm16(const std::filesystem::path &path,
                     int sample_rate,
                     int channels,
                     const std::vector<float> &interleaved,
                     std::string *error)
{
    const std::vector<std::uint8_t> bytes =
        encode_wav_pcm16(sample_rate, channels, interleaved);
    std::filesystem::path partial = path;
    partial += ".partial";
    {
        std::ofstream file(partial, std::ios::binary | std::ios::trunc);
        if (!file)
        {
            if (error != nullptr)
            {
                *error = "cannot create output file";
            }
            return false;
        }
        file.write(reinterpret_cast<const char *>(bytes.data()),
                   static_cast<std::streamsize>(bytes.size()));
        file.flush();
        if (!file)
        {
            if (error != nullptr)
            {
                *error = "cannot write output file";
            }
            return false;
        }
    }
    std::error_code ec;
    std::filesystem::remove(path, ec);
    std::filesystem::rename(partial, path, ec);
    if (ec)
    {
        if (error != nullptr)
        {
            *error = "cannot move output file into place: " + ec.message();
        }
        std::filesystem::remove(partial, ec);
        return false;
    }
    return true;
}

std::filesystem::path path_from_utf8(const std::string &utf8)
{
#ifdef _WIN32
    if (utf8.empty())
    {
        return std::filesystem::path();
    }
    const int length = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                           static_cast<int>(utf8.size()),
                                           nullptr, 0);
    std::wstring wide(static_cast<std::size_t>(length), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                        wide.data(), length);
    return std::filesystem::path(wide);
#else
    return std::filesystem::path(utf8);
#endif
}

bool split_stereo(const AudioBuffer &audio,
                  std::vector<float> *left,
                  std::vector<float> *right)
{
    const std::size_t frames = audio.frames();
    if (audio.channels != 1 && audio.channels != 2)
    {
        return false;
    }
    left->resize(frames);
    right->resize(frames);
    for (std::size_t i = 0; i < frames; ++i)
    {
        if (audio.channels == 1)
        {
            (*left)[i] = audio.interleaved[i];
            (*right)[i] = audio.interleaved[i];
        }
        else
        {
            (*left)[i] = audio.interleaved[2 * i];
            (*right)[i] = audio.interleaved[2 * i + 1];
        }
    }
    return true;
}

std::vector<float> interleave_stereo(const std::vector<float> &left,
                                     const std::vector<float> &right)
{
    const std::size_t frames = std::min(left.size(), right.size());
    std::vector<float> out(frames * 2);
    for (std::size_t i = 0; i < frames; ++i)
    {
        out[2 * i] = left[i];
        out[2 * i + 1] = right[i];
    }
    return out;
}

} // namespace lfsep
