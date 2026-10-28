public let stableInlayAppId: String = "com.dehv.inlay"
#if DEBUG
    public let inlayAppId: String = "com.dehv.inlay.debug"
    public let inlayAppName: String = "Inlay-Debug"
#else
    public let inlayAppId: String = stableInlayAppId
    public let inlayAppName: String = "Inlay"
#endif
