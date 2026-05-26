import Foundation

/// How this build is meant to be shipped. Flip `iCloudKeyValueBackupEnabled` only after
/// enrolling in the paid Apple Developer Program and linking iCloud key-value entitlements.
enum AppDistribution {
    /// Personal / free Apple ID signing — no annual Apple fee on your side.
    static let usesFreeDeveloperSigning = true

    /// iCloud KV requires a paid team + `KidsRewards.entitlements`. Off for zero-cost builds.
    static let iCloudKeyValueBackupEnabled = false
}

enum ICloudBackup {
    #if DEBUG
    private static let overrideLock = NSLock()
    private static var _isAvailableOverride: Bool?

    static func setAvailableForTesting(_ available: Bool?) {
        overrideLock.withLock { _isAvailableOverride = available }
    }
    #endif

    static var isAvailable: Bool {
        #if DEBUG
        let override = overrideLock.withLock { _isAvailableOverride }
        if let override { return override }
        #endif
        return AppDistribution.iCloudKeyValueBackupEnabled
    }
}
