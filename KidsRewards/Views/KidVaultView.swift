import SwiftUI

struct KidVaultRoute: Hashable {
    let kidID: UUID
}

struct KidVaultView: View {
    @EnvironmentObject private var store: RewardStore
    let kidID: UUID

    @State private var depositPoints = 1
    @State private var withdrawPoints = 1
    @State private var goalTitle = ""
    @State private var goalTargetPoints = 25
    @State private var showingInterestConfirmation = false
    @State private var showingWithdrawConfirmation = false

    private var kid: Kid? {
        store.kid(withID: kidID)
    }

    var body: some View {
        Group {
            if let kid {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        vaultSummary(for: kid)
                        savingsGoalSection(for: kid)
                        vaultActionsSection(for: kid)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                }
                .kidCoinScroll()
                .kidCoinBackground()
                .navigationTitle("Vault")
                .navigationBarTitleDisplayMode(.inline)
                .tint(KidCoinTheme.primary)
                .onAppear {
                    syncGoalFields(from: kid)
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

            MetricTile(title: "Vault", value: kid.vaultPoints, systemImage: "lock.fill", tone: .mint)

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
                        title: "Apply \(Formatters.percent(store.state.settings.vaultInterestRate)) Interest",
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

    private func syncGoalFields(from kid: Kid) {
        if let goal = kid.savingsGoal {
            goalTitle = goal.title
            goalTargetPoints = goal.targetPoints
        }
    }

    private var interestDialogTitle: String {
        store.state.settings.approvalFlowEnabled ? "Request Interest?" : "Apply Vault Interest?"
    }

    private var interestConfirmTitle: String {
        store.state.settings.approvalFlowEnabled ? "Request Interest" : "Apply Interest"
    }

    private func interestDialogMessage(for kid: Kid) -> String {
        let points = store.interestPoints(for: kid)
        if store.state.settings.approvalFlowEnabled {
            return "This creates a pending parent approval for \(points) vault interest points."
        }
        return "This adds \(points) points to \(kid.name)'s vault."
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
