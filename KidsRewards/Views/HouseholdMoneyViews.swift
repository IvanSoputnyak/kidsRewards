import SwiftUI

struct HouseholdAvailableRoute: Hashable {
    var initialKidID: UUID?
}

struct HouseholdVaultRoute: Hashable {
    var initialKidID: UUID?
}

@MainActor
private final class KidSelectionState: ObservableObject {
    @Published var selectedKidID: UUID?
    private let initialKidID: UUID?

    init(initialKidID: UUID?) {
        self.initialKidID = initialKidID
    }

    func resolvedKidID(in kids: [Kid]) -> UUID? {
        if let selectedKidID, kids.contains(where: { $0.id == selectedKidID }) {
            return selectedKidID
        }
        if let initialKidID, kids.contains(where: { $0.id == initialKidID }) {
            return initialKidID
        }
        return kids.first?.id
    }

    func sync(with kids: [Kid]) {
        guard !kids.isEmpty else {
            selectedKidID = nil
            return
        }
        if let selectedKidID, kids.contains(where: { $0.id == selectedKidID }) {
            return
        }
        if let initialKidID, kids.contains(where: { $0.id == initialKidID }) {
            selectedKidID = initialKidID
            return
        }
        selectedKidID = kids.first?.id
    }
}

/// Household entry for available points — pick a kid, then cash out / adjust (allowance settings are global on each screen).
struct HouseholdAvailableView: View {
    @EnvironmentObject private var store: RewardStore
    @StateObject private var selection: KidSelectionState

    init(initialKidID: UUID?) {
        _selection = StateObject(wrappedValue: KidSelectionState(initialKidID: initialKidID))
    }

    var body: some View {
        Group {
            if store.state.kids.isEmpty {
                ContentUnavailableView(
                    "No Kids Yet",
                    systemImage: "person.2",
                    description: Text("Add a kid from the household screen first.")
                )
                .kidCoinBackground()
            } else if let kidID = selection.resolvedKidID(in: store.state.kids) {
                VStack(spacing: 0) {
                    KidPickerBar(
                        kids: store.state.kids,
                        selectedKidID: Binding(
                            get: { selection.selectedKidID ?? kidID },
                            set: { selection.selectedKidID = $0 }
                        )
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                    KidAvailableView(kidID: kidID, embeddedInHousehold: true)
                }
            }
        }
        .navigationTitle("Available")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { selection.sync(with: store.state.kids) }
        .onChange(of: store.state.kids.map(\.id)) { _, _ in
            selection.sync(with: store.state.kids)
        }
    }
}

/// Household entry for vault — pick a kid, then deposit / withdraw / goals (vault rate & schedule are household-wide).
struct HouseholdVaultView: View {
    @EnvironmentObject private var store: RewardStore
    @StateObject private var selection: KidSelectionState

    init(initialKidID: UUID?) {
        _selection = StateObject(wrappedValue: KidSelectionState(initialKidID: initialKidID))
    }

    var body: some View {
        Group {
            if store.state.kids.isEmpty {
                ContentUnavailableView(
                    "No Kids Yet",
                    systemImage: "person.2",
                    description: Text("Add a kid from the household screen first.")
                )
                .kidCoinBackground()
            } else if let kidID = selection.resolvedKidID(in: store.state.kids) {
                VStack(spacing: 0) {
                    KidPickerBar(
                        kids: store.state.kids,
                        selectedKidID: Binding(
                            get: { selection.selectedKidID ?? kidID },
                            set: { selection.selectedKidID = $0 }
                        )
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                    KidVaultView(kidID: kidID, embeddedInHousehold: true)
                }
            }
        }
        .navigationTitle("Vault")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { selection.sync(with: store.state.kids) }
        .onChange(of: store.state.kids.map(\.id)) { _, _ in
            selection.sync(with: store.state.kids)
        }
    }
}

struct KidPickerBar: View {
    let kids: [Kid]
    @Binding var selectedKidID: UUID

    var body: some View {
        if kids.count > 1 {
            Picker("Kid", selection: $selectedKidID) {
                ForEach(kids) { kid in
                    Text(kid.name).tag(kid.id)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Select kid")
        }
    }
}
