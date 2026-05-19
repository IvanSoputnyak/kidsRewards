import SwiftUI

@main
struct KidsRewardsApp: App {
    @StateObject private var store: RewardStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _store = StateObject(wrappedValue: Self.makeStore())
        RewardNotifications.requestAuthorizationIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(store)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.runScheduledMaintenance()
                    }
                }
        }
    }

    private static func makeStore() -> RewardStore {
        guard CommandLine.arguments.contains("--ui-testing-reset") else {
            return RewardStore()
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kids-rewards-ui-tests-\(UUID().uuidString).json")
        return RewardStore(fileURL: fileURL, pinManager: UITestingParentPINManager())
    }
}

private final class UITestingParentPINManager: ParentPINManaging, @unchecked Sendable {
    private(set) var hasPIN = false
    private var savedPIN: String?

    @discardableResult
    func save(pin: String) -> Bool {
        savedPIN = pin
        hasPIN = true
        return true
    }

    @discardableResult
    func clear() -> Bool {
        savedPIN = nil
        hasPIN = false
        return true
    }

    func verify(pin: String) -> Bool {
        guard let savedPIN else { return true }
        return savedPIN == pin
    }
}
