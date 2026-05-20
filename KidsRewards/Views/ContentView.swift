import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: RewardStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @State private var isParentUnlocked = false
    @State private var isChildMode = false
    @State private var biometricsAvailable = false
    @State private var pinEntry = ""
    @State private var pinError = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            KidCoinTheme.background.ignoresSafeArea()

            if isChildMode {
                ChildModeView(onExit: {
                    isChildMode = false
                    isParentUnlocked = false
                })
            } else {
                Group {
                    switch router.selectedTab {
                    case .kids:
                        DashboardView()
                    case .work:
                        TasksView()
                    case .settings:
                        SettingsView()
                    }
                }
                .kidCoinMainTabScreen()

                KidCoinTabBar(selectedTab: $router.selectedTab)
            }
        }
        .overlay {
            if store.hasParentPIN && !isParentUnlocked && !isChildMode {
                ParentPINGate(
                    pinEntry: $pinEntry,
                    errorMessage: pinError,
                    isLockedOut: store.isParentPINLockedOut,
                    lockoutRemainingSeconds: store.parentPINLockoutRemainingSeconds(),
                    onUnlock: {
                        let enteredPIN = pinEntry
                        Task {
                            if store.isParentPINLockedOut {
                                pinError = parentPINLockoutMessage()
                                return
                            }
                            if await store.verifyParentPIN(enteredPIN) {
                                pinEntry = ""
                                pinError = ""
                                isParentUnlocked = true
                            } else if store.isParentPINLockedOut {
                                pinEntry = ""
                                pinError = parentPINLockoutMessage()
                            } else {
                                pinError = "Incorrect PIN"
                            }
                        }
                    },
                    onEnterChildMode: {
                        pinEntry = ""
                        pinError = ""
                        isChildMode = true
                    },
                    onBiometricUnlock: {
                        ParentBiometricUnlock.unlock(reason: AppBranding.biometricUnlockReason) { success in
                            if success {
                                pinEntry = ""
                                pinError = ""
                                isParentUnlocked = true
                            } else {
                                pinError = "Biometric unlock failed"
                            }
                        }
                    },
                    biometricsAvailable: biometricsAvailable
                )
                .transition(.opacity)
            }
        }
        .onAppear {
            biometricsAvailable = ParentBiometricUnlock.isAvailable
            isParentUnlocked = !store.hasParentPIN
        }
        .animation(.easeOut(duration: 0.18), value: isParentUnlocked)
        .animation(.easeOut(duration: 0.18), value: isChildMode)
        .onChange(of: router.selectedTab) { _, _ in
            KidCoinKeyboard.dismiss()
        }
        .onChange(of: router.requestChildMode) { _, requested in
            guard requested else { return }
            isChildMode = true
            router.requestChildMode = false
        }
        .onChange(of: store.hasParentPIN) { _, hasPIN in
            isParentUnlocked = !hasPIN
            biometricsAvailable = ParentBiometricUnlock.isAvailable
            pinEntry = ""
            pinError = ""
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active, store.hasParentPIN, !isChildMode else { return }
            isParentUnlocked = false
            pinEntry = ""
            pinError = ""
        }
        .dismissKeyboardOnTapOutside()
    }

    private func parentPINLockoutMessage() -> String {
        let seconds = store.parentPINLockoutRemainingSeconds()
        return seconds > 0
            ? "Too many attempts. Try again in \(seconds)s."
            : "Too many attempts. Try again shortly."
    }
}

private struct ParentPINGate: View {
    @Binding var pinEntry: String
    let errorMessage: String
    let isLockedOut: Bool
    let lockoutRemainingSeconds: Int
    let onUnlock: () -> Void
    let onEnterChildMode: () -> Void
    let onBiometricUnlock: () -> Void
    let biometricsAvailable: Bool

    var body: some View {
        ZStack {
            KidCoinTheme.background
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    KidCoinKeyboard.dismiss()
                }

            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(KidCoinTheme.primary)

                Text("Parent PIN")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))

                Text("Enter the parent PIN to manage rewards, money actions, and approvals.")
                    .font(.subheadline)
                    .foregroundStyle(KidCoinTheme.mutedText)
                    .lineSpacing(2)

                SecureField("PIN", text: TextFieldFilters.digitsOnly($pinEntry, limit: 12))
                    .kidCoinNumericPIN()
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(KidCoinTheme.muted)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KidCoinTheme.destructive)
                }

                PillButton(
                    title: "Unlock",
                    systemImage: "lock.open.fill",
                    tone: .primary,
                    disabled: pinEntry.isEmpty || isLockedOut
                ) {
                    onUnlock()
                }

                if biometricsAvailable {
                    PillButton(
                        title: "Use Face ID / Touch ID",
                        systemImage: "faceid",
                        tone: .subtle
                    ) {
                        onBiometricUnlock()
                    }
                }

                PillButton(
                    title: "Child Mode",
                    systemImage: "person.crop.circle",
                    tone: .subtle
                ) {
                    onEnterChildMode()
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .tileCard(cornerRadius: 30)
            .padding(.horizontal, 24)
        }
    }
}

private struct ChildModeView: View {
    @EnvironmentObject private var store: RewardStore
    let onExit: () -> Void

    @State private var selectedKidID: UUID?

    private var selectedKid: Kid? {
        if let selectedKidID,
           let kid = store.state.kids.first(where: { $0.id == selectedKidID }) {
            return kid
        }
        return store.state.kids.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    PageHeader(eyebrow: "Child mode", title: AppBranding.childAppName)
                    Spacer()
                    Button("Parent") {
                        onExit()
                    }
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(KidCoinTheme.muted)
                    .clipShape(Capsule())
                }

                if store.state.kids.isEmpty {
                    EmptyStatePanel(
                        systemImage: "person.2",
                        title: "No kids yet",
                        message: "Ask a parent to add a profile."
                    )
                } else if let selectedKid {
                    if store.state.kids.count > 1 {
                        Picker("Profile", selection: Binding(
                            get: { selectedKid.id },
                            set: { selectedKidID = $0 }
                        )) {
                            ForEach(store.state.kids) { kid in
                                Text(kid.name).tag(kid.id)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Choose profile")
                    }

                    ChildKidCard(kid: selectedKid)
                }

                if !store.state.kids.isEmpty && !store.state.settings.approvalFlowEnabled {
                    Text("Ask a parent to turn on approval flow in Settings before submitting chores or money requests.")
                        .font(.caption)
                        .foregroundStyle(KidCoinTheme.mutedText)
                        .lineSpacing(2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 42)
        }
        .kidCoinScroll()
        .kidCoinBackground()
        .onAppear {
            if selectedKidID == nil {
                selectedKidID = store.state.kids.first?.id
            }
        }
        .onChange(of: store.state.kids.map(\.id)) { _, kidIDs in
            guard let selectedKidID, kidIDs.contains(selectedKidID) else {
                self.selectedKidID = kidIDs.first
                return
            }
        }
    }
}

private struct ChildKidCard: View {
    @EnvironmentObject private var store: RewardStore
    let kid: Kid

    @State private var depositPoints = 1
    @State private var cashOutPoints = 1
    @State private var isHistoryExpanded = false

    private var approvalFlowEnabled: Bool {
        store.state.settings.approvalFlowEnabled
    }

    private var interestPoints: Int {
        store.interestPoints(for: kid)
    }

    private var transactions: [RewardTransaction] {
        store.transactions(for: kid)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection
            savingsGoalSection
            choreSection
            vaultDepositSection
            moneyActionsSection
            historySection
        }
        .padding(18)
        .tileCard(cornerRadius: 24)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kid.name)
                .font(.title3.weight(.bold))
            Text("\(kid.availablePoints) available · \(kid.vaultPoints) vault")
                .font(.caption)
                .foregroundStyle(KidCoinTheme.mutedText)
            Text("Cash value: \(Formatters.currency(store.currencyValue(for: kid.availablePoints), code: store.state.settings.currencyCode))")
                .font(.caption2)
                .foregroundStyle(KidCoinTheme.mutedText)
        }
    }

    @ViewBuilder
    private var savingsGoalSection: some View {
        if let goal = kid.savingsGoal {
            VStack(alignment: .leading, spacing: 6) {
                Text(goal.title)
                    .font(.caption.weight(.bold))
                ProgressView(
                    value: Double(kid.savingsGoalProgress(toward: goal)),
                    total: Double(goal.targetPoints)
                )
                .tint(KidCoinTheme.mintText)
            }
        }
    }

    @ViewBuilder
    private var choreSection: some View {
        let chores = store.tasks(for: kid)
        if !chores.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Award work")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KidCoinTheme.mutedText)
                Text("Tap a chore when you finish it. A parent approves before points are added.")
                    .font(.caption2)
                    .foregroundStyle(KidCoinTheme.mutedText)
                ForEach(chores) { task in
                    choreRow(for: task)
                }
            }
        }
    }

    @ViewBuilder
    private var vaultDepositSection: some View {
        if approvalFlowEnabled {
            VStack(alignment: .leading, spacing: 8) {
                Text("Save to vault")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KidCoinTheme.mutedText)
                HStack {
                    Text("Deposit")
                        .font(.caption)
                    Spacer()
                    CounterControl(
                        value: $depositPoints,
                        range: 1...max(kid.availablePoints, 1)
                    )
                }
                Button {
                    store.requestDeposit(points: depositPoints, for: kid)
                    depositPoints = 1
                } label: {
                    Text(depositPending ? "Deposit pending" : "Request vault deposit")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(depositPending || kid.availablePoints == 0 ? KidCoinTheme.muted : KidCoinTheme.mint.opacity(0.35))
                        .foregroundStyle(depositPending || kid.availablePoints == 0 ? KidCoinTheme.mutedText : KidCoinTheme.mintText)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(depositPending || kid.availablePoints == 0)
            }
        }
    }

    @ViewBuilder
    private var moneyActionsSection: some View {
        if approvalFlowEnabled {
            VStack(alignment: .leading, spacing: 8) {
                Text("Money actions")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KidCoinTheme.mutedText)
                Text("Cash out is a ledger entry. A parent pays you the shown amount separately.")
                    .font(.caption2)
                    .foregroundStyle(KidCoinTheme.mutedText)
                HStack {
                    Text("Cash out")
                        .font(.caption)
                    Spacer()
                    CounterControl(
                        value: $cashOutPoints,
                        range: 1...max(kid.availablePoints, 1)
                    )
                }
                Button {
                    store.requestCashOut(points: cashOutPoints, for: kid)
                    cashOutPoints = 1
                } label: {
                    Text(cashOutPending ? "Cash out pending" : cashOutRequestButtonTitle)
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(cashOutDisabled ? KidCoinTheme.muted : KidCoinTheme.primary)
                        .foregroundStyle(cashOutDisabled ? KidCoinTheme.mutedText : .white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(cashOutDisabled)

                Button {
                    store.requestInterest(for: kid)
                } label: {
                    Text(interestPending ? "Interest pending" : "Request interest")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(interestDisabled ? KidCoinTheme.muted : KidCoinTheme.muted.opacity(0.65))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(interestDisabled)
            }
        }
    }

    private var cashOutRequestButtonTitle: String {
        let amount = min(cashOutPoints, kid.availablePoints)
        let value = Formatters.currency(
            store.currencyValue(for: amount),
            code: store.state.settings.currencyCode
        )
        return "Request cash out \(value)"
    }

    private var historySection: some View {
        DisclosureGroup(isExpanded: $isHistoryExpanded) {
            if transactions.isEmpty {
                Text("No activity yet.")
                    .font(.caption)
                    .foregroundStyle(KidCoinTheme.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(transactions) { transaction in
                        RewardTransactionRow(
                            transaction: transaction,
                            currencyCode: store.state.settings.currencyCode,
                            variant: .child
                        )
                    }
                }
                .padding(.top, 4)
            }
        } label: {
            Text("History (\(transactions.count))")
                .font(.caption.weight(.bold))
                .foregroundStyle(KidCoinTheme.foreground)
        }
        .tint(KidCoinTheme.primary)
    }

    private var depositPending: Bool {
        store.pendingApprovalRequest(kind: .vaultDeposit, kidID: kid.id) != nil
    }

    private var cashOutPending: Bool {
        store.pendingApprovalRequest(kind: .cashOut, kidID: kid.id) != nil
    }

    private var interestPending: Bool {
        store.pendingApprovalRequest(kind: .interest, kidID: kid.id) != nil
    }

    private var cashOutDisabled: Bool {
        !approvalFlowEnabled || kid.availablePoints == 0 || cashOutPending
    }

    private var interestDisabled: Bool {
        !approvalFlowEnabled || interestPoints == 0 || interestPending
    }

    private func choreRow(for task: RewardTask) -> some View {
        let isAvailable = store.isTaskAvailable(task, for: kid)
        let isPending = store.pendingApprovalRequest(
            kind: .choreCompleted,
            kidID: kid.id,
            taskID: task.id
        ) != nil

        return Button {
            if approvalFlowEnabled, !isPending {
                store.requestChoreCompletion(task: task, for: kid)
            }
        } label: {
            HStack {
                Text(task.title)
                    .font(.caption.weight(.semibold))
                Spacer()
                if isPending {
                    Text("Pending")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(KidCoinTheme.mintText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(KidCoinTheme.mint.opacity(0.24))
                        .clipShape(Capsule())
                } else {
                    Text("+\(task.points)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KidCoinTheme.primary)
                }
            }
        }
        .disabled(!approvalFlowEnabled || !isAvailable || isPending)
        .buttonStyle(.plain)
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
