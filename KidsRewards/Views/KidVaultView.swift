import SwiftUI

struct KidVaultRoute: Hashable {
    let kidID: UUID
}

struct KidVaultView: View {
    @EnvironmentObject private var store: RewardStore
    let kidID: UUID
    var embeddedInHousehold = false

    @State private var depositPoints = 1
    @State private var withdrawPoints = 1
    @State private var goalDepositPoints = 1
    @State private var goalWithdrawPoints = 1
    @State private var goalCashOutPoints = 1
    @State private var goalTitle = ""
    @State private var goalTargetPoints = 25
    @State private var interestRateText = ""
    @State private var interestRecurrence: RewardTask.Recurrence = .none
    @State private var showingInterestConfirmation = false
    @State private var showingWithdrawConfirmation = false
    @State private var showingGoalCashOutConfirmation = false

    private var kid: Kid? {
        store.kid(withID: kidID)
    }

    var body: some View {
        Group {
            if let kid {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        vaultSummary(for: kid)
                        vaultSettingsSection()
                        autoSaveSection(for: kid)
                        vaultActionsSection(for: kid)
                        goalSection(for: kid)
                        savingsGoalSection(for: kid)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                }
                .kidCoinScroll()
                .kidCoinBackground()
                .navigationTitle(embeddedInHousehold ? "" : "Vault")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(embeddedInHousehold ? .hidden : .automatic, for: .navigationBar)
                .tint(KidCoinTheme.primary)
                .onAppear {
                    syncGoalFields(from: kid)
                    loadVaultSettings()
                }
                .onChange(of: kid.savingsGoal) { _, _ in
                    syncGoalFields(from: kid)
                }
                .confirmationDialog(
                    interestDialogTitle,
                    isPresented: $showingInterestConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(interestConfirmTitle, role: nil) {
                        applyInterest(for: kid)
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text(interestDialogMessage(for: kid))
                }
                .confirmationDialog(
                    "Withdraw from Vault?",
                    isPresented: $showingWithdrawConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Withdraw \(withdrawPoints) \(withdrawPoints == 1 ? "Point" : "Points")") {
                        withAnimation(KidCoinMotion.list) {
                            store.withdraw(points: withdrawPoints, for: kid)
                        }
                        withdrawPoints = 1
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text(withdrawDialogMessage(for: kid))
                }
                .confirmationDialog(
                    "Cash Out from Goal?",
                    isPresented: $showingGoalCashOutConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Cash Out \(goalCashOutPoints) \(goalCashOutPoints == 1 ? "Point" : "Points")", role: .destructive) {
                        withAnimation(KidCoinMotion.list) {
                            store.cashOutFromGoal(points: goalCashOutPoints, for: kid)
                        }
                        goalCashOutPoints = 1
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text(goalCashOutDialogMessage(for: kid))
                }
            } else {
                ContentUnavailableView("Kid Not Found", systemImage: "person.crop.circle.badge.questionmark")
                    .kidCoinBackground()
            }
        }
    }

    private func vaultSummary(for kid: Kid) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kid.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(KidCoinTheme.mutedText)
                .textCase(.uppercase)
                .tracking(1.2)

            HStack(spacing: 12) {
                MetricTile(title: "Vault", value: kid.vaultPoints, systemImage: "lock.fill", tone: .mint)
                if kid.goalPoints > 0 || kid.savingsGoal != nil {
                    MetricTile(title: "Goal", value: kid.goalPoints, systemImage: "target", tone: .coral)
                }
            }

            Text("Vault value: \(Formatters.currency(store.currencyValue(for: kid.vaultPoints), code: store.state.settings.currencyCode))")
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
                            Text("\(store.savingsGoalProgress(for: kid)) of \(goal.targetPoints) total points")
                                .font(.caption)
                                .foregroundStyle(KidCoinTheme.mutedText)
                        }
                        Spacer()
                        Button {
                            withAnimation(KidCoinMotion.list) {
                                store.clearSavingsGoal(for: kid)
                                goalTitle = ""
                                goalTargetPoints = 25
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(KidCoinTheme.destructive)
                                .frame(width: 32, height: 32)
                                .background(KidCoinTheme.destructive.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(KidCoinPressButtonStyle(scale: 0.94))
                        .accessibilityLabel("Clear savings goal")
                    }

                    ProgressView(
                        value: Double(store.savingsGoalProgress(for: kid)),
                        total: Double(goal.targetPoints)
                    )
                        .tint(KidCoinTheme.mintText)
                        .animation(KidCoinMotion.gentle, value: store.savingsGoalProgress(for: kid))
                        .accessibilityLabel("Savings goal progress")
                        .accessibilityValue("\(store.savingsGoalProgress(for: kid)) of \(goal.targetPoints) points")
                }

                TextField("Goal name", text: $goalTitle)
                    .kidCoinNameEntry()
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
                    withAnimation(KidCoinMotion.list) {
                        store.updateSavingsGoal(for: kid, title: goalTitle, targetPoints: goalTargetPoints)
                    }
                    goalTitle = ""
                    goalTargetPoints = 25
                }
            }
            .padding(18)
            .tileCard(cornerRadius: 26)
        }
    }

    private func autoSaveSection(for kid: Kid) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Auto-Save")
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Vault — % of each earn")
                        .font(.subheadline.weight(.semibold))
                    Text("Moves this share of every earn or allowance directly to vault.")
                        .font(.caption)
                        .foregroundStyle(KidCoinTheme.mutedText)
                    HStack(spacing: 8) {
                        ForEach([0, 10, 25, 50], id: \.self) { pct in
                            Button {
                                store.setAutoVaultPercent(pct, for: kid)
                            } label: {
                                Text(pct == 0 ? "Off" : "\(pct)%")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(kid.autoVaultPercent == pct
                                                ? KidCoinTheme.mint.opacity(0.35)
                                                : KidCoinTheme.muted)
                                    .foregroundStyle(kid.autoVaultPercent == pct
                                                     ? KidCoinTheme.mintText
                                                     : KidCoinTheme.mutedText)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(KidCoinPressButtonStyle(scale: 0.96))
                        }
                    }
                }

                Divider().overlay(KidCoinTheme.border)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Goal — % of each earn")
                        .font(.subheadline.weight(.semibold))
                    Text("Moves this share of every earn or allowance directly to goal.")
                        .font(.caption)
                        .foregroundStyle(KidCoinTheme.mutedText)
                    HStack(spacing: 8) {
                        ForEach([0, 10, 25, 50], id: \.self) { pct in
                            Button {
                                store.setAutoGoalPercent(pct, for: kid)
                            } label: {
                                Text(pct == 0 ? "Off" : "\(pct)%")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(kid.autoGoalPercent == pct
                                                ? KidCoinTheme.primary.opacity(0.18)
                                                : KidCoinTheme.muted)
                                    .foregroundStyle(kid.autoGoalPercent == pct
                                                     ? KidCoinTheme.primary
                                                     : KidCoinTheme.mutedText)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(KidCoinPressButtonStyle(scale: 0.96))
                        }
                    }
                }

                if kid.autoVaultPercent + kid.autoGoalPercent > 100 {
                    Text("Combined auto-save exceeds 100%. Goal will receive fewer points than set.")
                        .font(.caption)
                        .foregroundStyle(KidCoinTheme.destructive)
                }
            }
            .padding(18)
            .tileCard(cornerRadius: 26)
        }
    }

    private func vaultActionsSection(for kid: Kid) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Vault")
            VStack(spacing: 16) {
                HStack {
                    Text("Deposit from available")
                        .font(.subheadline)
                    Spacer()
                    CounterControl(value: $depositPoints, range: 1...max(kid.availablePoints, 1))
                }
                PillButton(
                    title: vaultDepositButtonTitle,
                    systemImage: "arrow.down.to.line",
                    tone: .mint,
                    disabled: kid.availablePoints == 0 || vaultDepositPending
                ) {
                    withAnimation(KidCoinMotion.list) {
                        _ = store.deposit(points: depositPoints, for: kid)
                    }
                    depositPoints = 1
                }
                HStack {
                    Text("Withdraw to available")
                        .font(.subheadline)
                    Spacer()
                    CounterControl(value: $withdrawPoints, range: 1...max(kid.vaultPoints, 1))
                }
                PillButton(
                    title: "Withdraw \(withdrawPoints) \(withdrawPoints == 1 ? "point" : "points")",
                    systemImage: "arrow.up.to.line",
                    tone: .primary,
                    disabled: kid.vaultPoints == 0
                ) {
                    showingWithdrawConfirmation = true
                }

                if store.state.settings.interestRecurrence != .none {
                    Text(scheduledInterestStatusText)
                        .font(.caption)
                        .foregroundStyle(KidCoinTheme.mutedText)
                } else {
                    PillButton(
                        title: "Apply \(Formatters.percent(store.state.settings.vaultInterestRate)) Vault Interest",
                        systemImage: "percent",
                        tone: .subtle,
                        disabled: store.interestPoints(for: kid) == 0
                    ) {
                        showingInterestConfirmation = true
                    }
                }
            }
            .padding(18)
            .tileCard(cornerRadius: 26)
        }
    }

    private func vaultSettingsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Interest Settings")
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Interest rate")
                            .font(.subheadline.weight(.semibold))
                        Text("Decimal — 0.05 means 5%. Applies to vault and goal.")
                            .font(.caption)
                            .foregroundStyle(KidCoinTheme.mutedText)
                    }
                    Spacer()
                    TextField("0.05", text: $interestRateText)
                        .kidCoinDecimalEntry()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 86)
                        .fieldPill()
                }

                SegmentedPickerRow(
                    selection: $interestRecurrence,
                    items: RewardTask.Recurrence.allCases,
                    label: \.label
                )
                .onChange(of: interestRecurrence) { _, newValue in
                    store.setInterestRecurrence(newValue)
                }

                Text(interestScheduleText)
                    .font(.caption)
                    .foregroundStyle(KidCoinTheme.mutedText)
                    .lineSpacing(2)

                PillButton(title: "Save Interest Settings", systemImage: "checkmark", tone: .subtle) {
                    saveVaultSettings()
                }
            }
            .padding(18)
            .tileCard(cornerRadius: 26)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: interestRecurrence)
    }

    private func goalSection(for kid: Kid) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Goal Balance")
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Goal")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(KidCoinTheme.mutedText)
                        Text("Can be cashed out at any time")
                            .font(.caption)
                            .foregroundStyle(KidCoinTheme.mutedText)
                    }
                    Spacer()
                    Text("\(kid.goalPoints) pts")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(KidCoinTheme.primary)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(kid.goalPoints)))
                        .animation(KidCoinMotion.gentle, value: kid.goalPoints)
                }

                HStack {
                    Text("Deposit from available")
                        .font(.subheadline)
                    Spacer()
                    CounterControl(value: $goalDepositPoints, range: 1...max(kid.availablePoints, 1))
                }
                PillButton(
                    title: goalDepositPending(for: kid) ? "Deposit pending approval" : "Deposit \(goalDepositPoints) \(goalDepositPoints == 1 ? "point" : "points")",
                    systemImage: "arrow.down.to.line",
                    tone: .primary,
                    disabled: kid.availablePoints == 0 || goalDepositPending(for: kid)
                ) {
                    withAnimation(KidCoinMotion.list) {
                        store.depositToGoal(points: goalDepositPoints, for: kid)
                    }
                    goalDepositPoints = 1
                }

                Divider().overlay(KidCoinTheme.border)

                HStack {
                    Text("Cash out from goal")
                        .font(.subheadline)
                    Spacer()
                    CounterControl(value: $goalCashOutPoints, range: 1...max(kid.goalPoints, 1))
                }
                PillButton(
                    title: goalCashOutPending(for: kid) ? "Cash out pending approval" : "Cash out \(goalCashOutPoints) \(goalCashOutPoints == 1 ? "point" : "points")",
                    systemImage: "banknote",
                    tone: .subtle,
                    disabled: kid.goalPoints == 0 || goalCashOutPending(for: kid)
                ) {
                    showingGoalCashOutConfirmation = true
                }

                HStack {
                    Text("Withdraw to available")
                        .font(.subheadline)
                    Spacer()
                    CounterControl(value: $goalWithdrawPoints, range: 1...max(kid.goalPoints, 1))
                }
                PillButton(
                    title: "Withdraw \(goalWithdrawPoints) \(goalWithdrawPoints == 1 ? "point" : "points")",
                    systemImage: "arrow.up.to.line",
                    tone: .subtle,
                    disabled: kid.goalPoints == 0
                ) {
                    withAnimation(KidCoinMotion.list) {
                        store.withdrawFromGoal(points: goalWithdrawPoints, for: kid)
                    }
                    goalWithdrawPoints = 1
                }

                if store.state.settings.interestRecurrence == .none {
                    let goalInterestAmt = store.goalInterestPoints(for: kid)
                    PillButton(
                        title: "Apply \(Formatters.percent(store.state.settings.vaultInterestRate)) Goal Interest",
                        systemImage: "percent",
                        tone: .subtle,
                        disabled: goalInterestAmt == 0
                    ) {
                        withAnimation(KidCoinMotion.list) {
                            _ = store.applyInterest(to: kid)
                        }
                    }
                }
            }
            .padding(18)
            .tileCard(cornerRadius: 26)
        }
    }

    private func syncGoalFields(from kid: Kid) {
        if let goal = kid.savingsGoal {
            goalTitle = goal.title
            goalTargetPoints = goal.targetPoints
        }
    }

    private func loadVaultSettings() {
        interestRateText = Formatters.decimalInput(store.state.settings.vaultInterestRate)
        interestRecurrence = store.state.settings.interestRecurrence
    }

    private func saveVaultSettings() {
        if let rate = Formatters.parseDecimal(interestRateText) {
            store.setVaultInterestRate(rate)
        }
    }

    private var interestScheduleText: String {
        switch interestRecurrence {
        case .none:
            return "Interest is applied manually using the button below."
        case .daily, .weekly, .biweekly, .monthly:
            let cadence = interestRecurrence.label.lowercased()
            if let last = store.state.settings.lastInterestAppliedAt {
                return "Interest runs \(cadence). Last applied \(last.formatted(date: .abbreviated, time: .omitted))."
            }
            return "Interest runs \(cadence) the next time the app opens."
        }
    }

    private func goalDepositPending(for kid: Kid) -> Bool {
        store.pendingApprovalRequest(kind: .goalDeposit, kidID: kid.id) != nil
    }

    private func goalCashOutPending(for kid: Kid) -> Bool {
        store.pendingApprovalRequest(kind: .goalCashOut, kidID: kid.id) != nil
    }

    private func goalCashOutDialogMessage(for kid: Kid) -> String {
        let amount = min(goalCashOutPoints, kid.goalPoints)
        let value = Formatters.currency(store.currencyValue(for: amount), code: store.state.settings.currencyCode)
        return "This cashes out \(amount) goal points (\(value)) for \(kid.name). Goal points are removed permanently."
    }

    private var interestDialogTitle: String {
        store.state.settings.approvalFlowEnabled ? "Request Interest?" : "Apply Interest?"
    }

    private var interestConfirmTitle: String {
        store.state.settings.approvalFlowEnabled ? "Request Interest" : "Apply Interest"
    }

    private func interestDialogMessage(for kid: Kid) -> String {
        let vaultPts = store.interestPoints(for: kid)
        let goalPts = store.goalInterestPoints(for: kid)
        var parts: [String] = []
        if vaultPts > 0 { parts.append("\(vaultPts) to vault") }
        if goalPts > 0 { parts.append("\(goalPts) to goal") }
        let summary = parts.isEmpty ? "0 points" : parts.joined(separator: ", ")
        if store.state.settings.approvalFlowEnabled {
            return "This creates a pending parent approval for interest: \(summary)."
        }
        return "This adds interest to \(kid.name): \(summary)."
    }

    private func applyInterest(for kid: Kid) {
        withAnimation(KidCoinMotion.list) {
            if store.state.settings.approvalFlowEnabled {
                store.requestInterest(for: kid)
            } else {
                store.applyInterest(to: kid)
            }
        }
    }

    private func withdrawDialogMessage(for kid: Kid) -> String {
        let amount = min(withdrawPoints, kid.vaultPoints)
        return "This moves \(amount) points from \(kid.name)'s vault back to available."
    }

    private var vaultDepositPending: Bool {
        store.pendingApprovalRequest(kind: .vaultDeposit, kidID: kidID) != nil
    }

    private var vaultDepositButtonTitle: String {
        if vaultDepositPending {
            return "Deposit pending approval"
        }
        return "Deposit \(depositPoints) \(depositPoints == 1 ? "point" : "points")"
    }

    private var scheduledInterestStatusText: String {
        let cadence = store.state.settings.interestRecurrence.label.lowercased()
        if let lastApplied = store.state.settings.lastInterestAppliedAt {
            return "Interest runs \(cadence). Last applied \(lastApplied.formatted(date: .abbreviated, time: .omitted)) when the app opened."
        }
        return "Interest runs \(cadence) the next time you open the app."
    }
}
