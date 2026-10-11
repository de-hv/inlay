public let stableInlayAppId: String = "com.davidhiguita.inlay"
#if DEBUG
    public let inlayAppId: String = "com.davidhiguita.inlay.debug"
    public let inlayAppName: String = "Inlay-Debug"
#else
    public let inlayAppId: String = stableInlayAppId
    public let inlayAppName: String = "Inlay"
#endif
