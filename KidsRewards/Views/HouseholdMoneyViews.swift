import SwiftUI

struct HouseholdAvailableRoute: Hashable {
    var initialKidID: UUID?
}

struct HouseholdVaultRoute: Hashable {
    var initialKidID: UUID?
}

/// Household entry for available points — pick a kid, then cash out / adjust (allowance settings are global on each screen).
struct HouseholdAvailableView: View {
    @EnvironmentObject private var store: RewardStore
    let initialKidID: UUID?

    @State private var selectedKidID: UUID?

    var body: some View {
        Group {
            if store.state.kids.isEmpty {
                ContentUnavailableView(
                    "No Kids Yet",
                    systemImage: "person.2",
                    description: Text("Add a kid from the household screen first.")
                )
                .kidCoinBackground()
            } else if let kidID = resolvedKidID {
                VStack(spacing: 0) {
                    KidPickerBar(
                        kids: store.state.kids,
                        selectedKidID: Binding(
                            get: { selectedKidID ?? kidID },
                            set: { selectedKidID = $0 }
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
        .onAppear(perform: syncSelectedKid)
        .onChange(of: store.state.kids.map(\.id)) { _, _ in
            syncSelectedKid()
        }
    }

    private var resolvedKidID: UUID? {
        if let selectedKidID,
           store.state.kids.contains(where: { $0.id == selectedKidID }) {
            return selectedKidID
        }
        if let initialKidID,
           store.state.kids.contains(where: { $0.id == initialKidID }) {
            return initialKidID
        }
        return store.state.kids.first?.id
    }

    private func syncSelectedKid() {
        guard !store.state.kids.isEmpty else {
            selectedKidID = nil
            return
        }
        if let selectedKidID,
           store.state.kids.contains(where: { $0.id == selectedKidID }) {
            return
        }
        if let initialKidID,
           store.state.kids.contains(where: { $0.id == initialKidID }) {
            selectedKidID = initialKidID
            return
        }
        selectedKidID = store.state.kids.first?.id
    }
}

/// Household entry for vault — pick a kid, then deposit / withdraw / goals (vault rate & schedule are household-wide).
struct HouseholdVaultView: View {
    @EnvironmentObject private var store: RewardStore
    let initialKidID: UUID?

    @State private var selectedKidID: UUID?

    var body: some View {
        Group {
            if store.state.kids.isEmpty {
                ContentUnavailableView(
                    "No Kids Yet",
                    systemImage: "person.2",
                    description: Text("Add a kid from the household screen first.")
                )
                .kidCoinBackground()
            } else if let kidID = resolvedKidID {
                VStack(spacing: 0) {
                    KidPickerBar(
                        kids: store.state.kids,
                        selectedKidID: Binding(
                            get: { selectedKidID ?? kidID },
                            set: { selectedKidID = $0 }
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
        .onAppear(perform: syncSelectedKid)
        .onChange(of: store.state.kids.map(\.id)) { _, _ in
            syncSelectedKid()
        }
    }

    private var resolvedKidID: UUID? {
        if let selectedKidID,
           store.state.kids.contains(where: { $0.id == selectedKidID }) {
            return selectedKidID
        }
        if let initialKidID,
           store.state.kids.contains(where: { $0.id == initialKidID }) {
            return initialKidID
        }
        return store.state.kids.first?.id
    }

    private func syncSelectedKid() {
        guard !store.state.kids.isEmpty else {
            selectedKidID = nil
            return
        }
        if let selectedKidID,
           store.state.kids.contains(where: { $0.id == selectedKidID }) {
            return
        }
        if let initialKidID,
           store.state.kids.contains(where: { $0.id == initialKidID }) {
            selectedKidID = initialKidID
            return
        }
        selectedKidID = store.state.kids.first?.id
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
