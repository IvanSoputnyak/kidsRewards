import SwiftUI

enum AppTab: CaseIterable {
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

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: AppTab = .kids
    @Published var requestChildMode = false
    @Published var focusApprovalsSection = false
}
