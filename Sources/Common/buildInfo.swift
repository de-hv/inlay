import BuildInfo

// See Sources/BuildInfo/include/BuildInfo.h
public let inlayAppVersion: String = unsafe String(cString: inlay_build_version())
public let gitHash: String = unsafe String(cString: inlay_build_git_hash())
public let gitShortHash: String = String(gitHash.prefix(7))
