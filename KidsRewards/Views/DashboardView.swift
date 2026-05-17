import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: RewardStore
    @State private var showingAddKid = false
    @State private var newKidName = ""
    @State private var kidPendingDeletion: Kid?
    @State private var kidBeingEdited: Kid?
    @State private var editedKidName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageHeader(eyebrow: "Household", title: "Kids Rewards") {
                        RoundIconButton(systemImage: "plus") {
                            showingAddKid = true
                        }
                    }

                    HStack(spacing: 12) {
                        MetricTile(title: "Available", value: store.totalAvailablePoints, tone: .coral)
                        MetricTile(title: "Vault", value: store.totalVaultPoints, tone: .mint)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "Kids")
                        if store.state.kids.isEmpty {
                            EmptyStatePanel(
                                systemImage: "plus",
                                title: "Add your first kid",
                                message: "Track points, savings, and allowance for everyone in the family.",
                                actionTitle: "Add Kid"
                            ) {
                                showingAddKid = true
                            }
                        } else {
                            VStack(spacing: 10) {
                                ForEach(store.state.kids) { kid in
                                    NavigationLink(value: kid) {
                                        KidRow(kid: kid)
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions {
                                        Button(role: .destructive) {
                                            kidPendingDeletion = kid
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            kidBeingEdited = kid
                                            editedKidName = kid.name
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(KidCoinTheme.primary)
                                    }
                                }
                            }
                        }
                    }

                    Text("1 point = \(Formatters.currency(store.state.settings.currencyPerPoint, code: store.state.settings.currencyCode))")
                        .font(.caption)
                        .foregroundStyle(KidCoinTheme.mutedText)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, 20)
                .padding(.top, 42)
                .padding(.bottom, 20)
            }
            .kidCoinBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .overlay {
                if showingAddKid {
                    AddKidModal(
                        name: $newKidName,
                        onCancel: {
                            newKidName = ""
                            showingAddKid = false
                        },
                        onAdd: {
                            store.addKid(name: newKidName)
                            newKidName = ""
                            showingAddKid = false
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                if kidBeingEdited != nil {
                    EditKidModal(
                        name: $editedKidName,
                        onCancel: {
                            editedKidName = ""
                            kidBeingEdited = nil
                        },
                        onSave: {
                            if let kidBeingEdited {
                                store.updateKid(kidBeingEdited, name: editedKidName)
                            }
                            editedKidName = ""
                            kidBeingEdited = nil
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(.easeOut(duration: 0.18), value: showingAddKid)
            .animation(.easeOut(duration: 0.18), value: kidBeingEdited)
            .navigationDestination(for: Kid.self) { kid in
                KidDetailView(kidID: kid.id)
            }
            .confirmationDialog(
                deletionTitle,
                isPresented: Binding(
                    get: { kidPendingDeletion != nil },
                    set: { if !$0 { kidPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Kid", role: .destructive) {
                    if let kidPendingDeletion {
                        store.deleteKid(kidPendingDeletion)
                    }
                    kidPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    kidPendingDeletion = nil
                }
            } message: {
                Text("This deletes their history.")
            }
        }
    }

    private var deletionTitle: String {
        guard let kidPendingDeletion else { return "Remove Kid?" }
        return "Remove \(kidPendingDeletion.name)?"
    }
}

private struct EditKidModal: View {
    @Binding var name: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        ZStack {
            KidCoinTheme.foreground.opacity(0.36)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 14) {
                Text("Edit Kid")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(KidCoinTheme.muted)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(spacing: 10) {
                    Button("Cancel", action: onCancel)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(KidCoinTheme.muted)
                        .clipShape(Capsule())

                    Button("Save") {
                        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        onSave()
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(KidCoinTheme.primary)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(22)
            .frame(maxWidth: 360)
            .tileCard(cornerRadius: 28)
            .padding(.horizontal, 24)
        }
    }
}

private struct AddKidModal: View {
    @Binding var name: String
    let onCancel: () -> Void
    let onAdd: () -> Void

    var body: some View {
        ZStack {
            KidCoinTheme.foreground.opacity(0.36)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 14) {
                Text("Add Kid")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text("They will start with 0 points.")
                    .font(.subheadline)
                    .foregroundStyle(KidCoinTheme.mutedText)

                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(KidCoinTheme.muted)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(spacing: 10) {
                    Button("Cancel", action: onCancel)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(KidCoinTheme.muted)
                        .clipShape(Capsule())

                    Button("Add") {
                        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        onAdd()
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(KidCoinTheme.primary)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(22)
            .frame(maxWidth: 360)
            .tileCard(cornerRadius: 28)
            .padding(.horizontal, 24)
        }
    }
}

private struct KidRow: View {
    let kid: Kid

    var body: some View {
        HStack(spacing: 14) {
            Text(String(kid.name.prefix(1)).uppercased())
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    LinearGradient(
                        colors: [KidCoinTheme.sunshine, KidCoinTheme.primary.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(kid.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(KidCoinTheme.foreground)
                HStack(spacing: 12) {
                    Label("\(kid.availablePoints) available", systemImage: "star.fill")
                        .foregroundStyle(KidCoinTheme.primary)
                    Label("\(kid.vaultPoints) vault", systemImage: "lock.fill")
                        .foregroundStyle(KidCoinTheme.mintText)
                }
                .font(.caption)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(KidCoinTheme.mutedText)
        }
        .padding(16)
        .tileCard(cornerRadius: 22)
    }
}
