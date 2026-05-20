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
    private(set) static var isAvailableOverride: Bool?

    static func setAvailableForTesting(_ available: Bool?) {
        isAvailableOverride = available
    }
    #endif

    static var isAvailable: Bool {
        #if DEBUG
        if let isAvailableOverride {
            return isAvailableOverride
        }
        #endif
        return AppDistribution.iCloudKeyValueBackupEnabled
    }
}
