#ifndef inlay_build_info_h
#define inlay_build_info_h

// Version and git hash of the build. Package.swift takes them from the INLAY_VERSION and INLAY_GIT_HASH
// environment variables (scripts/build-app.sh sets both) and passes them to this target as preprocessor
// definitions. That way no source file has to be generated, and a build never dirties the git working tree.
const char *_Nonnull inlay_build_version(void);
const char *_Nonnull inlay_build_git_hash(void);

#endif
