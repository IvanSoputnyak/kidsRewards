import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: RewardStore
    @EnvironmentObject private var router: AppRouter

    @State private var currencyCode = ""
    @State private var pointsPerDollarText = ""
    @State private var parentPINText = ""
    @State private var approvalFlowEnabled = false
    @State private var notificationsEnabled = true
    @State private var iCloudAutoSyncEnabled = false
    @State private var saved = false
    @State private var pinSaved = false
    @State private var savedResetTask: Task<Void, Never>?
    @State private var pinSavedResetTask: Task<Void, Never>?
    @State private var exportDocument = RewardStateDocument(data: Data())
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var pendingImportData: Data?
    @State private var pendingImportPreview: ImportPreview?
    @State private var cloudRestorePreview: ImportPreview?
    @State private var showImportConfirmation = false
    @State private var showRestoreConfirmation = false
    @State private var importMessage = ""
    @State private var approvalMessage = ""

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(eyebrow: "Economy", title: "Settings")

                SectionCard(title: "Point Value") {
                    SettingsField(label: "Currency code", hint: "ISO code used for formatting") {
                        TextField("USD", text: TextFieldFilters.currencyCode($currencyCode))
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 86)
                            .fieldPill()
                    }

                    SettingsField(label: "Points per dollar", hint: "Example: 10 means 10 points = $1 when cashing out") {
                        TextField("10", text: $pointsPerDollarText)
                            .kidCoinDecimalEntry()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 102)
                            .fieldPill()
                    }
                }

                SectionCard(title: ICloudBackup.isAvailable ? "Reminders & Sync" : "Reminders") {
                    Toggle(isOn: $notificationsEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notifications")
                                .font(.subheadline.weight(.semibold))
                            Text("Remind you about allowance, interest, and pending approvals.")
                                .font(.caption)
                                .foregroundStyle(KidCoinTheme.mutedText)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(KidCoinTheme.primary)
                    .onChange(of: notificationsEnabled) { _, newValue in
                        store.setNotificationsEnabled(newValue)
                    }

                    if ICloudBackup.isAvailable {
                        Toggle(isOn: $iCloudAutoSyncEnabled) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Auto-sync to iCloud")
                                    .font(.subheadline.weight(.semibold))
                                Text("Push after each save and pull newer backups when the app opens.")
                                    .font(.caption)
                                    .foregroundStyle(KidCoinTheme.mutedText)
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(KidCoinTheme.mintText)
                        .onChange(of: iCloudAutoSyncEnabled) { _, newValue in
                            store.setICloudAutoSyncEnabled(newValue)
                        }
                    }
                }

                SectionCard(title: "Parent Safety") {
                    SettingsField(label: "Parent PIN", hint: "Locks the app behind a local parent code") {
                        SecureField("Optional", text: TextFieldFilters.digitsOnly($parentPINText, limit: 12))
                            .kidCoinNumericPIN()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 118)
                            .fieldPill()
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
                                        withAnimation(KidCoinMotion.list) {
                                            let didApprove = store.approveRequest(request)
                                            approvalMessage = didApprove
                                                ? ""
                                                : "Could not approve request. The balance, chore, or schedule may have changed."
                                        }
                                    },
                                    onDecline: {
                                        withAnimation(KidCoinMotion.list) {
                                            store.declineRequest(request)
                                            approvalMessage = ""
                                        }
                                    }
                                )
                                .transition(.kidCoinRow)
                            }
                        }
                        .animation(KidCoinMotion.list, value: store.state.approvalRequests)
                    }

                    if !approvalMessage.isEmpty {
                        Text(approvalMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(KidCoinTheme.destructive)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .id("approvalQueue")

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
                    .buttonStyle(KidCoinPressButtonStyle(scale: 0.97))

                    Text(dataBackupFootnote)
                        .font(.caption)
                        .foregroundStyle(KidCoinTheme.mutedText)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if ICloudBackup.isAvailable {
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
                        .buttonStyle(KidCoinPressButtonStyle(scale: 0.97))
                    }

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
            }
            .kidCoinScroll()
            .kidCoinBackground()
            .onAppear(perform: loadSettings)
            .onChange(of: router.focusApprovalsSection) { _, shouldFocus in
                guard shouldFocus else { return }
                withAnimation(KidCoinMotion.scroll) {
                    scrollProxy.scrollTo("approvalQueue", anchor: .top)
                }
                router.focusApprovalsSection = false
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: AppBranding.exportFilename
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
        .onAppear {
            if !ICloudBackup.isAvailable {
                iCloudAutoSyncEnabled = false
            }
        }
    }

    private var dataBackupFootnote: String {
        if ICloudBackup.isAvailable {
            return "Export JSON for a full backup. iCloud sync is optional when enabled above."
        }
        return "Free build: data stays on this device. Export JSON to Files or AirDrop to copy to another phone—no subscription or paid Apple developer account required."
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

    private func currencyPerPointFromPointsField() -> Decimal? {
        guard let pointsPerDollar = Formatters.parseDecimal(pointsPerDollarText) else { return nil }
        return RewardSettings.currencyPerPoint(pointsPerDollar: pointsPerDollar)
    }

    private func loadSettings() {
        currencyCode = store.state.settings.currencyCode
        if let pointsPerDollar = store.state.settings.pointsPerDollar {
            pointsPerDollarText = Formatters.decimalInput(pointsPerDollar)
        } else {
            pointsPerDollarText = ""
        }
        parentPINText = ""
        approvalFlowEnabled = store.state.settings.approvalFlowEnabled
        notificationsEnabled = store.state.settings.notificationsEnabled
        iCloudAutoSyncEnabled = store.state.settings.iCloudAutoSyncEnabled
    }

    private func saveSettings() {
        store.updateSettings(
            currencyCode: currencyCode,
            currencyPerPoint: currencyPerPointFromPointsField() ?? store.state.settings.currencyPerPoint,
            vaultInterestRate: store.state.settings.vaultInterestRate
        )
        loadSettings()
        saved = true
        savedResetTask?.cancel()
        savedResetTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            saved = false
        }
    }

    private func saveParentPIN() {
        let nextPIN = parentPINText
        Task {
            guard await store.updateParentPIN(nextPIN) else { return }
            loadSettings()
            pinSaved = true
            pinSavedResetTask?.cancel()
            pinSavedResetTask = Task {
                try? await Task.sleep(for: .seconds(1.6))
                guard !Task.isCancelled else { return }
                pinSaved = false
            }
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
        store.kid(withID: id)?.name ?? "Unknown kid"
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
            .buttonStyle(KidCoinPressButtonStyle(scale: 0.96))
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
        case .choreCompleted:
            return "\(request.points) points · \(request.note)"
        case .vaultDeposit:
            return "\(request.points) points to vault"
        case .allowance:
            return "\(request.points) allowance points"
        case .goalDeposit:
            return "\(request.points) points to goal"
        case .goalCashOut:
            return "\(request.points) points from goal · \(Formatters.currency(currencyValue, code: currencyCode))"
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
        case .choreCompleted:
            return "Chore completed"
        case .vaultDeposit:
            return "Vault deposit"
        case .allowance:
            return "Allowance"
        case .goalDeposit:
            return "Goal deposit"
        case .goalCashOut:
            return "Goal cash out"
        }
    }

    var systemImage: String {
        switch self {
        case .cashOut:
            return "banknote"
        case .interest:
            return "percent"
        case .choreCompleted:
            return "checkmark.circle"
        case .vaultDeposit:
            return "arrow.down.to.line"
        case .allowance:
            return "gift"
        case .goalDeposit:
            return "target"
        case .goalCashOut:
            return "arrow.up.forward"
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
