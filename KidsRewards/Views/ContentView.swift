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
    @State private var cashOutPoints = 1

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
                    profileCard(for: kid)
                        .padding(.top, 10)

                    choreSection(for: kid)

                    if store.state.settings.approvalFlowEnabled {
                        moneySection(for: kid)
                    } else {
                        Text("Ask a parent to turn on approval flow in Settings to submit chores and money requests.")
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
        }
        .onChange(of: store.state.kids.map(\.id)) { _, kidIDs in
            guard let selectedKidID, kidIDs.contains(selectedKidID) else {
                self.selectedKidID = kidIDs.first
                return
            }
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

    @ViewBuilder
    private func kidNameView(for kid: Kid) -> some View {
        if store.state.kids.count > 1 {
            Menu {
                ForEach(store.state.kids) { k in
                    Button {
                        selectedKidID = k.id
                    } label: {
                        if k.id == kid.id {
                            Label(k.name, systemImage: "checkmark")
                        } else {
                            Text(k.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(kid.name)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(KidCoinTheme.foreground)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KidCoinTheme.mutedText)
                }
            }
        } else {
            Text(kid.name)
                .font(.system(size: 22, weight: .bold, design: .rounded))
        }
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

    // MARK: - Money section

    private func moneySection(for kid: Kid) -> some View {
        let depositPending = store.pendingApprovalRequest(kind: .vaultDeposit, kidID: kid.id) != nil
        let cashOutPending = store.pendingApprovalRequest(kind: .cashOut, kidID: kid.id) != nil
        let interestPending = store.pendingApprovalRequest(kind: .interest, kidID: kid.id) != nil
        let interestAmt = store.interestPoints(for: kid)

        return VStack(alignment: .leading, spacing: 16) {
            Text("Save & Money")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Save to vault")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    CounterControl(value: $depositPoints, range: 1...max(kid.availablePoints, 1))
                }
                Button {
                    withAnimation(KidCoinMotion.list) {
                        store.requestDeposit(points: depositPoints, for: kid)
                    }
                    depositPoints = 1
                } label: {
                    Text(depositPending ? "Deposit pending" : "Request vault deposit")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(depositPending || kid.availablePoints == 0 ? KidCoinTheme.muted : KidCoinTheme.mint.opacity(0.35))
                        .foregroundStyle(depositPending || kid.availablePoints == 0 ? KidCoinTheme.mutedText : KidCoinTheme.mintText)
                        .clipShape(Capsule())
                }
                .buttonStyle(KidCoinPressButtonStyle(scale: 0.97))
                .disabled(depositPending || kid.availablePoints == 0)
            }

            Divider()
                .overlay(KidCoinTheme.border)

            VStack(alignment: .leading, spacing: 8) {
                Text("Cash out is a ledger entry — a parent pays you separately.")
                    .font(.caption)
                    .foregroundStyle(KidCoinTheme.mutedText)
                HStack {
                    Text("Cash out")
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

                Button {
                    withAnimation(KidCoinMotion.list) {
                        store.requestInterest(for: kid)
                    }
                } label: {
                    Text(interestPending ? "Interest pending" : "Request vault interest")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(KidCoinTheme.muted.opacity(0.65))
                        .foregroundStyle(interestPending || interestAmt == 0 ? KidCoinTheme.mutedText : KidCoinTheme.foreground)
                        .clipShape(Capsule())
                }
                .buttonStyle(KidCoinPressButtonStyle(scale: 0.97))
                .disabled(interestPending || interestAmt == 0)
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
