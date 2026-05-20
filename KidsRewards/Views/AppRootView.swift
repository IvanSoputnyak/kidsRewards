import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var store: RewardStore
    @StateObject private var router = AppRouter()
    @State private var isShowingLoadingScreen = true

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-reset")
    }

    var body: some View {
        ZStack {
            ContentView()
                .environmentObject(store)
                .environmentObject(router)
                .opacity(isShowingLoadingScreen ? 0 : 1)

            if isShowingLoadingScreen {
                LoadingScreenView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            await presentLoadingScreenIfNeeded()
        }
    }

    @MainActor
    private func presentLoadingScreenIfNeeded() async {
        guard !isUITesting else {
            isShowingLoadingScreen = false
            return
        }

        let minimumDisplay = Duration.milliseconds(850)
        try? await Task.sleep(for: minimumDisplay)

        withAnimation(.easeOut(duration: 0.32)) {
            isShowingLoadingScreen = false
        }
    }
}

#Preview {
    AppRootView()
        .environmentObject(RewardStore())
}
