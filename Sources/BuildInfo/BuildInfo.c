#include "BuildInfo.h"

// Written by scripts/build-app.sh: '#define INLAY_BUILD_VERSION 0.1.0' and '#define INLAY_BUILD_GIT_HASH <hash>'
#if __has_include("inlay_build_info_values.h")
#include "inlay_build_info_values.h"
#endif

#ifndef INLAY_BUILD_VERSION
#define INLAY_BUILD_VERSION 0.0.0-dev
#endif
#ifndef INLAY_BUILD_GIT_HASH
#define INLAY_BUILD_GIT_HASH SNAPSHOT
#endif

// The values come unquoted, so that nothing has to get the quoting right
#define INLAY_STRINGIFY_(x) #x
#define INLAY_STRINGIFY(x) INLAY_STRINGIFY_(x)

const char *inlay_build_version(void) { return INLAY_STRINGIFY(INLAY_BUILD_VERSION); }
const char *inlay_build_git_hash(void) { return INLAY_STRINGIFY(INLAY_BUILD_GIT_HASH); }
