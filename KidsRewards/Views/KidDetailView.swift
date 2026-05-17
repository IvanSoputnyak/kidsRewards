import SwiftUI

struct KidDetailView: View {
    @EnvironmentObject private var store: RewardStore
    let kidID: UUID

    @State private var depositPoints = 1
    @State private var cashOutPoints = 1
    @State private var adjustmentPoints = 1
    @State private var adjustmentAddsPoints = true
    @State private var adjustmentNote = ""
    @State private var transactionBeingCorrected: RewardTransaction?
    @State private var transactionPendingDeletion: RewardTransaction?
    @State private var correctedNote = ""
    @State private var correctedPoints = 1
    @State private var correctedAddsPoints = true
    @State private var correctionErrorMessage = ""
    @State private var pendingParentAction: ParentAction?
    @State private var goalTitle = ""
    @State private var goalTargetPoints = 25

    private var kid: Kid? {
        store.state.kids.first { $0.id == kidID }
    }

    var body: some View {
        Group {
            if let kid {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        detailHeader(for: kid)
                        savingsGoalSection(for: kid)
                        awardWorkSection(for: kid)
                        manualAdjustmentSection(for: kid)
                        vaultSection(for: kid)
                        cashOutSection(for: kid)
                        historySection(for: kid)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }
                .kidCoinBackground()
                .navigationTitle("Kids")
                .navigationBarTitleDisplayMode(.inline)
                .tint(KidCoinTheme.primary)
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
                .confirmationDialog(
                    parentActionTitle,
                    isPresented: Binding(
                        get: { pendingParentAction != nil },
                        set: { if !$0 { pendingParentAction = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button(parentActionConfirmTitle, role: pendingParentAction == .cashOut ? .destructive : nil) {
                        if let pendingParentAction {
                            runParentAction(pendingParentAction, for: kid)
                        }
                        pendingParentAction = nil
                    }
                    Button("Cancel", role: .cancel) {
                        pendingParentAction = nil
                    }
                } message: {
                    Text(parentActionMessage)
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

    private func manualAdjustmentSection(for kid: Kid) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Manual Adjustment")
            VStack(spacing: 14) {
                Picker("Adjustment type", selection: $adjustmentAddsPoints) {
                    Text("Add").tag(true)
                    Text("Remove").tag(false)
                }
                .pickerStyle(.segmented)

                TextField("Reason, for example correction", text: $adjustmentNote)
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
                    CounterControl(value: $adjustmentPoints, range: 1...500)
                }

                PillButton(
                    title: adjustmentAddsPoints ? "Add \(adjustmentPoints) Points" : "Remove \(adjustmentPoints) Points",
                    systemImage: adjustmentAddsPoints ? "plus.circle.fill" : "minus.circle.fill",
                    tone: adjustmentAddsPoints ? .primary : .subtle,
                    disabled: !adjustmentAddsPoints && kid.availablePoints == 0
                ) {
                    let signedPoints = adjustmentAddsPoints ? adjustmentPoints : -adjustmentPoints
                    store.adjust(points: signedPoints, note: adjustmentNote, for: kid)
                    adjustmentPoints = 1
                    adjustmentNote = ""
                    adjustmentAddsPoints = true
                }
            }
            .padding(18)
            .tileCard(cornerRadius: 26)
        }
    }

    private func detailHeader(for kid: Kid) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(kid.name)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(KidCoinTheme.foreground)

            HStack(spacing: 12) {
                MetricTile(title: "Available", value: kid.availablePoints, systemImage: "star.fill", tone: .coral)
                MetricTile(title: "Vault", value: kid.vaultPoints, systemImage: "lock.fill", tone: .mint)
            }

            Text("Cash value: \(Formatters.currency(store.currencyValue(for: kid.availablePoints), code: store.state.settings.currencyCode))")
                .font(.subheadline)
                .foregroundStyle(KidCoinTheme.mutedText)
                .padding(.horizontal, 4)
        }
    }

    private func savingsGoalSection(for kid: Kid) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Savings Goal")
            VStack(alignment: .leading, spacing: 14) {
                if let goal = kid.savingsGoal {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(goal.title)
                                .font(.headline.weight(.bold))
                            Text("\(kid.vaultPoints) of \(goal.targetPoints) vault points")
                                .font(.caption)
                                .foregroundStyle(KidCoinTheme.mutedText)
                        }
                        Spacer()
                        Button {
                            store.clearSavingsGoal(for: kid)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(KidCoinTheme.destructive)
                                .frame(width: 32, height: 32)
                                .background(KidCoinTheme.destructive.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear savings goal")
                    }

                    ProgressView(value: Double(min(kid.vaultPoints, goal.targetPoints)), total: Double(goal.targetPoints))
                        .tint(KidCoinTheme.mintText)
                        .accessibilityLabel("Savings goal progress")
                        .accessibilityValue("\(kid.vaultPoints) of \(goal.targetPoints) points")
                }

                TextField("Goal name", text: $goalTitle)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(KidCoinTheme.muted)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack {
                    Text("Target")
                        .font(.subheadline)
                        .foregroundStyle(KidCoinTheme.mutedText)
                    Spacer()
                    CounterControl(value: $goalTargetPoints, range: 1...500)
                }

                PillButton(
                    title: kid.savingsGoal == nil ? "Set Goal" : "Update Goal",
                    systemImage: "target",
                    tone: .mint,
                    disabled: goalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    store.updateSavingsGoal(for: kid, title: goalTitle, targetPoints: goalTargetPoints)
                    goalTitle = ""
                    goalTargetPoints = 25
                }
            }
            .padding(18)
            .tileCard(cornerRadius: 26)
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
                    ForEach(store.state.tasks) { task in
                        Button {
                            store.award(task: task, to: kid)
                        } label: {
                            HStack {
                                Text(task.title)
                                    .font(.subheadline.weight(.semibold))
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
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func vaultSection(for kid: Kid) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Vault")
            VStack(spacing: 16) {
                HStack {
                    Text("Deposit")
                        .font(.subheadline)
                    Spacer()
                    CounterControl(value: $depositPoints, range: 1...max(kid.availablePoints, 1))
                }
                PillButton(
                    title: "Deposit \(depositPoints) \(depositPoints == 1 ? "point" : "points")",
                    systemImage: "arrow.down.to.line",
                    tone: .mint,
                    disabled: kid.availablePoints == 0
                ) {
                    store.deposit(points: depositPoints, for: kid)
                    depositPoints = 1
                }
                PillButton(
                    title: "Apply \(Formatters.percent(store.state.settings.vaultInterestRate)) Interest",
                    systemImage: "percent",
                    tone: .subtle,
                    disabled: store.interestPoints(for: kid) == 0
                ) {
                    pendingParentAction = .interest
                }
            }
            .padding(18)
            .tileCard(cornerRadius: 26)
        }
    }

    private func cashOutSection(for kid: Kid) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Cash Out")
            VStack(spacing: 16) {
                HStack {
                    Text("Cash out")
                        .font(.subheadline)
                    Spacer()
                    CounterControl(value: $cashOutPoints, range: 1...max(kid.availablePoints, 1))
                }
                PillButton(
                    title: cashOutButtonTitle,
                    systemImage: "banknote",
                    tone: .primary,
                    disabled: kid.availablePoints == 0
                ) {
                    pendingParentAction = .cashOut
                }
            }
            .padding(18)
            .tileCard(cornerRadius: 26)
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

    private var cashOutButtonTitle: String {
        let value = Formatters.currency(store.currencyValue(for: cashOutPoints), code: store.state.settings.currencyCode)
        return store.state.settings.approvalFlowEnabled ? "Request Cash Out \(value)" : "Cash Out \(value)"
    }

    private var parentActionTitle: String {
        guard let pendingParentAction else { return "" }
        switch pendingParentAction {
        case .cashOut:
            return store.state.settings.approvalFlowEnabled ? "Request Cash Out?" : "Cash Out Points?"
        case .interest:
            return store.state.settings.approvalFlowEnabled ? "Request Interest?" : "Apply Vault Interest?"
        }
    }

    private var parentActionConfirmTitle: String {
        guard let pendingParentAction else { return "" }
        let prefix = store.state.settings.approvalFlowEnabled ? "Request" : "Confirm"
        switch pendingParentAction {
        case .cashOut:
            return "\(prefix) Cash Out"
        case .interest:
            return "\(prefix) Interest"
        }
    }

    private var parentActionMessage: String {
        guard let kid, let pendingParentAction else { return "" }
        switch pendingParentAction {
        case .cashOut:
            let amount = min(cashOutPoints, kid.availablePoints)
            let value = Formatters.currency(store.currencyValue(for: amount), code: store.state.settings.currencyCode)
            if store.state.settings.approvalFlowEnabled {
                return "This creates a pending parent approval for \(amount) points worth \(value)."
            }
            return "This removes \(amount) available points from \(kid.name) and records a \(value) cash out."
        case .interest:
            let points = store.interestPoints(for: kid)
            if store.state.settings.approvalFlowEnabled {
                return "This creates a pending parent approval for \(points) vault interest points."
            }
            return "This adds \(points) points to \(kid.name)'s vault."
        }
    }

    private func runParentAction(_ action: ParentAction, for kid: Kid) {
        switch action {
        case .cashOut:
            if store.state.settings.approvalFlowEnabled {
                store.requestCashOut(points: cashOutPoints, for: kid)
            } else {
                store.cashOut(points: cashOutPoints, for: kid)
            }
            cashOutPoints = 1
        case .interest:
            if store.state.settings.approvalFlowEnabled {
                store.requestInterest(for: kid)
            } else {
                store.applyInterest(to: kid)
            }
        }
    }
}

private enum ParentAction {
    case cashOut
    case interest
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

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KidCoinTheme.destructive)
                    .frame(width: 32, height: 32)
                    .background(KidCoinTheme.destructive.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
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
        case .cashedOut:
            return "Cash out"
        case .interest:
            return "Vault interest"
        case .adjusted:
            return "Manual adjustment"
        }
    }
}
