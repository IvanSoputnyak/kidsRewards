import SwiftUI

@main
struct KidsRewardsApp: App {
    @StateObject private var store: RewardStore

    init() {
        _store = StateObject(wrappedValue: Self.makeStore())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
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

private final class UITestingParentPINManager: ParentPINManaging {
    private(set) var hasPIN = false
    private var savedPIN: String?

    func save(pin: String) {
        savedPIN = pin
        hasPIN = true
    }

    func clear() {
        savedPIN = nil
        hasPIN = false
    }

    func verify(pin: String) -> Bool {
        guard let savedPIN else { return true }
        return savedPIN == pin
    }
}
