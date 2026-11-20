// demucs.onnx engine: htdemucs (fine-tuned vocals model) on ONNX Runtime.
//
// Provider order for --provider auto is DirectML, then CPU. DirectML runs on
// any DirectX 12 GPU (the RTX 5080 target included) without shipping cuDNN;
// the CPU provider is the fallback when no usable adapter or driver exists,
// and on platforms built without DirectML.
#include "engine.hpp"

#include "demucs.hpp"
#include "wav_io.hpp"

#include <onnxruntime_cxx_api.h>

#include <exception>
#include <fstream>
#include <iterator>
#include <memory>

#if defined(_WIN32) && defined(LFSEP_WITH_DIRECTML)
#include <dml_provider_factory.h>
#define LFSEP_HAS_DML 1
#else
#define LFSEP_HAS_DML 0
#endif

namespace lfsep
{
namespace
{

bool read_model(const std::string &utf8_path,
                std::vector<char> *bytes,
                std::string *error)
{
    std::ifstream file(path_from_utf8(utf8_path), std::ios::binary);
    if (!file)
    {
        *error = "cannot open model file";
        return false;
    }
    bytes->assign(std::istreambuf_iterator<char>(file),
                  std::istreambuf_iterator<char>());
    if (bytes->size() < 1024)
    {
        *error = "model file is empty or truncated";
        return false;
    }
    return true;
}

// The model struct keeps C-string pointers into its own std::string members,
// so it must never move: each attempt builds a fresh one on the heap.
std::unique_ptr<demucsonnx::demucs_model> load(const std::vector<char> &bytes,
                                               Provider provider,
                                               const CliOptions &options,
                                               std::string *error)
{
    try
    {
        Ort::SessionOptions session_options;
        session_options.SetGraphOptimizationLevel(
            GraphOptimizationLevel::ORT_ENABLE_ALL);
        // Required by DirectML and harmless on CPU.
        session_options.SetExecutionMode(ExecutionMode::ORT_SEQUENTIAL);
        if (options.threads > 0)
        {
            session_options.SetIntraOpNumThreads(options.threads);
        }
        if (provider == Provider::directml)
        {
#if LFSEP_HAS_DML
            session_options.DisableMemPattern();
            Ort::ThrowOnError(
                OrtSessionOptionsAppendExecutionProvider_DML(session_options, 0));
#else
            *error = "this build has no DirectML support";
            return nullptr;
#endif
        }
        auto model = std::make_unique<demucsonnx::demucs_model>();
        if (!demucsonnx::load_model(bytes, *model, session_options))
        {
            *error = "model outputs disagree on the number of sources";
            return nullptr;
        }
        return model;
    }
    catch (const std::exception &e)
    {
        *error = e.what();
        return nullptr;
    }
}

std::vector<Provider> attempts_for(Provider requested)
{
    switch (requested)
    {
    case Provider::automatic:
        if (LFSEP_HAS_DML)
        {
            return {Provider::directml, Provider::cpu};
        }
        return {Provider::cpu};
    case Provider::directml:
        return {Provider::directml};
    case Provider::cpu:
        return {Provider::cpu};
    }
    return {Provider::cpu};
}

EngineResult failed(ExitCode code, std::string message)
{
    EngineResult result;
    result.code = code;
    result.error = std::move(message);
    return result;
}

} // namespace

EngineResult run_demucs_onnx(const EngineRequest &request,
                             const EngineCallbacks &callbacks)
{
    const CliOptions &options = *request.options;
    const std::vector<float> &left = *request.left;
    const std::vector<float> &right = *request.right;

    callbacks.stage("load-model");
    std::vector<char> bytes;
    std::string error;
    if (!read_model(options.model, &bytes, &error))
    {
        return failed(ExitCode::model, error);
    }

    const Eigen::Index frames = static_cast<Eigen::Index>(left.size());
    Eigen::MatrixXf audio(2, frames);
    for (Eigen::Index i = 0; i < frames; ++i)
    {
        audio(0, i) = left[static_cast<std::size_t>(i)];
        audio(1, i) = right[static_cast<std::size_t>(i)];
    }

    const std::vector<Provider> attempts = attempts_for(options.provider);
    for (std::size_t attempt = 0; attempt < attempts.size(); ++attempt)
    {
        const Provider provider = attempts[attempt];
        const bool last = attempt + 1 == attempts.size();
        if (attempt > 0)
        {
            callbacks.stage("load-model");
        }

        std::unique_ptr<demucsonnx::demucs_model> model =
            load(bytes, provider, options, &error);
        if (!model)
        {
            if (!last)
            {
                callbacks.fallback(std::string(provider_name(provider)) +
                                   " unavailable: " + error);
                continue;
            }
            return failed(ExitCode::model, std::string("cannot load model on ") +
                                               provider_name(provider) + ": " +
                                               error);
        }
        if (model->nb_sources <= options.vocals_index)
        {
            return failed(ExitCode::model,
                          "model has " + std::to_string(model->nb_sources) +
                              " sources, vocals index " +
                              std::to_string(options.vocals_index) +
                              " is out of range");
        }

        callbacks.provider(provider_name(provider));
        callbacks.stage("separate");
        Eigen::Tensor3dXf targets;
        try
        {
            demucsonnx::ProgressCallback progress =
                [&callbacks](float fraction, const std::string &) {
                    callbacks.progress(fraction);
                };
            targets = demucsonnx::demucs_inference(*model, audio, progress);
        }
        catch (const std::exception &e)
        {
            if (!last)
            {
                callbacks.fallback(std::string(provider_name(provider)) +
                                   " failed during inference: " + e.what());
                continue;
            }
            return failed(ExitCode::model,
                          std::string("inference failed: ") + e.what());
        }

        if (targets.dimension(2) != frames)
        {
            return failed(ExitCode::internal,
                          "separated stem length does not match the input");
        }
        EngineResult result;
        result.code = ExitCode::ok;
        result.vocals_left.resize(left.size());
        result.vocals_right.resize(right.size());
        for (Eigen::Index i = 0; i < frames; ++i)
        {
            result.vocals_left[static_cast<std::size_t>(i)] =
                targets(options.vocals_index, 0, i);
            result.vocals_right[static_cast<std::size_t>(i)] =
                targets(options.vocals_index, 1, i);
        }
        return result;
    }
    return failed(ExitCode::internal, "no execution provider was attempted");
}

} // namespace lfsep
