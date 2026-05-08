import SwiftUI

@main
struct KidsRewardsApp: App {
    @StateObject private var store = RewardStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
