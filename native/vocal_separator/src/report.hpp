// Machine-readable stdout protocol shared with the app
// (lib/features/transcription/data/services/separator_output_parser.dart).
//
//   LF_STAGE <load-model|separate|write>
//   LF_PROVIDER <dml|cpu>
//   LF_FALLBACK <reason>                   DirectML failed, retrying on CPU
//   LF_PROGRESS <0.0000-1.0000>
//   LF_STATS mix_rms=<f> vocals_rms=<f> accompaniment_rms=<f> seconds=<f>
//   LF_DONE vocals=<path> [accompaniment=<path>]
//   LF_ERROR <code> <message>
//
// Every other line is free-form log output and must be ignored by parsers.
#ifndef LFSEP_REPORT_HPP
#define LFSEP_REPORT_HPP

#include <string>
#include <vector>

namespace lfsep
{

struct StemStats
{
    double mix_rms = 0.0;
    double vocals_rms = 0.0;
    double accompaniment_rms = 0.0;
    double seconds = 0.0;
};

double rms(const std::vector<float> &samples);

// Mix minus vocals, sample by sample, for the accompaniment stem.
std::vector<float> subtract(const std::vector<float> &mix,
                            const std::vector<float> &vocals);

std::string progress_line(double fraction);
std::string stage_line(const std::string &stage);
std::string provider_line(const std::string &provider);
std::string fallback_line(const std::string &reason);
std::string stats_line(const StemStats &stats);
std::string error_line(int code, const std::string &message);

// Single-line form of a message: newlines and tabs become spaces.
std::string one_line(const std::string &text);

} // namespace lfsep

#endif // LFSEP_REPORT_HPP
