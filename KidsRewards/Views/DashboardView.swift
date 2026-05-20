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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageHeader(eyebrow: "Household", title: "Kids Rewards") {
                        RoundIconButton(systemImage: "plus") {
                            showingAddKid = true
                        }
                        .accessibilityLabel("Add kid")
                    }

                    if !store.state.kids.isEmpty {
                        householdSummarySection
                        needsAttentionSection
                        quickActionsSection
                    }

                    kidsSection

                    if !store.state.kids.isEmpty {
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

    private var householdSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Household")
            HStack(spacing: 12) {
                MetricTile(title: "Available", value: store.totalAvailablePoints, tone: .coral)
                MetricTile(title: "Vault", value: store.totalVaultPoints, tone: .mint)
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
                        .buttonStyle(.plain)
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
                            DashboardKidCard(kid: kid)
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
    }

    @ViewBuilder
    private var recentActivitySection: some View {
        let recent = store.recentTransactions(limit: 8)
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Recent activity")
            if recent.isEmpty {
                Text("Activity from chores, allowance, vault, and cash out will show up here.")
                    .font(.caption)
                    .foregroundStyle(KidCoinTheme.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .tileCard(cornerRadius: 18)
            } else {
                VStack(spacing: 8) {
                    ForEach(recent) { transaction in
                        if let kid = store.kid(withID: transaction.kidID) {
                            NavigationLink(value: kid) {
                                HouseholdActivityRow(
                                    transaction: transaction,
                                    kidName: kid.name,
                                    currencyCode: store.state.settings.currencyCode
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
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
                    subtitle: "Open a kid's vault to apply or request interest",
                    systemImage: "percent",
                    accent: .mint,
                    action: { }
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
                    action: { }
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
        .buttonStyle(.plain)
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

                HStack(spacing: 12) {
                    Label("\(kid.availablePoints) available", systemImage: "star.fill")
                        .foregroundStyle(KidCoinTheme.primary)
                    Label("\(kid.vaultPoints) vault", systemImage: "lock.fill")
                        .foregroundStyle(KidCoinTheme.mintText)
                }
                .font(.caption)

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
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(KidCoinTheme.mutedText)
        }
        .padding(16)
        .tileCard(cornerRadius: 22)
    }
}

private struct HouseholdActivityRow: View {
    let transaction: RewardTransaction
    let kidName: String
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.note)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KidCoinTheme.foreground)
                    .lineLimit(1)
                Text("\(kidName) · \(detailText)")
                    .font(.caption2)
                    .foregroundStyle(KidCoinTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(transaction.pointsDisplayLabel)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(pointsBackground)
                .foregroundStyle(pointsForeground)
                .clipShape(Capsule())
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

    private var pointsBackground: Color {
        switch transaction.kind {
        case .cashedOut: KidCoinTheme.destructive.opacity(0.12)
        case .deposited: KidCoinTheme.mint.opacity(0.25)
        case .withdrawn: KidCoinTheme.primary.opacity(0.2)
        case .earned, .interest, .adjusted: KidCoinTheme.primary.opacity(0.12)
        }
    }

    private var pointsForeground: Color {
        switch transaction.kind {
        case .cashedOut: KidCoinTheme.destructive
        case .deposited: KidCoinTheme.mintText
        case .withdrawn: KidCoinTheme.primary
        case .earned, .interest, .adjusted: KidCoinTheme.primary
        }
    }
}

// MARK: - Kid modals (unchanged)

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
                .buttonStyle(.plain)
            }
            .padding(22)
            .frame(maxWidth: 360)
            .tileCard(cornerRadius: 28)
            .padding(.horizontal, 24)
        }
    }
}
