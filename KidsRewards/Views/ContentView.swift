import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: RewardStore
    @State private var selectedTab: AppTab = .kids
    @State private var isParentUnlocked = false
    @State private var isChildMode = false
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
                    switch selectedTab {
                    case .kids:
                        DashboardView()
                    case .work:
                        TasksView()
                    case .settings:
                        SettingsView()
                    }
                }
                .safeAreaPadding(.bottom, 92)

                KidCoinTabBar(selectedTab: $selectedTab)
            }
        }
        .overlay {
            if store.hasParentPIN && !isParentUnlocked && !isChildMode {
                ParentPINGate(
                    pinEntry: $pinEntry,
                    errorMessage: pinError,
                    onUnlock: {
                        if store.verifyParentPIN(pinEntry) {
                            pinEntry = ""
                            pinError = ""
                            isParentUnlocked = true
                        } else {
                            pinError = "Incorrect PIN"
                        }
                    },
                    onEnterChildMode: {
                        pinEntry = ""
                        pinError = ""
                        isChildMode = true
                    },
                    onBiometricUnlock: {
                        ParentBiometricUnlock.unlock(reason: "Unlock KidCoin Keeper parent controls") { success in
                            if success {
                                pinEntry = ""
                                pinError = ""
                                isParentUnlocked = true
                            } else {
                                pinError = "Biometric unlock failed"
                            }
                        }
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: isParentUnlocked)
        .animation(.easeOut(duration: 0.18), value: isChildMode)
        .onChange(of: store.hasParentPIN) { _, hasPIN in
            isParentUnlocked = !hasPIN
            pinEntry = ""
            pinError = ""
        }
    }
}

private struct ParentPINGate: View {
    @Binding var pinEntry: String
    let errorMessage: String
    let onUnlock: () -> Void
    let onEnterChildMode: () -> Void
    let onBiometricUnlock: () -> Void

    var body: some View {
        ZStack {
            KidCoinTheme.background.ignoresSafeArea()

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

                SecureField("PIN", text: $pinEntry)
                    .keyboardType(.numberPad)
                    .textContentType(.password)
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(KidCoinTheme.muted)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onChange(of: pinEntry) { _, newValue in
                        let filtered = newValue.filter(\.isNumber)
                        if filtered != newValue {
                            pinEntry = filtered
                        }
                    }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KidCoinTheme.destructive)
                }

                PillButton(
                    title: "Unlock",
                    systemImage: "lock.open.fill",
                    tone: .primary,
                    disabled: pinEntry.isEmpty
                ) {
                    onUnlock()
                }

                if ParentBiometricUnlock.isAvailable {
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    PageHeader(eyebrow: "Child mode", title: "My Rewards")
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
                } else {
                    VStack(spacing: 12) {
                        ForEach(store.state.kids) { kid in
                            childCard(for: kid)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 42)
            .padding(.bottom, 24)
        }
        .kidCoinBackground()
    }

    private func childCard(for kid: Kid) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(kid.name)
                        .font(.title3.weight(.bold))
                    Text("\(kid.availablePoints) available · \(kid.vaultPoints) vault")
                        .font(.caption)
                        .foregroundStyle(KidCoinTheme.mutedText)
                }
                Spacer()
            }

            if let goal = kid.savingsGoal {
                VStack(alignment: .leading, spacing: 6) {
                    Text(goal.title)
                        .font(.caption.weight(.bold))
                    ProgressView(value: Double(min(kid.vaultPoints, goal.targetPoints)), total: Double(goal.targetPoints))
                        .tint(KidCoinTheme.mintText)
                }
            }

            if !store.state.settings.approvalFlowEnabled {
                Text("Ask a parent to turn on approval flow before requesting money actions.")
                    .font(.caption)
                    .foregroundStyle(KidCoinTheme.mutedText)
            }

            HStack(spacing: 10) {
                Button("Request Cash Out") {
                    store.requestCashOut(points: kid.availablePoints, for: kid)
                }
                .disabled(!store.state.settings.approvalFlowEnabled || kid.availablePoints == 0)
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(!store.state.settings.approvalFlowEnabled || kid.availablePoints == 0 ? KidCoinTheme.muted : KidCoinTheme.primary)
                .foregroundStyle(!store.state.settings.approvalFlowEnabled || kid.availablePoints == 0 ? KidCoinTheme.mutedText : .white)
                .clipShape(Capsule())

                Button("Request Interest") {
                    store.requestInterest(for: kid)
                }
                .disabled(!store.state.settings.approvalFlowEnabled || store.interestPoints(for: kid) == 0)
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(KidCoinTheme.muted)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .tileCard(cornerRadius: 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kid.name), \(kid.availablePoints) available points, \(kid.vaultPoints) vault points")
    }
}

private enum AppTab: CaseIterable {
    case kids
    case work
    case settings

    var title: String {
        switch self {
        case .kids: "Kids"
        case .work: "Work"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .kids: "person.2.fill"
        case .work: "checklist"
        case .settings: "gearshape.fill"
        }
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
