#ifndef inlay_build_info_h
#define inlay_build_info_h

// Version and git hash of the build. scripts/build-app.sh writes them to a header in .build, outside of the
// sources: a build never dirties the git working tree, and a new git hash doesn't build everything again
const char *_Nonnull inlay_build_version(void);
const char *_Nonnull inlay_build_git_hash(void);

#endif
