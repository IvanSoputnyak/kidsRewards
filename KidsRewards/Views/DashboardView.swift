import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: RewardStore
    @State private var showingAddKid = false
    @State private var newKidName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        SummaryMetric(title: "Available", value: "\(store.totalAvailablePoints)")
                        SummaryMetric(title: "Vault", value: "\(store.totalVaultPoints)")
                    }
                    .padding(.vertical, 6)
                }

                Section("Kids") {
                    ForEach(store.state.kids) { kid in
                        NavigationLink(value: kid) {
                            KidRow(kid: kid)
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { store.state.kids[$0] }.forEach(store.deleteKid)
                    }
                }
            }
            .navigationTitle("Kids Rewards")
            .navigationDestination(for: Kid.self) { kid in
                KidDetailView(kidID: kid.id)
            }
            .toolbar {
                Button {
                    showingAddKid = true
                } label: {
                    Label("Add Kid", systemImage: "plus")
                }
            }
            .alert("Add Kid", isPresented: $showingAddKid) {
                TextField("Name", text: $newKidName)
                Button("Cancel", role: .cancel) { newKidName = "" }
                Button("Add") {
                    store.addKid(name: newKidName)
                    newKidName = ""
                }
            }
        }
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct KidRow: View {
    let kid: Kid

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kid.name)
                .font(.headline)
            HStack {
                Label("\(kid.availablePoints) available", systemImage: "star.fill")
                Label("\(kid.vaultPoints) in vault", systemImage: "lock.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
