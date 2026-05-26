import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: RewardStore
    @EnvironmentObject private var router: AppRouter
    @State private var showingAddKid = false
    @State private var newKidName = ""
    @State private var kidPendingDeletion: Kid?
    @State private var kidBeingEdited: Kid?
    @State private var editedKidName = ""
    @State private var allowanceAppliedMessage = ""
    @State private var navigationPath = NavigationPath()
    @State private var activityVisibleCount = 5

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageHeader(eyebrow: "Household", title: AppBranding.parentAppName)

                    if !store.state.kids.isEmpty {
                        householdSummarySection
                    }

                    kidsSection

                    if !store.state.kids.isEmpty {
                        needsAttentionSection
                        quickActionsSection
                        recentActivitySection
                    }

                    if let pointsPerDollar = store.state.settings.pointsPerDollar {
                        Text("\(Formatters.decimalInput(pointsPerDollar)) points = \(Formatters.currency(1, code: store.state.settings.currencyCode))")
                            .font(.caption)
                            .foregroundStyle(KidCoinTheme.mutedText)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 42)
            }
            .kidCoinScroll()
            .kidCoinBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .overlay { addAndEditKidModals }
            .animation(KidCoinMotion.modal, value: showingAddKid)
            .animation(KidCoinMotion.modal, value: kidBeingEdited)
            .navigationDestination(for: Kid.self) { kid in
                KidDetailView(kidID: kid.id)
            }
            .navigationDestination(for: HouseholdAvailableRoute.self) { route in
                HouseholdAvailableView(initialKidID: route.initialKidID)
            }
            .navigationDestination(for: HouseholdVaultRoute.self) { route in
                HouseholdVaultView(initialKidID: route.initialKidID)
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
                        withAnimation(KidCoinMotion.list) {
                            store.deleteKid(kidPendingDeletion)
                        }
                    }
                    kidPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    kidPendingDeletion = nil
                }
            } message: {
                Text("This deletes their history.")
            }
            .alert("Allowance", isPresented: Binding(
                get: { !allowanceAppliedMessage.isEmpty },
                set: { if !$0 { allowanceAppliedMessage = "" } }
            )) {
                Button("OK", role: .cancel) {
                    allowanceAppliedMessage = ""
                }
            } message: {
                Text(allowanceAppliedMessage)
            }
        }
    }

    @ViewBuilder
    private var addAndEditKidModals: some View {
        if showingAddKid {
            AddKidModal(
                name: $newKidName,
                onCancel: {
                    newKidName = ""
                    withAnimation(KidCoinMotion.modal) {
                        showingAddKid = false
                    }
                },
                onAdd: {
                    withAnimation(KidCoinMotion.list) {
                        store.addKid(name: newKidName)
                    }
                    newKidName = ""
                    withAnimation(KidCoinMotion.modal) {
                        showingAddKid = false
                    }
                }
            )
            .transition(.kidCoinModal)
        }

        if kidBeingEdited != nil {
            EditKidModal(
                name: $editedKidName,
                onCancel: {
                    editedKidName = ""
                    withAnimation(KidCoinMotion.modal) {
                        kidBeingEdited = nil
                    }
                },
                onSave: {
                    if let kidBeingEdited {
                        withAnimation(KidCoinMotion.gentle) {
                            store.updateKid(kidBeingEdited, name: editedKidName)
                        }
                    }
                    editedKidName = ""
                    withAnimation(KidCoinMotion.modal) {
                        kidBeingEdited = nil
                    }
                }
            )
            .transition(.kidCoinModal)
        }
    }

    private var householdSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Household")
            HStack(spacing: 12) {
                NavigationLink(value: HouseholdAvailableRoute()) {
                    MetricTile(
                        title: "Available",
                        value: store.totalAvailablePoints,
                        tone: .coral,
                        showsDisclosure: true
                    )
                }
                .buttonStyle(KidCoinPressButtonStyle(scale: 0.985))
                .accessibilityLabel("Available points, \(store.totalAvailablePoints) total")
                .accessibilityHint("Opens cash out and adjustments for each kid")

                NavigationLink(value: HouseholdVaultRoute()) {
                    MetricTile(
                        title: "Vault",
                        value: store.totalVaultPoints,
                        tone: .mint,
                        showsDisclosure: true
                    )
                }
                .buttonStyle(KidCoinPressButtonStyle(scale: 0.985))
                .accessibilityLabel("Vault points, \(store.totalVaultPoints) total")
                .accessibilityHint("Opens vault, savings goals, and interest for each kid")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Total value: \(Formatters.currency(store.currencyValue(for: store.totalHouseholdPoints), code: store.state.settings.currencyCode))")
                    .font(.subheadline.weight(.semibold))
                let weekEarned = store.earnedPointsThisWeek()
                if weekEarned > 0 {
                    Text("+\(weekEarned) points earned this week")
                        .font(.caption)
                        .foregroundStyle(KidCoinTheme.mintText)
                } else {
                    Text("No points earned yet this week")
                        .font(.caption)
                        .foregroundStyle(KidCoinTheme.mutedText)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var needsAttentionSection: some View {
        let items = attentionItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "Needs attention")
                VStack(spacing: 10) {
                    ForEach(items) { item in
                        Button(action: item.action) {
                            AttentionRow(item: item)
                        }
                        .buttonStyle(KidCoinPressButtonStyle(scale: 0.985))
                    }
                }
            }
        }
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Quick actions")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    QuickActionChip(
                        title: "Allowance",
                        systemImage: "gift.fill",
                        tone: .primary
                    ) {
                        applyAllowanceFromDashboard()
                    }

                    QuickActionChip(
                        title: "Add chore",
                        systemImage: "plus.circle.fill",
                        tone: .mint
                    ) {
                        router.selectedTab = .work
                    }

                    QuickActionChip(
                        title: "Child mode",
                        systemImage: "person.crop.circle",
                        tone: .subtle
                    ) {
                        router.requestChildMode = true
                    }

                    if store.pendingApprovalCount > 0 {
                        QuickActionChip(
                            title: "Approvals",
                            systemImage: "tray.full.fill",
                            tone: .primary
                        ) {
                            openApprovals()
                        }
                    }
                }
            }
        }
    }

    private var kidsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                SectionLabel(title: "Kids")
                Spacer()
                RoundIconButton(systemImage: "plus") {
                    withAnimation(KidCoinMotion.modal) {
                        showingAddKid = true
                    }
                }
                .accessibilityLabel("Add kid")
            }
            if store.state.kids.isEmpty {
                EmptyStatePanel(
                    systemImage: "person.2",
                    title: "No kids yet",
                    message: "Track points, savings, and allowance for everyone in the family."
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(store.state.kids) { kid in
                        DashboardKidCard(kid: kid)
                        .swipeActions {
                            Button {
                                kidBeingEdited = kid
                                editedKidName = kid.name
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(KidCoinTheme.primary)

                            Button(role: .destructive) {
                                kidPendingDeletion = kid
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .animation(KidCoinMotion.list, value: store.state.kids)
            }
        }
    }

    private let activityPageSize = 10
    private let activityInitialCount = 5

    @ViewBuilder
    private var recentActivitySection: some View {
        let total = store.state.transactions.count
        let visible = store.recentTransactions(limit: activityVisibleCount)
        let hasMore = activityVisibleCount < total
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(title: "Recent activity")
                Spacer()
                if total > 0 {
                    Text("\(total) total")
                        .font(.caption)
                        .foregroundStyle(KidCoinTheme.mutedText)
                }
            }
            if visible.isEmpty {
                Text("Activity from chores, allowance, vault, and cash out will show up here.")
                    .font(.caption)
                    .foregroundStyle(KidCoinTheme.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .tileCard(cornerRadius: 18)
            } else {
                VStack(spacing: 8) {
                    ForEach(visible) { transaction in
                        if let kid = store.kid(withID: transaction.kidID) {
                            NavigationLink(value: kid) {
                                RewardTransactionRow(
                                    transaction: transaction,
                                    currencyCode: store.state.settings.currencyCode,
                                    variant: .household(kidName: kid.name)
                                )
                            }
                            .buttonStyle(KidCoinPressButtonStyle(scale: 0.985))
                        }
                    }

                    if hasMore {
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                activityVisibleCount += activityPageSize
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text("Show \(min(activityPageSize, total - activityVisibleCount)) more")
                                    .font(.caption.weight(.semibold))
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(KidCoinTheme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(KidCoinTheme.primary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .animation(KidCoinMotion.list, value: visible.map(\.id))
            }
        }
    }

    private var attentionItems: [DashboardAttentionItem] {
        var items: [DashboardAttentionItem] = []

        let pending = store.pendingApprovalCount
        if pending > 0 {
            let suffix = pending == 1 ? "" : "s"
            items.append(
                DashboardAttentionItem(
                    id: "approvals",
                    title: "\(pending) approval request\(suffix)",
                    subtitle: "Review kid requests in Settings",
                    systemImage: "tray.full.fill",
                    accent: .primary,
                    action: openApprovals
                )
            )
        }

        if store.isAllowanceScheduleDue() {
            items.append(
                DashboardAttentionItem(
                    id: "allowance",
                    title: "Allowance is due",
                    subtitle: store.state.settings.approvalFlowEnabled
                        ? "Tap to queue allowance for approval"
                        : "Tap to apply to all kids",
                    systemImage: "gift.fill",
                    accent: .primary,
                    action: applyAllowanceFromDashboard
                )
            )
        }

        if store.isInterestScheduleDue() {
            items.append(
                DashboardAttentionItem(
                    id: "interest",
                    title: "Vault interest is due",
                    subtitle: "Open vault to apply or request interest",
                    systemImage: "percent",
                    accent: .mint,
                    action: openVaultForScheduledInterest
                )
            )
        }

        let readyChores = store.totalReadyChoreCount()
        if readyChores > 0 {
            items.append(
                DashboardAttentionItem(
                    id: "chores",
                    title: "\(readyChores) chore\(readyChores == 1 ? "" : "s") ready to award",
                    subtitle: "Open a kid to award work",
                    systemImage: "checkmark.circle.fill",
                    accent: .primary,
                    action: openKidWithReadyChores
                )
            )
        }

        return items
    }

    private var deletionTitle: String {
        guard let kidPendingDeletion else { return "Remove Kid?" }
        return "Remove \(kidPendingDeletion.name)?"
    }

    private func openApprovals() {
        router.selectedTab = .settings
        router.focusApprovalsSection = true
    }

    private func applyAllowanceFromDashboard() {
        if store.isAllowanceScheduleDue() {
            if store.applyDueAllowanceIfNeeded() {
                allowanceAppliedMessage = store.state.settings.approvalFlowEnabled
                    ? "Allowance requests were added to the approval queue."
                    : "Allowance was applied to all kids."
            } else {
                allowanceAppliedMessage = "Allowance could not be applied right now."
            }
        } else {
            store.applyAllowanceToAllKids()
            allowanceAppliedMessage = "Allowance was applied to all kids."
        }
    }

    private func openKidWithReadyChores() {
        guard let kid = store.firstKidWithReadyChores() else { return }
        navigationPath.append(kid)
    }

    private func openVaultForScheduledInterest() {
        guard let kid = store.firstKidEligibleForVaultInterest() else { return }
        navigationPath.append(HouseholdVaultRoute(initialKidID: kid.id))
    }
}

// MARK: - Dashboard components

private struct DashboardAttentionItem: Identifiable {
    enum Accent {
        case primary
        case mint
        case muted
    }

    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Accent
    let action: () -> Void
}

private struct AttentionRow: View {
    let item: DashboardAttentionItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 40, height: 40)
                .background(iconColor.opacity(0.14))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KidCoinTheme.foreground)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(KidCoinTheme.mutedText)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(KidCoinTheme.mutedText)
        }
        .padding(14)
        .tileCard(cornerRadius: 18)
    }

    private var iconColor: Color {
        switch item.accent {
        case .primary: KidCoinTheme.primary
        case .mint: KidCoinTheme.mintText
        case .muted: KidCoinTheme.mutedText
        }
    }
}

private struct QuickActionChip: View {
    let title: String
    let systemImage: String
    let tone: PillButton.Tone
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                Text(title)
                    .font(.caption.weight(.bold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
        }
        .buttonStyle(KidCoinPressButtonStyle(scale: 0.96))
    }

    private var background: Color {
        switch tone {
        case .primary: KidCoinTheme.primary
        case .mint: KidCoinTheme.mint.opacity(0.35)
        case .subtle: KidCoinTheme.muted
        }
    }

    private var foreground: Color {
        switch tone {
        case .primary: .white
        case .mint: KidCoinTheme.mintText
        case .subtle: KidCoinTheme.foreground
        }
    }
}

private struct DashboardKidCard: View {
    @EnvironmentObject private var store: RewardStore
    let kid: Kid

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                NavigationLink(value: kid) {
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

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(kid.name)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(KidCoinTheme.foreground)
                                if store.pendingRequestCount(for: kid) > 0 {
                                    Text("Pending")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(KidCoinTheme.primary.opacity(0.14))
                                        .foregroundStyle(KidCoinTheme.primary)
                                        .clipShape(Capsule())
                                }
                            }

                            if let goal = kid.savingsGoal {
                                let progress = store.savingsGoalProgress(for: kid)
                                Text("\(goal.title): \(progress)/\(goal.targetPoints) toward goal")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(KidCoinTheme.mintText)
                            }

                            if let activity = store.lastActivitySummary(for: kid) {
                                Text(activity)
                                    .font(.caption2)
                                    .foregroundStyle(KidCoinTheme.mutedText)
                                    .lineLimit(1)
                            }

                            let ready = store.readyChoreCount(for: kid)
                            if ready > 0 {
                                Text("\(ready) chore\(ready == 1 ? "" : "s") ready to award")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(KidCoinTheme.primary)
                            }

                            Text("Award work & history")
                                .font(.caption2)
                                .foregroundStyle(KidCoinTheme.mutedText)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(KidCoinTheme.mutedText)
                    }
                }
                .buttonStyle(KidCoinPressButtonStyle(scale: 0.985))
                .accessibilityLabel("\(kid.name), award work and history")
            }

            HStack(spacing: 10) {
                NavigationLink(value: HouseholdAvailableRoute(initialKidID: kid.id)) {
                    KidBalanceChip(
                        title: "Available",
                        points: kid.availablePoints,
                        systemImage: "star.fill",
                        tone: .coral
                    )
                }
                .buttonStyle(KidCoinPressButtonStyle(scale: 0.985))

                NavigationLink(value: HouseholdVaultRoute(initialKidID: kid.id)) {
                    KidBalanceChip(
                        title: "Vault",
                        points: kid.vaultPoints,
                        systemImage: "lock.fill",
                        tone: .mint
                    )
                }
                .buttonStyle(KidCoinPressButtonStyle(scale: 0.985))
            }
        }
        .padding(16)
        .tileCard(cornerRadius: 22)
    }
}

private struct KidBalanceChip: View {
    enum Tone {
        case coral
        case mint
    }

    let title: String
    let points: Int
    let systemImage: String
    let tone: Tone

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                Text("\(points)")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .opacity(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .foregroundStyle(foreground)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(points) points")
    }

    private var foreground: Color {
        switch tone {
        case .coral: KidCoinTheme.primary
        case .mint: KidCoinTheme.mintText
        }
    }

    private var background: Color {
        switch tone {
        case .coral: KidCoinTheme.primary.opacity(0.1)
        case .mint: KidCoinTheme.mint.opacity(0.22)
        }
    }
}

// MARK: - Kid modals

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
                    .kidCoinNameEntry()
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
                .buttonStyle(KidCoinPressButtonStyle(scale: 0.97))
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
                    .kidCoinNameEntry()
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
                .buttonStyle(KidCoinPressButtonStyle(scale: 0.97))
            }
            .padding(22)
            .frame(maxWidth: 360)
            .tileCard(cornerRadius: 28)
            .padding(.horizontal, 24)
        }
    }
}
