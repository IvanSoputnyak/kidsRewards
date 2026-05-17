import SwiftUI

struct ContentView: View {
    @State private var selectedTab: AppTab = .kids

    var body: some View {
        ZStack(alignment: .bottom) {
            KidCoinTheme.background.ignoresSafeArea()

            Group {
                switch selectedTab {
                case .kids:
                    DashboardView()
                case .work:
                    TasksView()
                case .settings:
                    SettingsView()
                }
            }
            .safeAreaPadding(.bottom, 92)

            KidCoinTabBar(selectedTab: $selectedTab)
        }
    }
}

private enum AppTab: CaseIterable {
    case kids
    case work
    case settings

    var title: String {
        switch self {
        case .kids: "Kids"
        case .work: "Work"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .kids: "person.2.fill"
        case .work: "checklist"
        case .settings: "gearshape.fill"
        }
    }
}

private struct KidCoinTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 38, height: 34)
                            .background(selectedTab == tab ? KidCoinTheme.primary.opacity(0.12) : .clear)
                            .clipShape(Capsule())
                        Text(tab.title)
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(selectedTab == tab ? KidCoinTheme.primary : KidCoinTheme.mutedText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .background(KidCoinTheme.card.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(KidCoinTheme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 22, x: 0, y: 8)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }
}
