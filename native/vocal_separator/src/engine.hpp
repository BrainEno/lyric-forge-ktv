// The separation step behind the CLI, as an interface so the command-line
// behaviour (validation, files, protocol) can be tested without ONNX Runtime.
#ifndef LFSEP_ENGINE_HPP
#define LFSEP_ENGINE_HPP

#include "cli_options.hpp"

#include <functional>
#include <string>
#include <vector>

namespace lfsep
{

struct EngineRequest
{
    const CliOptions *options = nullptr;
    // Equal-length stereo channels at kRequiredSampleRate.
    const std::vector<float> *left = nullptr;
    const std::vector<float> *right = nullptr;
};

struct EngineCallbacks
{
    std::function<void(double)> progress;           // 0..1 for the whole run
    std::function<void(const std::string &)> stage; // see report.hpp
    std::function<void(const std::string &)> provider;
    std::function<void(const std::string &)> fallback;
};

struct EngineResult
{
    ExitCode code = ExitCode::internal;
    std::string error;
    std::vector<float> vocals_left;
    std::vector<float> vocals_right;
};

using Engine = std::function<EngineResult(const EngineRequest &,
                                          const EngineCallbacks &)>;

// The real engine: demucs.onnx with DirectML or CPU (engine_demucs_onnx.cpp).
EngineResult run_demucs_onnx(const EngineRequest &request,
                             const EngineCallbacks &callbacks);

} // namespace lfsep

#endif // LFSEP_ENGINE_HPP
