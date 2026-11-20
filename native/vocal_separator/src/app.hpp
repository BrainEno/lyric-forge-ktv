#ifndef LFSEP_APP_HPP
#define LFSEP_APP_HPP

#include "engine.hpp"

#include <ostream>
#include <string>
#include <vector>

namespace lfsep
{

// Runs the CLI with UTF-8 [args] (program name excluded). Protocol lines and
// the help/version text go to [out], human-readable errors to [err].
int run_app(const std::vector<std::string> &args,
            std::ostream &out,
            std::ostream &err,
            const Engine &engine);

} // namespace lfsep

#endif // LFSEP_APP_HPP
