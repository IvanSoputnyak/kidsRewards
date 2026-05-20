import SwiftUI

struct KidAvailableRoute: Hashable {
    let kidID: UUID
}

struct KidAvailableView: View {
    @EnvironmentObject private var store: RewardStore
    let kidID: UUID

    @State private var cashOutPoints = 1
    @State private var adjustmentPoints = 1
    @State private var adjustmentAddsPoints = true
    @State private var adjustmentNote = ""
    @State private var allowancePointsText = ""
    @State private var kidAllowancePointsText = ""
    @State private var allowanceRecurrence: RewardTask.Recurrence = .none
    @State private var showingCashOutConfirmation = false

    private var kid: Kid? {
        store.kid(withID: kidID)
    }

    var body: some View {
        Group {
            if let kid {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        availableSummary(for: kid)
                        allowanceSection(for: kid)
                        manualAdjustmentSection(for: kid)
                        cashOutSection(for: kid)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                }
                .kidCoinScroll()
                .kidCoinBackground()
                .navigationTitle("Available")
                .navigationBarTitleDisplayMode(.inline)
                .tint(KidCoinTheme.primary)
                .onAppear(perform: loadAllowanceSettings)
                .confirmationDialog(
                    cashOutDialogTitle,
                    isPresented: $showingCashOutConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(cashOutConfirmTitle, role: .destructive) {
                        performCashOut(for: kid)
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text(cashOutDialogMessage(for: kid))
                }
            } else {
                ContentUnavailableView("Kid Not Found", systemImage: "person.crop.circle.badge.questionmark")
                    .kidCoinBackground()
            }
        }
    }

    private func availableSummary(for kid: Kid) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kid.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(KidCoinTheme.mutedText)
                .textCase(.uppercase)
                .tracking(1.2)

            MetricTile(title: "Available", value: kid.availablePoints, systemImage: "star.fill", tone: .coral)

            Text("Cash value: \(Formatters.currency(store.currencyValue(for: kid.availablePoints), code: store.state.settings.currencyCode))")
                .font(.subheadline)
                .foregroundStyle(KidCoinTheme.mutedText)
                .padding(.horizontal, 4)
        }
    }

    private func allowanceSection(for kid: Kid) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Allowance")
            VStack(alignment: .leading, spacing: 14) {
                SettingsField(label: "Default allowance", hint: "Used when a kid has no custom amount") {
                    TextField("5", text: TextFieldFilters.digitsOnly($allowancePointsText, limit: 4))
                        .kidCoinNumberEntry()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 86)
                        .fieldPill()
                }

                SettingsField(
                    label: "\(kid.name)'s allowance",
                    hint: "Leave blank to use the default (\(parsedAllowancePoints) pts)"
                ) {
                    TextField(
                        "\(parsedAllowancePoints)",
                        text: TextFieldFilters.digitsOnly($kidAllowancePointsText, limit: 4)
                    )
                    .kidCoinNumberEntry()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 86)
                    .fieldPill()
                }

                PillButton(
                    title: "Apply to \(kid.name)",
                    systemImage: "person.fill.checkmark",
                    tone: .primary,
                    disabled: parsedAllowancePoints == 0
                ) {
                    saveAllowanceSettings()
                    store.applyAllowance(to: kid)
                }

                PillButton(
                    title: "Apply to All Kids",
                    systemImage: "person.2.fill",
                    tone: .mint,
                    disabled: store.state.kids.isEmpty || parsedAllowancePoints == 0
                ) {
                    saveAllowanceSettings()
                    store.applyAllowanceToAllKids()
                }

                Picker("Automatic allowance", selection: $allowanceRecurrence) {
                    ForEach(RewardTask.Recurrence.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Automatic allowance recurrence")
                .onChange(of: allowanceRecurrence) { _, _ in
                    saveAllowanceSettings()
                }

                Text(allowanceStatusText)
                    .font(.caption)
                    .foregroundStyle(KidCoinTheme.mutedText)

                PillButton(
                    title: "Save Allowance Settings",
                    systemImage: "checkmark",
                    tone: .subtle
                ) {
                    saveAllowanceSettings()
                }
            }
            .padding(18)
            .tileCard(cornerRadius: 26)
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

    private func cashOutSection(for kid: Kid) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Cash Out")
            VStack(spacing: 16) {
                Text("Cash out is a ledger entry. Pay your child the shown amount in cash or through your bank.")
                    .font(.caption)
                    .foregroundStyle(KidCoinTheme.mutedText)

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
                    showingCashOutConfirmation = true
                }
            }
            .padding(18)
            .tileCard(cornerRadius: 26)
        }
    }

    private var parsedAllowancePoints: Int {
        Int(allowancePointsText) ?? store.state.settings.allowancePoints
    }

    private var allowanceStatusText: String {
        switch allowanceRecurrence {
        case .none:
            return "Allowance is manual only."
        case .daily, .weekly:
            let cadence = allowanceRecurrence.label.lowercased()
            if let lastApplied = store.state.settings.lastAllowanceAppliedAt {
                return "Allowance runs \(cadence). Last applied \(lastApplied.formatted(date: .abbreviated, time: .omitted))."
            }
            return "Allowance runs \(cadence) the next time the app opens."
        }
    }

    private var cashOutButtonTitle: String {
        let value = Formatters.currency(store.currencyValue(for: cashOutPoints), code: store.state.settings.currencyCode)
        return store.state.settings.approvalFlowEnabled ? "Request Cash Out \(value)" : "Cash Out \(value)"
    }

    private var cashOutDialogTitle: String {
        store.state.settings.approvalFlowEnabled ? "Request Cash Out?" : "Cash Out Points?"
    }

    private var cashOutConfirmTitle: String {
        store.state.settings.approvalFlowEnabled ? "Request Cash Out" : "Confirm Cash Out"
    }

    private func cashOutDialogMessage(for kid: Kid) -> String {
        let amount = min(cashOutPoints, kid.availablePoints)
        let value = Formatters.currency(store.currencyValue(for: amount), code: store.state.settings.currencyCode)
        if store.state.settings.approvalFlowEnabled {
            return "This creates a pending parent approval for \(amount) points worth \(value). Pay your child that amount in cash or transfer separately."
        }
        return "This records a \(value) cash out (\(amount) points) for \(kid.name). Give your child that amount in cash or transfer separately—the app does not move real money."
    }

    private func performCashOut(for kid: Kid) {
        if store.state.settings.approvalFlowEnabled {
            store.requestCashOut(points: cashOutPoints, for: kid)
        } else {
            store.cashOut(points: cashOutPoints, for: kid)
        }
        cashOutPoints = 1
    }

    private func loadAllowanceSettings() {
        allowancePointsText = "\(store.state.settings.allowancePoints)"
        allowanceRecurrence = store.state.settings.allowanceRecurrence
        guard let kid else { return }
        if let kidAllowance = kid.allowancePoints {
            kidAllowancePointsText = "\(kidAllowance)"
        } else {
            kidAllowancePointsText = ""
        }
    }

    private func saveAllowanceSettings() {
        store.updateSettings(
            currencyCode: store.state.settings.currencyCode,
            currencyPerPoint: store.state.settings.currencyPerPoint,
            vaultInterestRate: store.state.settings.vaultInterestRate,
            allowancePoints: parsedAllowancePoints,
            allowanceRecurrence: allowanceRecurrence
        )
        if let kid {
            let trimmed = kidAllowancePointsText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                store.updateKidAllowancePoints(kid, points: nil)
            } else if let points = Int(trimmed) {
                store.updateKidAllowancePoints(kid, points: points)
            }
        }
        loadAllowanceSettings()
    }
}
