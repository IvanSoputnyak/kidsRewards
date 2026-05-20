import SwiftUI

struct KidDetailView: View {
    @EnvironmentObject private var store: RewardStore
    let kidID: UUID

    @State private var transactionBeingCorrected: RewardTransaction?
    @State private var transactionPendingDeletion: RewardTransaction?
    @State private var correctedNote = ""
    @State private var correctedPoints = 1
    @State private var correctedAddsPoints = true
    @State private var correctionErrorMessage = ""

    private var kid: Kid? {
        store.state.kids.first { $0.id == kidID }
    }

    var body: some View {
        Group {
            if let kid {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        detailHeader(for: kid)
                        awardWorkSection(for: kid)
                        historySection(for: kid)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                }
                .kidCoinScroll()
                .kidCoinBackground()
                .navigationTitle("Kids")
                .navigationBarTitleDisplayMode(.inline)
                .tint(KidCoinTheme.primary)
                .navigationDestination(for: KidVaultRoute.self) { route in
                    KidVaultView(kidID: route.kidID)
                }
                .navigationDestination(for: KidAvailableRoute.self) { route in
                    KidAvailableView(kidID: route.kidID)
                }
                .overlay {
                    if let transactionBeingCorrected {
                        CorrectTransactionModal(
                            transaction: transactionBeingCorrected,
                            note: $correctedNote,
                            points: $correctedPoints,
                            addsPoints: $correctedAddsPoints,
                            onCancel: {
                                clearCorrectionState()
                            },
                            onSave: {
                                let points = transactionBeingCorrected.kind == .adjusted
                                    ? (correctedAddsPoints ? correctedPoints : -correctedPoints)
                                    : correctedPoints
                                let didCorrect = store.correctTransaction(
                                    transactionBeingCorrected,
                                    points: points,
                                    note: correctedNote
                                )
                                clearCorrectionState()
                                if !didCorrect {
                                    correctionErrorMessage = "That correction would make available or vault points negative."
                                }
                            }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .animation(.easeOut(duration: 0.18), value: transactionBeingCorrected)
                .confirmationDialog(
                    "Delete Transaction?",
                    isPresented: Binding(
                        get: { transactionPendingDeletion != nil },
                        set: { if !$0 { transactionPendingDeletion = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Delete Transaction", role: .destructive) {
                        if let transactionPendingDeletion {
                            let didDelete = store.deleteTransaction(transactionPendingDeletion)
                            if !didDelete {
                                correctionErrorMessage = "That transaction cannot be deleted because it would make available or vault points negative."
                            }
                        }
                        transactionPendingDeletion = nil
                    }
                    Button("Cancel", role: .cancel) {
                        transactionPendingDeletion = nil
                    }
                } message: {
                    Text("Deleting a transaction also reverses its current balance effect.")
                }
                .alert("Correction Not Applied", isPresented: Binding(
                    get: { !correctionErrorMessage.isEmpty },
                    set: { if !$0 { correctionErrorMessage = "" } }
                )) {
                    Button("OK", role: .cancel) {
                        correctionErrorMessage = ""
                    }
                } message: {
                    Text(correctionErrorMessage)
                }
            } else {
                ContentUnavailableView("Kid Not Found", systemImage: "person.crop.circle.badge.questionmark")
                    .kidCoinBackground()
            }
        }
    }

    private func detailHeader(for kid: Kid) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(kid.name)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(KidCoinTheme.foreground)

            HStack(spacing: 12) {
                NavigationLink(value: KidAvailableRoute(kidID: kid.id)) {
                    MetricTile(
                        title: "Available",
                        value: kid.availablePoints,
                        systemImage: "star.fill",
                        tone: .coral,
                        showsDisclosure: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Available, \(kid.availablePoints) points")
                .accessibilityHint("Opens cash out, adjustments, and allowance")

                NavigationLink(value: KidVaultRoute(kidID: kid.id)) {
                    MetricTile(
                        title: "Vault",
                        value: kid.vaultPoints,
                        systemImage: "lock.fill",
                        tone: .mint,
                        showsDisclosure: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Vault, \(kid.vaultPoints) points")
                .accessibilityHint("Opens vault and savings goal")
            }

            Text("Cash value: \(Formatters.currency(store.currencyValue(for: kid.availablePoints), code: store.state.settings.currencyCode))")
                .font(.subheadline)
                .foregroundStyle(KidCoinTheme.mutedText)
                .padding(.horizontal, 4)

            if let goal = kid.savingsGoal {
                Text("\(goal.title): \(store.savingsGoalProgress(for: kid))/\(goal.targetPoints) total")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KidCoinTheme.mintText)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func awardWorkSection(for kid: Kid) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Award Work")
            if store.state.tasks.isEmpty {
                EmptyStatePanel(
                    systemImage: "checklist",
                    title: "No work yet",
                    message: "Add work in the Work tab to start earning."
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(store.tasks(for: kid)) { task in
                        let isAvailable = store.isTaskAvailable(task, for: kid)
                        Button {
                            store.award(task: task, to: kid)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.title)
                                        .font(.subheadline.weight(.semibold))
                                    if task.recurrence != .none && !isAvailable {
                                        Text("Available \(task.recurrence.label.lowercased())")
                                            .font(.caption2)
                                            .foregroundStyle(KidCoinTheme.mutedText)
                                    }
                                }
                                Spacer()
                                Text("+\(task.points)")
                                    .font(.subheadline.weight(.bold))
                                    .monospacedDigit()
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(KidCoinTheme.primary.opacity(0.12))
                                    .foregroundStyle(KidCoinTheme.primary)
                                    .clipShape(Capsule())
                            }
                            .padding(15)
                            .tileCard(cornerRadius: 18)
                        }
                        .disabled(!isAvailable)
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(task.title), \(task.points) points")
                        .accessibilityHint(isAvailable ? "Awards points" : "This recurring chore is not due yet")
                    }
                }
            }
        }
    }

    private func historySection(for kid: Kid) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "History")
            let transactions = store.transactions(for: kid)
            if transactions.isEmpty {
                Text("No activity yet.")
                    .font(.subheadline)
                    .foregroundStyle(KidCoinTheme.mutedText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                VStack(spacing: 8) {
                    ForEach(transactions) { transaction in
                        TransactionRow(
                            transaction: transaction,
                            currencyCode: store.state.settings.currencyCode,
                            onCorrect: {
                                transactionBeingCorrected = transaction
                                correctedNote = transaction.note
                                correctedPoints = max(abs(transaction.points), 1)
                                correctedAddsPoints = transaction.points >= 0
                            },
                            onDelete: {
                                transactionPendingDeletion = transaction
                            }
                        )
                    }
                }
            }
        }
    }

    private func clearCorrectionState() {
        transactionBeingCorrected = nil
        correctedNote = ""
        correctedPoints = 1
        correctedAddsPoints = true
    }

}

private struct TransactionRow: View {
    let transaction: RewardTransaction
    let currencyCode: String
    let onCorrect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.note)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption2)
                    .foregroundStyle(KidCoinTheme.mutedText)
            }

            Spacer()

            Text(pointsLabel)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(pointsBackground)
                .foregroundStyle(pointsForeground)
                .clipShape(Capsule())

            Button(action: onCorrect) {
                Image(systemName: "pencil")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KidCoinTheme.primary)
                    .frame(width: 32, height: 32)
                    .background(KidCoinTheme.primary.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Correct transaction")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KidCoinTheme.destructive)
                    .frame(width: 32, height: 32)
                    .background(KidCoinTheme.destructive.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete transaction")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .tileCard(cornerRadius: 14)
    }

    private var detailText: String {
        let formattedDate = transaction.date.formatted(date: .abbreviated, time: .omitted)
        if let amount = transaction.currencyAmount {
            return "\(formattedDate) · \(Formatters.currency(amount, code: currencyCode))"
        }
        return formattedDate
    }

    private var pointsLabel: String {
        transaction.pointsDisplayLabel
    }

    private var pointsBackground: Color {
        switch transaction.kind {
        case .cashedOut:
            return KidCoinTheme.destructive.opacity(0.12)
        case .deposited:
            return KidCoinTheme.mint.opacity(0.25)
        case .withdrawn:
            return KidCoinTheme.primary.opacity(0.2)
        case .earned, .interest, .adjusted:
            return KidCoinTheme.primary.opacity(0.12)
        }
    }

    private var pointsForeground: Color {
        switch transaction.kind {
        case .cashedOut:
            return KidCoinTheme.destructive
        case .deposited:
            return KidCoinTheme.mintText
        case .withdrawn:
            return KidCoinTheme.primary
        case .earned, .interest, .adjusted:
            return KidCoinTheme.primary
        }
    }
}

private struct CorrectTransactionModal: View {
    let transaction: RewardTransaction
    @Binding var note: String
    @Binding var points: Int
    @Binding var addsPoints: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        ZStack {
            KidCoinTheme.foreground.opacity(0.36)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 14) {
                Text("Correct Transaction")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text(transaction.kindLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KidCoinTheme.mutedText)

                if transaction.kind == .adjusted {
                    Picker("Adjustment type", selection: $addsPoints) {
                        Text("Add").tag(true)
                        Text("Remove").tag(false)
                    }
                    .pickerStyle(.segmented)
                }

                TextField("Note", text: $note)
                    .kidCoinNameEntry()
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(KidCoinTheme.muted)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack {
                    Text("Points")
                        .font(.subheadline)
                        .foregroundStyle(KidCoinTheme.mutedText)
                    Spacer()
                    CounterControl(value: $points, range: 1...500)
                }

                HStack(spacing: 10) {
                    Button("Cancel", action: onCancel)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(KidCoinTheme.muted)
                        .clipShape(Capsule())

                    Button("Save", action: onSave)
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
            .frame(maxWidth: 380)
            .tileCard(cornerRadius: 28)
            .padding(.horizontal, 24)
        }
    }
}

private extension RewardTransaction {
    var kindLabel: String {
        switch kind {
        case .earned:
            return "Earned points"
        case .deposited:
            return "Vault deposit"
        case .withdrawn:
            return "Vault withdrawal"
        case .cashedOut:
            return "Cash out"
        case .interest:
            return "Vault interest"
        case .adjusted:
            return "Manual adjustment"
        }
    }
}
