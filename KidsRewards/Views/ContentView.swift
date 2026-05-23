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
    @State private var parentPINLockoutRefresh = Date()

    var body: some View {
        ZStack(alignment: .bottom) {
            KidCoinTheme.background.ignoresSafeArea()

            if isChildMode {
                ChildModeView(onExit: {
                    withAnimation(KidCoinMotion.modal) {
                        isChildMode = false
                        isParentUnlocked = false
                    }
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
                let isLockedOut = store.parentPINLockoutUntil.map { $0 > parentPINLockoutRefresh } ?? false
                ParentPINGate(
                    pinEntry: $pinEntry,
                    errorMessage: pinError,
                    isLockedOut: isLockedOut,
                    lockoutRemainingSeconds: store.parentPINLockoutRemainingSeconds(now: parentPINLockoutRefresh),
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
                                withAnimation(KidCoinMotion.modal) {
                                    isParentUnlocked = true
                                }
                            } else if store.isParentPINLockedOut {
                                pinEntry = ""
                                parentPINLockoutRefresh = Date()
                                pinError = parentPINLockoutMessage()
                            } else {
                                pinError = "Incorrect PIN"
                            }
                        }
                    },
                    onEnterChildMode: {
                        pinEntry = ""
                        pinError = ""
                        withAnimation(KidCoinMotion.modal) {
                            isChildMode = true
                        }
                    },
                    onBiometricUnlock: {
                        ParentBiometricUnlock.unlock(reason: AppBranding.biometricUnlockReason) { success in
                            if success {
                                pinEntry = ""
                                pinError = ""
                                withAnimation(KidCoinMotion.modal) {
                                    isParentUnlocked = true
                                }
                            } else {
                                pinError = "Biometric unlock failed"
                            }
                        }
                    },
                    biometricsAvailable: biometricsAvailable
                )
                .transition(.kidCoinModal)
            }
        }
        .onAppear {
            biometricsAvailable = ParentBiometricUnlock.isAvailable
            isParentUnlocked = !store.hasParentPIN
        }
        .animation(KidCoinMotion.modal, value: isParentUnlocked)
        .animation(KidCoinMotion.modal, value: isChildMode)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
            guard store.parentPINLockoutUntil != nil else { return }
            parentPINLockoutRefresh = now
            if store.parentPINLockoutRemainingSeconds(now: now) == 0,
               pinError.hasPrefix("Too many attempts") {
                pinError = ""
            }
        }
        .onChange(of: router.selectedTab) { _, _ in
            KidCoinKeyboard.dismiss()
        }
        .onChange(of: router.requestChildMode) { _, requested in
            guard requested else { return }
            withAnimation(KidCoinMotion.modal) {
                isChildMode = true
            }
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
    @State private var isHistoryExpanded = false
    @State private var depositPoints = 1
    @State private var withdrawVaultPoints = 1
    @State private var goalDepositPoints = 1
    @State private var cashOutPoints = 1
    @State private var goalCashOutPoints = 1
    @State private var kidGoalTitle = ""
    @State private var kidGoalTargetPoints = 25

    private var selectedKid: Kid? {
        if let selectedKidID,
           let kid = store.state.kids.first(where: { $0.id == selectedKidID }) {
            return kid
        }
        return store.state.kids.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                childHeader

                if store.state.kids.isEmpty {
                    EmptyStatePanel(
                        systemImage: "person.2",
                        title: "No kids yet",
                        message: "Ask a parent to add a profile."
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                } else if let kid = selectedKid {
                    if store.state.kids.count > 1 {
                        kidSwitcher
                            .padding(.top, 12)
                    }

                    profileCard(for: kid)
                        .padding(.top, 10)

                    choreSection(for: kid)

                    kidVaultSection(for: kid)

                    kidGoalSection(for: kid)

                    if store.state.settings.approvalFlowEnabled {
                        moneySection(for: kid)
                    } else {
                        Text("Ask a parent to turn on approval flow in Settings to submit chore and cash out requests.")
                            .font(.caption)
                            .foregroundStyle(KidCoinTheme.mutedText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                            .padding(.top, 20)
                    }

                    historySection(for: kid)
                }
            }
            .padding(.bottom, 48)
        }
        .kidCoinScroll()
        .kidCoinBackground()
        .onAppear {
            if selectedKidID == nil {
                selectedKidID = store.state.kids.first?.id
            }
            syncKidGoalFields(for: selectedKid)
        }
        .onChange(of: store.state.kids.map(\.id)) { _, kidIDs in
            guard let selectedKidID, kidIDs.contains(selectedKidID) else {
                self.selectedKidID = kidIDs.first
                return
            }
        }
        .onChange(of: selectedKidID) { _, _ in
            depositPoints = 1
            withdrawVaultPoints = 1
            goalDepositPoints = 1
            cashOutPoints = 1
            goalCashOutPoints = 1
            isHistoryExpanded = false
            syncKidGoalFields(for: selectedKid)
        }
        .onChange(of: selectedKid?.savingsGoal) { _, _ in
            syncKidGoalFields(for: selectedKid)
        }
        .onChange(of: selectedKid?.vaultPoints) { _, newVault in
            let cap = max(newVault ?? 1, 1)
            if withdrawVaultPoints > cap { withdrawVaultPoints = cap }
        }
        .onChange(of: selectedKid?.availablePoints) { _, newAvail in
            let cap = max(newAvail ?? 1, 1)
            if depositPoints > cap { depositPoints = cap }
            if goalDepositPoints > cap { goalDepositPoints = cap }
        }
    }

    // MARK: - Header

    private var childHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text("CHILD MODE")
                    .font(.caption.weight(.bold))
                    .tracking(3.5)
                    .foregroundStyle(KidCoinTheme.primary)
                Text("My Rewards")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(KidCoinTheme.foreground)
            }
            Spacer()
            Button("Parent", action: onExit)
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(KidCoinTheme.mint)
                .foregroundStyle(KidCoinTheme.mintText)
                .clipShape(Capsule())
                .shadow(color: KidCoinTheme.mint.opacity(0.3), radius: 8, x: 0, y: 4)
                .buttonStyle(KidCoinPressButtonStyle(scale: 0.96))
        }
        .padding(.horizontal, 22)
        .padding(.top, 48)
        .padding(.bottom, 20)
    }

    // MARK: - Profile card

    private func profileCard(for kid: Kid) -> some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(KidCoinTheme.mint.opacity(0.28))
                .frame(width: 130, height: 130)
                .blur(radius: 44)
                .offset(x: 44, y: -44)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                kidNameView(for: kid)
                    .padding(.bottom, 4)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(kid.availablePoints)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(KidCoinTheme.primary)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(kid.availablePoints)))
                        .animation(KidCoinMotion.gentle, value: kid.availablePoints)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("available")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(KidCoinTheme.mutedText)
                        HStack(spacing: 4) {
                            Text("\(kid.vaultPoints)")
                                .monospacedDigit()
                                .contentTransition(.numericText(value: Double(kid.vaultPoints)))
                                .animation(KidCoinMotion.gentle, value: kid.vaultPoints)
                            Text("vault")
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(KidCoinTheme.mintText)
                        if kid.goalPoints > 0 || kid.savingsGoal != nil {
                            HStack(spacing: 4) {
                                Text("\(kid.goalPoints)")
                                    .monospacedDigit()
                                    .contentTransition(.numericText(value: Double(kid.goalPoints)))
                                    .animation(KidCoinMotion.gentle, value: kid.goalPoints)
                                Text(kid.savingsGoal?.title ?? "goal")
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(KidCoinTheme.primary.opacity(0.7))
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 18)

                Text(Formatters.currency(store.currencyValue(for: kid.availablePoints), code: store.state.settings.currencyCode))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(KidCoinTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(KidCoinTheme.border, lineWidth: 1)
                    }

                if let goal = kid.savingsGoal {
                    let progress = store.savingsGoalProgress(for: kid)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(goal.title): \(progress)/\(goal.targetPoints)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(KidCoinTheme.mintText)
                        ProgressView(value: Double(min(progress, goal.targetPoints)), total: Double(goal.targetPoints))
                            .tint(KidCoinTheme.mint)
                    }
                    .padding(.top, 16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(26)
        }
        .tileCard(cornerRadius: 36)
        .padding(.horizontal, 20)
        .clipped()
    }

    private var kidSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.state.kids) { k in
                    let isSelected = k.id == (selectedKidID ?? store.state.kids.first?.id)
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedKidID = k.id
                        }
                    } label: {
                        Text(k.name)
                            .font(.subheadline.weight(isSelected ? .bold : .regular))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(isSelected ? KidCoinTheme.primary : KidCoinTheme.muted)
                            .foregroundStyle(isSelected ? Color.white : KidCoinTheme.foreground)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(KidCoinPressButtonStyle(scale: 0.96))
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func kidNameView(for kid: Kid) -> some View {
        Text(kid.name)
            .font(.system(size: 22, weight: .bold, design: .rounded))
    }

    // MARK: - Chores

    private func choreSection(for kid: Kid) -> some View {
        let chores = store.tasks(for: kid)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Award work")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .padding(.horizontal, 20)

            if chores.isEmpty {
                Text("No chores yet. Ask a parent to add some in the Work tab.")
                    .font(.subheadline)
                    .foregroundStyle(KidCoinTheme.mutedText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(KidCoinTheme.border, style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                    }
                    .padding(.horizontal, 20)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(chores.enumerated()), id: \.element.id) { index, task in
                        ChildChoreButton(
                            task: task,
                            isAlt: index % 2 == 1,
                            isPending: store.pendingApprovalRequest(kind: .choreCompleted, kidID: kid.id, taskID: task.id) != nil,
                            isAvailable: store.isTaskAvailable(task, for: kid),
                            approvalEnabled: store.state.settings.approvalFlowEnabled
                        ) {
                            if store.state.settings.approvalFlowEnabled {
                                store.requestChoreCompletion(task: task, for: kid)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            Text("Tap a chore to ask Mom or Dad to check your work")
                .font(.subheadline)
                .foregroundStyle(KidCoinTheme.mutedText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
        }
        .padding(.top, 26)
    }

    // MARK: - Vault section (always visible, direct deposit)

    private func kidVaultSection(for kid: Kid) -> some View {
        let capped = kid.availablePoints > 0 ? min(depositPoints, kid.availablePoints) : 0
        let projected = kid.vaultPoints + capped

        return VStack(alignment: .leading, spacing: 14) {
            Text("Vault")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(kid.vaultPoints)")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(KidCoinTheme.mintText)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(kid.vaultPoints)))
                        .animation(KidCoinMotion.gentle, value: kid.vaultPoints)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("saved")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(KidCoinTheme.mutedText)
                        if kid.autoVaultPercent > 0 {
                            Text("Auto-saving \(kid.autoVaultPercent)% of every earn")
                                .font(.caption2)
                                .foregroundStyle(KidCoinTheme.mintText)
                        }
                    }
                    .padding(.bottom, 3)
                }

                Divider().overlay(KidCoinTheme.border)

                // Deposit
                HStack {
                    Text("Move to vault")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    CounterControl(value: $depositPoints, range: 1...max(kid.availablePoints, 1))
                }

                estimatedGainPanel(projectedVault: projected)
                    .animation(KidCoinMotion.gentle, value: projected)

                Button {
                    withAnimation(KidCoinMotion.list) {
                        store.depositDirectly(points: depositPoints, for: kid)
                    }
                    depositPoints = 1
                } label: {
                    Text(kid.availablePoints == 0
                         ? "No points to save"
                         : "Save \(depositPoints) \(depositPoints == 1 ? "point" : "points") to vault")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(kid.availablePoints == 0
                                    ? KidCoinTheme.muted
                                    : KidCoinTheme.mint.opacity(0.35))
                        .foregroundStyle(kid.availablePoints == 0
                                         ? KidCoinTheme.mutedText
                                         : KidCoinTheme.mintText)
                        .clipShape(Capsule())
                }
                .buttonStyle(KidCoinPressButtonStyle(scale: 0.97))
                .disabled(kid.availablePoints == 0)

                // Withdraw
                if kid.vaultPoints > 0 {
                    Divider().overlay(KidCoinTheme.border)

                    HStack {
                        Text("Withdraw from vault")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        CounterControl(value: $withdrawVaultPoints, range: 1...max(kid.vaultPoints, 1))
                    }

                    Button {
                        withAnimation(KidCoinMotion.list) {
                            store.withdraw(points: withdrawVaultPoints, for: kid)
                        }
                        withdrawVaultPoints = 1
                    } label: {
                        Text("Move \(withdrawVaultPoints) \(withdrawVaultPoints == 1 ? "point" : "points") to available")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(KidCoinTheme.primary.opacity(0.1))
                            .foregroundStyle(KidCoinTheme.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(KidCoinPressButtonStyle(scale: 0.97))
                }

                // Auto-save setting
                Divider().overlay(KidCoinTheme.border)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Auto-save to vault")
                        .font(.subheadline.weight(.semibold))
                    Text("Automatically move this % of every earn to vault.")
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
            }
            .padding(20)
            .tileCard(cornerRadius: 28)
            .padding(.horizontal, 20)
        }
        .padding(.top, 22)
    }

    // MARK: - Goal section (always visible, direct deposit)

    private func syncKidGoalFields(for kid: Kid?) {
        guard let kid else { return }
        if let goal = kid.savingsGoal {
            kidGoalTitle = goal.title
            kidGoalTargetPoints = goal.targetPoints
        } else {
            kidGoalTitle = ""
            kidGoalTargetPoints = 25
        }
    }

    private func kidGoalSection(for kid: Kid) -> some View {
        let goalCashOutPending = store.pendingApprovalRequest(kind: .goalCashOut, kidID: kid.id) != nil

        return VStack(alignment: .leading, spacing: 14) {
            Text("Goal")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 14) {
                // Balance + progress
                if let goal = kid.savingsGoal {
                    let progress = store.savingsGoalProgress(for: kid)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(goal.title)
                                    .font(.headline.weight(.bold))
                                Text("\(progress) of \(goal.targetPoints) pts")
                                    .font(.caption)
                                    .foregroundStyle(KidCoinTheme.mutedText)
                            }
                            Spacer()
                            Button {
                                withAnimation(KidCoinMotion.list) {
                                    store.clearSavingsGoal(for: kid)
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
                        }
                        ProgressView(value: Double(min(progress, goal.targetPoints)), total: Double(goal.targetPoints))
                            .tint(KidCoinTheme.primary)
                            .animation(KidCoinMotion.gentle, value: progress)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(kid.goalPoints)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(KidCoinTheme.primary)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(kid.goalPoints)))
                        .animation(KidCoinMotion.gentle, value: kid.goalPoints)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("saved")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(KidCoinTheme.mutedText)
                        if kid.autoGoalPercent > 0 {
                            Text("Auto-saving \(kid.autoGoalPercent)% of every earn")
                                .font(.caption2)
                                .foregroundStyle(KidCoinTheme.primary.opacity(0.7))
                        }
                    }
                    .padding(.bottom, 3)
                }

                Divider().overlay(KidCoinTheme.border)

                // Set / update goal
                VStack(alignment: .leading, spacing: 10) {
                    Text("My goal")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KidCoinTheme.mutedText)
                        .textCase(.uppercase)
                        .tracking(1)

                    TextField("Goal name (e.g. New bike)", text: $kidGoalTitle)
                        .kidCoinNameEntry()
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .background(KidCoinTheme.muted)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    HStack {
                        Text("Target points")
                            .font(.subheadline)
                            .foregroundStyle(KidCoinTheme.mutedText)
                        Spacer()
                        CounterControl(value: $kidGoalTargetPoints, range: 1...500)
                    }

                    let trimmed = kidGoalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    Button {
                        withAnimation(KidCoinMotion.list) {
                            store.updateSavingsGoal(for: kid, title: trimmed, targetPoints: kidGoalTargetPoints)
                        }
                    } label: {
                        Text(kid.savingsGoal == nil ? "Set goal" : "Update goal")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(trimmed.isEmpty ? KidCoinTheme.muted : KidCoinTheme.primary.opacity(0.15))
                            .foregroundStyle(trimmed.isEmpty ? KidCoinTheme.mutedText : KidCoinTheme.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(KidCoinPressButtonStyle(scale: 0.97))
                    .disabled(trimmed.isEmpty)
                }

                Divider().overlay(KidCoinTheme.border)

                // Deposit to goal (direct)
                HStack {
                    Text("Move to goal")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    CounterControl(value: $goalDepositPoints, range: 1...max(kid.availablePoints, 1))
                }

                Button {
                    withAnimation(KidCoinMotion.list) {
                        store.depositToGoalDirectly(points: goalDepositPoints, for: kid)
                    }
                    goalDepositPoints = 1
                } label: {
                    Text(kid.availablePoints == 0
                         ? "No points to save"
                         : "Save \(goalDepositPoints) \(goalDepositPoints == 1 ? "point" : "points") to goal")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(kid.availablePoints == 0
                                    ? KidCoinTheme.muted
                                    : KidCoinTheme.primary.opacity(0.15))
                        .foregroundStyle(kid.availablePoints == 0
                                         ? KidCoinTheme.mutedText
                                         : KidCoinTheme.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(KidCoinPressButtonStyle(scale: 0.97))
                .disabled(kid.availablePoints == 0)

                // Auto-save to goal
                Divider().overlay(KidCoinTheme.border)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Auto-save to goal")
                        .font(.subheadline.weight(.semibold))
                    Text("Automatically move this % of every earn to goal.")
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

                // Cash out from goal (approval-gated — real money)
                if kid.goalPoints > 0 && store.state.settings.approvalFlowEnabled {
                    Divider().overlay(KidCoinTheme.border)

                    HStack {
                        Text("Cash out from goal")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        CounterControl(value: $goalCashOutPoints, range: 1...max(kid.goalPoints, 1))
                    }

                    Button {
                        withAnimation(KidCoinMotion.list) {
                            store.requestGoalCashOut(points: goalCashOutPoints, for: kid)
                        }
                        goalCashOutPoints = 1
                    } label: {
                        let amt = Formatters.currency(
                            store.currencyValue(for: min(goalCashOutPoints, kid.goalPoints)),
                            code: store.state.settings.currencyCode
                        )
                        Text(goalCashOutPending ? "Cash out pending" : "Cash out \(amt) from goal")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(goalCashOutPending ? KidCoinTheme.muted : KidCoinTheme.primary.opacity(0.12))
                            .foregroundStyle(goalCashOutPending ? KidCoinTheme.mutedText : KidCoinTheme.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(KidCoinPressButtonStyle(scale: 0.97))
                    .disabled(goalCashOutPending)
                }
            }
            .padding(20)
            .tileCard(cornerRadius: 28)
            .padding(.horizontal, 20)
        }
        .padding(.top, 22)
    }

    // MARK: - Money section

    private func estimatedMonthlyInterest(vault: Int) -> Int {
        let rate = store.state.settings.vaultInterestRate
        guard rate > 0, vault > 0 else { return 0 }
        let perApp = NSDecimalNumber(decimal: Decimal(vault) * rate).rounding(accordingToBehavior: nil).intValue
        switch store.state.settings.interestRecurrence {
        case .none: return 0
        case .daily: return perApp * 30
        case .weekly: return Int(Double(perApp) * 52.0 / 12.0)
        case .biweekly: return Int(Double(perApp) * 26.0 / 12.0)
        case .monthly: return perApp
        }
    }

    @ViewBuilder
    private func estimatedGainPanel(projectedVault: Int) -> some View {
        let rate = store.state.settings.vaultInterestRate
        let monthly = estimatedMonthlyInterest(vault: projectedVault)
        let yearly = monthly * 12
        if rate > 0, projectedVault > 0 {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estimated gain")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(KidCoinTheme.mutedText)
                        .textCase(.uppercase)
                        .tracking(0.8)
                    if store.state.settings.interestRecurrence == .none {
                        Text("\(NSDecimalNumber(decimal: Decimal(projectedVault) * rate).rounding(accordingToBehavior: nil).intValue) pts per app open")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(KidCoinTheme.mintText)
                    } else if monthly > 0 {
                        HStack(spacing: 6) {
                            Text("≈\(monthly) pts/mo")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(KidCoinTheme.mintText)
                            Text("·")
                                .foregroundStyle(KidCoinTheme.mutedText)
                                .font(.caption)
                            Text("≈\(yearly) pts/yr")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(KidCoinTheme.mutedText)
                        }
                    }
                }
                Spacer(minLength: 0)
                Text(Formatters.percent(rate))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KidCoinTheme.mintText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(KidCoinTheme.mint.opacity(0.22))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(KidCoinTheme.mint.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func moneySection(for kid: Kid) -> some View {
        let cashOutPending = store.pendingApprovalRequest(kind: .cashOut, kidID: kid.id) != nil

        return VStack(alignment: .leading, spacing: 16) {
            Text("Cash out")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            VStack(alignment: .leading, spacing: 8) {
                Text("A parent pays you the cash amount separately.")
                    .font(.caption)
                    .foregroundStyle(KidCoinTheme.mutedText)

                HStack {
                    Text("From available")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    CounterControl(value: $cashOutPoints, range: 1...max(kid.availablePoints, 1))
                }
                Button {
                    withAnimation(KidCoinMotion.list) {
                        store.requestCashOut(points: cashOutPoints, for: kid)
                    }
                    cashOutPoints = 1
                } label: {
                    let amt = Formatters.currency(store.currencyValue(for: min(cashOutPoints, kid.availablePoints)), code: store.state.settings.currencyCode)
                    Text(cashOutPending ? "Cash out pending" : "Request cash out \(amt)")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(cashOutPending || kid.availablePoints == 0 ? KidCoinTheme.muted : KidCoinTheme.primary)
                        .foregroundStyle(cashOutPending || kid.availablePoints == 0 ? KidCoinTheme.mutedText : .white)
                        .clipShape(Capsule())
                }
                .buttonStyle(KidCoinPressButtonStyle(scale: 0.97))
                .disabled(cashOutPending || kid.availablePoints == 0)
            }
        }
        .padding(20)
        .tileCard(cornerRadius: 28)
        .padding(.horizontal, 20)
        .padding(.top, 22)
    }

    // MARK: - History

    private func historySection(for kid: Kid) -> some View {
        let txns = store.transactions(for: kid)
        return VStack(spacing: 12) {
            Button {
                withAnimation(KidCoinMotion.gentle) {
                    isHistoryExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("History (\(txns.count))")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(KidCoinTheme.primary)
                    Spacer()
                    Image(systemName: isHistoryExpanded ? "chevron.up" : "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KidCoinTheme.primary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 4)
            }
            .buttonStyle(KidCoinPressButtonStyle(scale: 0.98))

            if isHistoryExpanded {
                if txns.isEmpty {
                    Text("No activity yet.")
                        .font(.subheadline)
                        .foregroundStyle(KidCoinTheme.mutedText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(txns.prefix(10))) { txn in
                            RewardTransactionRow(
                                transaction: txn,
                                currencyCode: store.state.settings.currencyCode,
                                variant: .child
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .transition(.kidCoinRow)
                }
            }
        }
        .padding(.top, 26)
        .animation(KidCoinMotion.list, value: isHistoryExpanded)
        .animation(KidCoinMotion.list, value: txns)
    }
}

private struct ChildChoreButton: View {
    let task: RewardTask
    let isAlt: Bool
    let isPending: Bool
    let isAvailable: Bool
    let approvalEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        let tint: Color = isAlt ? KidCoinTheme.mint : KidCoinTheme.primary
        let fg: Color = isAlt ? KidCoinTheme.mintText : .white
        let active = approvalEnabled && isAvailable && !isPending

        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.body.weight(.bold))
                        .foregroundStyle(KidCoinTheme.foreground)
                    if isPending {
                        Text("Pending approval")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(KidCoinTheme.mintText)
                    } else if task.recurrence != .none && !isAvailable {
                        Text("Available \(task.recurrence.label.lowercased())")
                            .font(.caption2)
                            .foregroundStyle(KidCoinTheme.mutedText)
                    }
                }
                Spacer()
                Text(isPending ? "✓" : "+\(task.points)")
                    .font(.system(.headline, design: .rounded).weight(.black))
                    .monospacedDigit()
                    .frame(minWidth: 52, minHeight: 48)
                    .padding(.horizontal, 4)
                    .background(isPending ? KidCoinTheme.mint.opacity(0.3) : tint)
                    .foregroundStyle(isPending ? KidCoinTheme.mintText : fg)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(
                        color: (isPending ? KidCoinTheme.mint : tint).opacity(active ? 0.55 : 0),
                        radius: 0, x: 0, y: 5
                    )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(KidCoinTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(KidCoinTheme.border, lineWidth: 1)
            }
            .shadow(color: KidCoinTheme.border.opacity(0.85), radius: 0, x: 0, y: 4)
        }
        .buttonStyle(KidCoinPressButtonStyle(scale: 0.98))
        .opacity(active || isPending ? 1.0 : 0.45)
        .disabled(!active)
    }
}

private struct KidCoinTabBar: View {
    @Binding var selectedTab: AppTab
    @Namespace private var selectedTabBackground

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(KidCoinMotion.tab) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 38, height: 34)
                            .background {
                                if selectedTab == tab {
                                    Capsule()
                                        .fill(KidCoinTheme.primary.opacity(0.12))
                                        .matchedGeometryEffect(id: "selectedTab", in: selectedTabBackground)
                                }
                            }
                            .clipShape(Capsule())
                        Text(tab.title)
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(selectedTab == tab ? KidCoinTheme.primary : KidCoinTheme.mutedText)
                }
                .buttonStyle(KidCoinPressButtonStyle(scale: 0.96))
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
