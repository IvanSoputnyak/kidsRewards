import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: RewardStore

    @State private var currencyCode = ""
    @State private var currencyPerPointText = ""
    @State private var interestRateText = ""
    @State private var allowancePointsText = ""
    @State private var allowanceRecurrence: RewardTask.Recurrence = .none
    @State private var parentPINText = ""
    @State private var approvalFlowEnabled = false
    @State private var saved = false
    @State private var pinSaved = false
    @State private var exportDocument = RewardStateDocument(data: Data())
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var pendingImportData: Data?
    @State private var pendingImportPreview: ImportPreview?
    @State private var cloudRestorePreview: ImportPreview?
    @State private var showImportConfirmation = false
    @State private var showRestoreConfirmation = false
    @State private var importMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(eyebrow: "Economy", title: "Settings")

                SectionCard(title: "Point Value") {
                    SettingsField(label: "Currency code", hint: "ISO code used for formatting") {
                        TextField("USD", text: $currencyCode)
                            .textInputAutocapitalization(.characters)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 86)
                            .fieldPill()
                            .onChange(of: currencyCode) { _, newValue in
                                let normalized = String(newValue.uppercased().prefix(3))
                                if currencyCode != normalized {
                                    currencyCode = normalized
                                }
                            }
                    }

                    SettingsField(label: "Currency per point", hint: "What 1 point is worth when cashing out") {
                        TextField("1", text: $currencyPerPointText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 102)
                            .fieldPill()
                    }
                }

                SectionCard(title: "Vault") {
                    SettingsField(label: "Interest rate", hint: "Decimal, 0.05 means 5%") {
                        TextField("0.05", text: $interestRateText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 102)
                            .fieldPill()
                    }

                    HStack {
                        Text("Current interest")
                            .font(.subheadline)
                            .foregroundStyle(KidCoinTheme.mutedText)
                        Spacer()
                        Text(currentInterestLabel)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(KidCoinTheme.mintText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(KidCoinTheme.mint.opacity(0.28))
                            .clipShape(Capsule())
                    }

                    Text("Interest is applied manually per tap on a kid's vault, not automatically over time.")
                        .font(.caption)
                        .foregroundStyle(KidCoinTheme.mutedText)
                        .lineSpacing(2)
                }

                SectionCard(title: "Allowance") {
                    SettingsField(label: "Allowance points", hint: "Manual weekly allowance amount per kid") {
                        TextField("5", text: $allowancePointsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 86)
                            .fieldPill()
                            .onChange(of: allowancePointsText) { _, newValue in
                                let filtered = String(newValue.filter(\.isNumber).prefix(4))
                                if allowancePointsText != filtered {
                                    allowancePointsText = filtered
                                }
                            }
                    }

                    PillButton(
                        title: "Apply Allowance Now",
                        systemImage: "calendar.badge.plus",
                        tone: .mint,
                        disabled: store.state.kids.isEmpty || (Int(allowancePointsText) ?? store.state.settings.allowancePoints) == 0
                    ) {
                        saveSettings()
                        store.applyAllowanceToAllKids()
                    }

                    Picker("Automatic allowance", selection: $allowanceRecurrence) {
                        ForEach(RewardTask.Recurrence.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Automatic allowance recurrence")

                    Text(allowanceStatusText)
                        .font(.caption)
                        .foregroundStyle(KidCoinTheme.mutedText)
                }

                SectionCard(title: "Parent Safety") {
                    SettingsField(label: "Parent PIN", hint: "Locks the app behind a local parent code") {
                        SecureField("Optional", text: $parentPINText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 118)
                            .fieldPill()
                            .onChange(of: parentPINText) { _, newValue in
                                let filtered = String(newValue.filter(\.isNumber).prefix(12))
                                if parentPINText != filtered {
                                    parentPINText = filtered
                                }
                            }
                    }

                    PillButton(
                        title: pinButtonTitle,
                        systemImage: pinButtonSystemImage,
                        tone: parentPINText.isEmpty && store.hasParentPIN ? .subtle : .primary,
                        disabled: parentPINText.isEmpty && !store.hasParentPIN
                    ) {
                        saveParentPIN()
                    }

                    Text(store.hasParentPIN ? "Parent PIN is active." : "No parent PIN is set.")
                        .font(.caption)
                        .foregroundStyle(KidCoinTheme.mutedText)

                    Toggle(isOn: $approvalFlowEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Approval flow")
                                .font(.subheadline.weight(.semibold))
                            Text("Kid money actions become requests until a parent approves them.")
                                .font(.caption)
                                .foregroundStyle(KidCoinTheme.mutedText)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(KidCoinTheme.primary)
                    .onChange(of: approvalFlowEnabled) { _, newValue in
                        store.setApprovalFlowEnabled(newValue)
                    }
                }

                SectionCard(title: "Approval Queue") {
                    if store.state.approvalRequests.isEmpty {
                        Text("No pending requests.")
                            .font(.subheadline)
                            .foregroundStyle(KidCoinTheme.mutedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(store.state.approvalRequests.sorted { $0.date > $1.date }) { request in
                                ApprovalRequestRow(
                                    request: request,
                                    kidName: kidName(for: request.kidID),
                                    currencyCode: store.state.settings.currencyCode,
                                    currencyValue: store.currencyValue(for: request.points),
                                    onApprove: {
                                        _ = store.approveRequest(request)
                                    },
                                    onDecline: {
                                        store.declineRequest(request)
                                    }
                                )
                            }
                        }
                    }
                }

                SectionCard(title: "Data") {
                    HStack(spacing: 10) {
                        Button("Export JSON") {
                            exportDocument = RewardStateDocument(data: store.exportStateData() ?? Data())
                            isExporting = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(KidCoinTheme.muted)
                        .clipShape(Capsule())

                        Button("Import JSON") {
                            isImporting = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(KidCoinTheme.muted)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 10) {
                        Button("Sync to iCloud") {
                            importMessage = store.syncToICloud()
                                ? "Synced to iCloud key-value storage."
                                : "iCloud sync failed."
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(KidCoinTheme.mint.opacity(0.24))
                        .clipShape(Capsule())

                        Button("Restore iCloud") {
                            if let preview = store.iCloudBackupPreview() {
                                cloudRestorePreview = preview
                                showRestoreConfirmation = true
                            } else {
                                importMessage = "No iCloud backup found."
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(KidCoinTheme.mint.opacity(0.24))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    if !importMessage.isEmpty {
                        Text(importMessage)
                            .font(.caption)
                            .foregroundStyle(KidCoinTheme.mutedText)
                    }

                    if let persistenceError = store.persistenceErrorMessage {
                        Text("Storage issue: \(persistenceError)")
                            .font(.caption)
                            .foregroundStyle(KidCoinTheme.destructive)
                    }
                }

                PillButton(
                    title: saved ? "Saved" : "Save Settings",
                    systemImage: "checkmark",
                    tone: .primary
                ) {
                    saveSettings()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 42)
            .padding(.bottom, 20)
        }
        .kidCoinBackground()
        .onAppear(perform: loadSettings)
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "kidcoin-keeper-backup"
        ) { _ in }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                guard url.startAccessingSecurityScopedResource() else {
                    importMessage = "Could not access selected file."
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url) {
                    if let preview = store.importPreview(from: data) {
                        pendingImportData = data
                        pendingImportPreview = preview
                        showImportConfirmation = true
                        importMessage = "Backup selected."
                    } else {
                        importMessage = "Import failed."
                    }
                } else {
                    importMessage = "Import failed."
                }
            case .failure:
                importMessage = "Import canceled."
            }
        }
        .confirmationDialog(
            "Import Backup?",
            isPresented: $showImportConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace Local Data", role: .destructive) {
                importPendingBackup()
            }
            Button("Cancel", role: .cancel) {
                pendingImportData = nil
                pendingImportPreview = nil
            }
        } message: {
            Text(importConfirmationMessage)
        }
        .confirmationDialog(
            "Restore iCloud Backup?",
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace Local Data", role: .destructive) {
                restoreCloudBackup()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(restoreConfirmationMessage)
        }
    }

    private var currentInterestLabel: String {
        let rate = Decimal(string: interestRateText) ?? store.state.settings.vaultInterestRate
        return Formatters.percent(rate)
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

    private var pinButtonTitle: String {
        if pinSaved { return "PIN Saved" }
        if parentPINText.isEmpty {
            return store.hasParentPIN ? "Remove PIN" : "No PIN Set"
        }
        return store.hasParentPIN ? "Update PIN" : "Set PIN"
    }

    private var pinButtonSystemImage: String {
        if parentPINText.isEmpty {
            return store.hasParentPIN ? "lock.open.fill" : "lock.slash"
        }
        return "lock.fill"
    }

    private var importConfirmationMessage: String {
        previewMessage(for: pendingImportPreview, fallback: "This replaces all local data with the selected backup.")
    }

    private var restoreConfirmationMessage: String {
        previewMessage(for: cloudRestorePreview, fallback: "This replaces all local data with the backup currently stored in iCloud key-value storage.")
    }

    private func loadSettings() {
        currencyCode = store.state.settings.currencyCode
        currencyPerPointText = "\(store.state.settings.currencyPerPoint)"
        interestRateText = "\(store.state.settings.vaultInterestRate)"
        allowancePointsText = "\(store.state.settings.allowancePoints)"
        allowanceRecurrence = store.state.settings.allowanceRecurrence
        parentPINText = ""
        approvalFlowEnabled = store.state.settings.approvalFlowEnabled
    }

    private func saveSettings() {
        store.updateSettings(
            currencyCode: currencyCode,
            currencyPerPoint: Decimal(string: currencyPerPointText) ?? store.state.settings.currencyPerPoint,
            vaultInterestRate: Decimal(string: interestRateText) ?? store.state.settings.vaultInterestRate,
            allowancePoints: Int(allowancePointsText) ?? store.state.settings.allowancePoints,
            allowanceRecurrence: allowanceRecurrence
        )
        loadSettings()
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            saved = false
        }
    }

    private func saveParentPIN() {
        store.updateParentPIN(parentPINText)
        loadSettings()
        pinSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            pinSaved = false
        }
    }

    private func importPendingBackup() {
        guard let data = pendingImportData else { return }
        pendingImportData = nil
        pendingImportPreview = nil
        if store.importStateData(data) {
            importMessage = "Imported backup."
            loadSettings()
        } else {
            importMessage = "Import failed."
        }
    }

    private func restoreCloudBackup() {
        if store.restoreFromICloud() {
            importMessage = "Restored from iCloud."
            cloudRestorePreview = nil
            loadSettings()
        } else {
            importMessage = "No iCloud backup found."
        }
    }

    private func previewMessage(for preview: ImportPreview?, fallback: String) -> String {
        guard let preview else { return fallback }
        var parts = [
            "\(preview.kidsCount) kids",
            "\(preview.tasksCount) chores",
            "\(preview.transactionsCount) transactions",
            "\(preview.approvalRequestsCount) approval requests"
        ]
        if let savedAt = preview.savedAt {
            parts.append("saved \(savedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        if let deviceName = preview.deviceName, !deviceName.isEmpty {
            parts.append("from \(deviceName)")
        }
        return "This replaces all local data with: \(parts.joined(separator: ", "))."
    }

    private func kidName(for id: UUID) -> String {
        store.state.kids.first { $0.id == id }?.name ?? "Unknown kid"
    }
}

private struct RewardStateDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct ApprovalRequestRow: View {
    let request: ApprovalRequest
    let kidName: String
    let currencyCode: String
    let currencyValue: Decimal
    let onApprove: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: request.kind.systemImage)
                    .font(.headline)
                    .foregroundStyle(KidCoinTheme.primary)
                    .frame(width: 38, height: 38)
                    .background(KidCoinTheme.primary.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(request.kind.title)
                        .font(.subheadline.weight(.bold))
                    Text("\(kidName) · \(detailText)")
                        .font(.caption)
                        .foregroundStyle(KidCoinTheme.mutedText)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Button("Decline", action: onDecline)
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(KidCoinTheme.muted)
                    .clipShape(Capsule())

                Button("Approve", action: onApprove)
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(KidCoinTheme.primary)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(KidCoinTheme.muted.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var detailText: String {
        switch request.kind {
        case .cashOut:
            return "\(request.points) points · \(Formatters.currency(currencyValue, code: currencyCode))"
        case .interest:
            return "\(request.points) interest points"
        }
    }
}

private extension ApprovalRequest.Kind {
    var title: String {
        switch self {
        case .cashOut:
            return "Cash out request"
        case .interest:
            return "Interest request"
        }
    }

    var systemImage: String {
        switch self {
        case .cashOut:
            return "banknote"
        case .interest:
            return "percent"
        }
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: title)
            content
        }
        .padding(18)
        .tileCard(cornerRadius: 26)
    }
}

private struct SettingsField<Content: View>: View {
    let label: String
    let hint: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(KidCoinTheme.mutedText)
            }
            Spacer()
            content
        }
    }
}

private extension View {
    func fieldPill() -> some View {
        self
            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(KidCoinTheme.muted)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
