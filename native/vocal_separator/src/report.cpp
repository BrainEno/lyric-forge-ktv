#include "report.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>

namespace lfsep
{

double rms(const std::vector<float> &samples)
{
    if (samples.empty())
    {
        return 0.0;
    }
    double sum = 0.0;
    for (float sample : samples)
    {
        sum += static_cast<double>(sample) * sample;
    }
    return std::sqrt(sum / static_cast<double>(samples.size()));
}

std::vector<float> subtract(const std::vector<float> &mix,
                            const std::vector<float> &vocals)
{
    const std::size_t n = std::min(mix.size(), vocals.size());
    std::vector<float> out(n);
    for (std::size_t i = 0; i < n; ++i)
    {
        out[i] = mix[i] - vocals[i];
    }
    return out;
}

static std::string format_double(const char *format, double value)
{
    char buffer[64];
    std::snprintf(buffer, sizeof(buffer), format, value);
    return buffer;
}

std::string progress_line(double fraction)
{
    if (!std::isfinite(fraction))
    {
        fraction = 0.0;
    }
    fraction = std::clamp(fraction, 0.0, 1.0);
    return "LF_PROGRESS " + format_double("%.4f", fraction);
}

std::string stage_line(const std::string &stage)
{
    return "LF_STAGE " + one_line(stage);
}

std::string provider_line(const std::string &provider)
{
    return "LF_PROVIDER " + one_line(provider);
}

std::string fallback_line(const std::string &reason)
{
    return "LF_FALLBACK " + one_line(reason);
}

std::string stats_line(const StemStats &stats)
{
    return "LF_STATS mix_rms=" + format_double("%.6f", stats.mix_rms) +
           " vocals_rms=" + format_double("%.6f", stats.vocals_rms) +
           " accompaniment_rms=" +
           format_double("%.6f", stats.accompaniment_rms) +
           " seconds=" + format_double("%.3f", stats.seconds);
}

std::string error_line(int code, const std::string &message)
{
    return "LF_ERROR " + std::to_string(code) + " " + one_line(message);
}

std::string one_line(const std::string &text)
{
    std::string out = text;
    for (char &c : out)
    {
        if (c == '\n' || c == '\r' || c == '\t')
        {
            c = ' ';
        }
    }
    return out;
}

} // namespace lfsep
