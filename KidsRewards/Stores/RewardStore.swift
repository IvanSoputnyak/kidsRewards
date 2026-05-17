import Foundation

@MainActor
final class RewardStore: ObservableObject {
    @Published private(set) var state: RewardState
    @Published private(set) var persistenceErrorMessage: String?

    private let fileURL: URL
    private let pinManager: ParentPINManaging
    private let cloudBackupKey = "kidsRewardsState.v2"
    private let legacyCloudBackupKey = "kidsRewardsState"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        initialState: RewardState = .empty,
        fileURL: URL? = nil,
        pinManager: ParentPINManaging = KeychainParentPINManager()
    ) {
        self.pinManager = pinManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.fileURL = documents.appendingPathComponent("kids-rewards-state.json")
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? decoder.decode(RewardState.self, from: data) {
            state = decoded
            migrateLegacyParentPINIfNeeded()
            applyDueAllowanceIfNeeded()
        } else {
            state = initialState
            migrateLegacyParentPINIfNeeded()
            applyDueAllowanceIfNeeded()
            save()
        }
    }

    var totalAvailablePoints: Int {
        state.kids.reduce(0) { $0 + $1.availablePoints }
    }

    var totalVaultPoints: Int {
        state.kids.reduce(0) { $0 + $1.vaultPoints }
    }

    var hasParentPIN: Bool {
        pinManager.hasPIN
    }

    func addKid(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.kids.append(Kid(name: trimmed, availablePoints: 0, vaultPoints: 0))
        save()
    }

    func updateKid(_ kid: Kid, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateKid(kid.id) { $0.name = trimmed }
        save()
    }

    func deleteKid(_ kid: Kid) {
        state.kids.removeAll { $0.id == kid.id }
        state.transactions.removeAll { $0.kidID == kid.id }
        save()
    }

    func addTask(title: String, points: Int) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, points > 0 else { return }
        state.tasks.append(RewardTask(title: trimmed, points: points))
        save()
    }

    func updateTask(_ task: RewardTask, title: String, points: Int) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, points > 0 else { return }
        guard let index = state.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        state.tasks[index].title = trimmed
        state.tasks[index].points = points
        save()
    }

    func updateTaskRecurrence(_ task: RewardTask, recurrence: RewardTask.Recurrence) {
        guard let index = state.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        state.tasks[index].recurrence = recurrence
        save()
    }

    func deleteTask(_ task: RewardTask) {
        state.tasks.removeAll { $0.id == task.id }
        save()
    }

    func award(task: RewardTask, to kid: Kid, at date: Date = Date()) {
        guard isTaskAvailable(task, for: kid, now: date) else { return }
        updateKid(kid.id) { $0.availablePoints += task.points }
        addTransaction(
            kidID: kid.id,
            kind: .earned,
            points: task.points,
            note: task.title,
            currencyAmount: nil
        )
        updateTaskCompletion(task, for: kid, at: date)
        save()
    }

    func isTaskAvailable(_ task: RewardTask, for kid: Kid, now: Date = Date()) -> Bool {
        guard task.recurrence != .none,
              let completion = taskCompletion(for: task, kid: kid) else {
            return true
        }
        return isDue(since: completion.lastAwardedAt, recurrence: task.recurrence, now: now)
    }

    func deposit(points: Int, for kid: Kid) {
        guard points > 0 else { return }
        updateKid(kid.id) { current in
            let amount = min(points, current.availablePoints)
            guard amount > 0 else { return }
            current.availablePoints -= amount
            current.vaultPoints += amount
            addTransaction(
                kidID: kid.id,
                kind: .deposited,
                points: amount,
                note: "Vault deposit",
                currencyAmount: nil
            )
        }
        save()
    }

    @discardableResult
    func cashOut(points: Int, for kid: Kid) -> Bool {
        guard points > 0 else { return false }
        var didCashOut = false
        updateKid(kid.id) { current in
            let amount = min(points, current.availablePoints)
            guard amount > 0 else { return }
            current.availablePoints -= amount
            addTransaction(
                kidID: kid.id,
                kind: .cashedOut,
                points: amount,
                note: "Cash out",
                currencyAmount: Decimal(amount) * state.settings.currencyPerPoint
            )
            didCashOut = true
        }
        if didCashOut {
            save()
        }
        return didCashOut
    }

    func requestCashOut(points: Int, for kid: Kid) {
        guard state.settings.approvalFlowEnabled, points > 0 else { return }
        let amount = min(points, kid.availablePoints)
        guard amount > 0 else { return }
        addApprovalRequest(
            kidID: kid.id,
            kind: .cashOut,
            points: amount,
            note: "Cash out request"
        )
        save()
    }

    @discardableResult
    func applyInterest(to kid: Kid) -> Bool {
        let points = interestPoints(for: kid)
        return applyInterest(points: points, to: kid)
    }

    @discardableResult
    private func applyInterest(points: Int, to kid: Kid) -> Bool {
        guard points > 0 else { return false }
        var didApplyInterest = false
        updateKid(kid.id) { current in
            current.vaultPoints += points
            addTransaction(
                kidID: kid.id,
                kind: .interest,
                points: points,
                note: "Vault interest",
                currencyAmount: nil
            )
            didApplyInterest = true
        }
        if didApplyInterest {
            save()
        }
        return didApplyInterest
    }

    func requestInterest(for kid: Kid) {
        guard state.settings.approvalFlowEnabled else { return }
        let points = interestPoints(for: kid)
        guard points > 0 else { return }
        addApprovalRequest(
            kidID: kid.id,
            kind: .interest,
            points: points,
            note: "Vault interest request"
        )
        save()
    }

    func interestPoints(for kid: Kid) -> Int {
        let interest = Decimal(kid.vaultPoints) * state.settings.vaultInterestRate
        return NSDecimalNumber(decimal: interest).rounding(accordingToBehavior: nil).intValue
    }

    func adjust(points requestedPoints: Int, note: String, for kid: Kid) {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard requestedPoints != 0 else { return }

        updateKid(kid.id) { current in
            let points = requestedPoints < 0
                ? -min(abs(requestedPoints), current.availablePoints)
                : requestedPoints
            guard points != 0 else { return }
            current.availablePoints += points
            addTransaction(
                kidID: kid.id,
                kind: .adjusted,
                points: points,
                note: trimmedNote.isEmpty ? "Manual adjustment" : trimmedNote,
                currencyAmount: nil
            )
        }
        save()
    }

    func updateSavingsGoal(for kid: Kid, title: String, targetPoints: Int) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, targetPoints > 0 else { return }
        updateKid(kid.id) {
            $0.savingsGoal = SavingsGoal(title: trimmed, targetPoints: targetPoints)
        }
        save()
    }

    func clearSavingsGoal(for kid: Kid) {
        updateKid(kid.id) {
            $0.savingsGoal = nil
        }
        save()
    }

    @discardableResult
    func deleteTransaction(_ transaction: RewardTransaction) -> Bool {
        guard let transactionIndex = state.transactions.firstIndex(where: { $0.id == transaction.id }),
              let kidIndex = state.kids.firstIndex(where: { $0.id == transaction.kidID }) else {
            return false
        }

        var kid = state.kids[kidIndex]
        guard apply(transaction, to: &kid, multiplier: -1) else { return false }
        state.kids[kidIndex] = kid
        state.transactions.remove(at: transactionIndex)
        save()
        return true
    }

    @discardableResult
    func correctTransaction(_ transaction: RewardTransaction, points: Int, note: String) -> Bool {
        guard let transactionIndex = state.transactions.firstIndex(where: { $0.id == transaction.id }),
              let kidIndex = state.kids.firstIndex(where: { $0.id == transaction.kidID }) else {
            return false
        }

        let correctedPoints = normalizedCorrectionPoints(points, for: transaction.kind)
        guard correctedPoints != 0 else { return false }

        var corrected = transaction
        corrected.points = correctedPoints
        corrected.note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? transaction.note : note.trimmingCharacters(in: .whitespacesAndNewlines)
        if corrected.kind == .cashedOut {
            corrected.currencyAmount = Decimal(abs(correctedPoints)) * state.settings.currencyPerPoint
        }

        var kid = state.kids[kidIndex]
        guard apply(transaction, to: &kid, multiplier: -1),
              apply(corrected, to: &kid, multiplier: 1) else {
            return false
        }

        state.kids[kidIndex] = kid
        state.transactions[transactionIndex] = corrected
        save()
        return true
    }

    func updateSettings(
        currencyCode: String,
        currencyPerPoint: Decimal,
        vaultInterestRate: Decimal,
        allowancePoints: Int? = nil,
        allowanceRecurrence: RewardTask.Recurrence? = nil
    ) {
        let normalizedCurrency = currencyCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .prefix(3)
        let savedCurrencyCode = normalizedCurrency.isEmpty ? state.settings.currencyCode : String(normalizedCurrency)

        state.settings = RewardSettings(
            currencyCode: savedCurrencyCode,
            currencyPerPoint: max(currencyPerPoint, 0),
            vaultInterestRate: max(vaultInterestRate, 0),
            approvalFlowEnabled: state.settings.approvalFlowEnabled,
            allowancePoints: max(allowancePoints ?? state.settings.allowancePoints, 0),
            allowanceRecurrence: allowanceRecurrence ?? state.settings.allowanceRecurrence,
            lastAllowanceAppliedAt: state.settings.lastAllowanceAppliedAt
        )
        save()
    }

    func applyAllowanceToAllKids(at date: Date = Date()) {
        let points = state.settings.allowancePoints
        guard points > 0 else { return }

        for index in state.kids.indices {
            state.kids[index].availablePoints += points
            addTransaction(
                kidID: state.kids[index].id,
                kind: .earned,
                points: points,
                note: "Allowance",
                currencyAmount: nil
            )
        }
        state.settings.lastAllowanceAppliedAt = date
        save()
    }

    @discardableResult
    func applyDueAllowanceIfNeeded(now: Date = Date()) -> Bool {
        let recurrence = state.settings.allowanceRecurrence
        guard recurrence != .none,
              !state.kids.isEmpty,
              state.settings.allowancePoints > 0 else {
            return false
        }
        if let lastApplied = state.settings.lastAllowanceAppliedAt,
           !isDue(since: lastApplied, recurrence: recurrence, now: now) {
            return false
        }
        applyAllowanceToAllKids(at: now)
        return true
    }

    func updateParentPIN(_ pin: String) {
        let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        objectWillChange.send()
        if trimmed.isEmpty {
            pinManager.clear()
        } else {
            pinManager.save(pin: String(trimmed.prefix(12)))
        }
        save()
    }

    func verifyParentPIN(_ pin: String) -> Bool {
        pinManager.verify(pin: pin)
    }

    func setApprovalFlowEnabled(_ isEnabled: Bool) {
        state.settings.approvalFlowEnabled = isEnabled
        save()
    }

    @discardableResult
    func approveRequest(_ request: ApprovalRequest) -> Bool {
        guard let currentRequest = state.approvalRequests.first(where: { $0.id == request.id }),
              let kid = state.kids.first(where: { $0.id == currentRequest.kidID }) else {
            return false
        }

        let didApply: Bool
        switch currentRequest.kind {
        case .cashOut:
            didApply = cashOutExact(points: currentRequest.points, for: kid)
        case .interest:
            didApply = applyInterest(points: currentRequest.points, to: kid)
        }
        guard didApply else { return false }

        state.approvalRequests.removeAll { $0.id == currentRequest.id }
        save()
        return true
    }

    func declineRequest(_ request: ApprovalRequest) {
        state.approvalRequests.removeAll { $0.id == request.id }
        save()
    }

    func transactions(for kid: Kid) -> [RewardTransaction] {
        state.transactions
            .filter { $0.kidID == kid.id }
            .sorted { $0.date > $1.date }
    }

    func currencyValue(for points: Int) -> Decimal {
        Decimal(points) * state.settings.currencyPerPoint
    }

    func exportStateData() -> Data? {
        try? encoder.encode(state)
    }

    func importPreview(from data: Data) -> ImportPreview? {
        guard let decoded = decodeImportData(data) else { return nil }
        return ImportPreview(
            kidsCount: decoded.state.kids.count,
            tasksCount: decoded.state.tasks.count,
            transactionsCount: decoded.state.transactions.count,
            approvalRequestsCount: decoded.state.approvalRequests.count,
            savedAt: decoded.savedAt,
            deviceName: decoded.deviceName,
            isCloudBackup: decoded.isCloudBackup
        )
    }

    @discardableResult
    func importStateData(_ data: Data) -> Bool {
        guard let decoded = decodeImportData(data)?.state else { return false }
        let previousState = state
        state = decoded
        migrateLegacyParentPINIfNeeded()
        guard save() else {
            state = previousState
            return false
        }
        return true
    }

    @discardableResult
    func syncToICloud() -> Bool {
        let envelope = CloudBackupEnvelope(
            schemaVersion: 2,
            savedAt: Date(),
            deviceName: ProcessInfo.processInfo.processName,
            state: state
        )
        guard let data = try? encoder.encode(envelope),
              let json = String(data: data, encoding: .utf8) else {
            return false
        }
        let cloudStore = NSUbiquitousKeyValueStore.default
        cloudStore.set(json, forKey: cloudBackupKey)
        return cloudStore.synchronize()
    }

    func iCloudBackupPreview() -> ImportPreview? {
        guard let data = iCloudBackupData() else { return nil }
        return importPreview(from: data)
    }

    @discardableResult
    func restoreFromICloud() -> Bool {
        guard let data = iCloudBackupData() else {
            return false
        }
        return importStateData(data)
    }

    private func updateKid(_ id: UUID, mutate: (inout Kid) -> Void) {
        guard let index = state.kids.firstIndex(where: { $0.id == id }) else { return }
        mutate(&state.kids[index])
    }

    private func updateTaskCompletion(_ task: RewardTask, for kid: Kid, at date: Date) {
        guard task.recurrence != .none else { return }
        if let index = state.taskCompletions.firstIndex(where: { $0.taskID == task.id && $0.kidID == kid.id }) {
            state.taskCompletions[index].lastAwardedAt = date
        } else {
            state.taskCompletions.append(TaskCompletion(kidID: kid.id, taskID: task.id, lastAwardedAt: date))
        }
    }

    private func taskCompletion(for task: RewardTask, kid: Kid) -> TaskCompletion? {
        state.taskCompletions.first { $0.taskID == task.id && $0.kidID == kid.id }
    }

    private func isDue(since date: Date, recurrence: RewardTask.Recurrence, now: Date) -> Bool {
        switch recurrence {
        case .none:
            return true
        case .daily:
            return Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0 >= 1
        case .weekly:
            return Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0 >= 7
        }
    }

    private func migrateLegacyParentPINIfNeeded() {
        guard let legacyPIN = state.settings.legacyParentPIN, !legacyPIN.isEmpty else { return }
        pinManager.save(pin: legacyPIN)
        state.settings.legacyParentPIN = nil
        save()
    }

    private func normalizedCorrectionPoints(_ points: Int, for kind: RewardTransaction.Kind) -> Int {
        switch kind {
        case .adjusted:
            return points
        case .earned, .deposited, .cashedOut, .interest:
            return abs(points)
        }
    }

    private func apply(_ transaction: RewardTransaction, to kid: inout Kid, multiplier: Int) -> Bool {
        var nextAvailable = kid.availablePoints
        var nextVault = kid.vaultPoints

        switch transaction.kind {
        case .earned:
            nextAvailable += multiplier * transaction.points
        case .deposited:
            nextAvailable -= multiplier * transaction.points
            nextVault += multiplier * transaction.points
        case .cashedOut:
            nextAvailable -= multiplier * transaction.points
        case .interest:
            nextVault += multiplier * transaction.points
        case .adjusted:
            nextAvailable += multiplier * transaction.points
        }

        guard nextAvailable >= 0, nextVault >= 0 else { return false }
        kid.availablePoints = nextAvailable
        kid.vaultPoints = nextVault
        return true
    }

    private func addTransaction(
        kidID: UUID,
        kind: RewardTransaction.Kind,
        points: Int,
        note: String,
        currencyAmount: Decimal?
    ) {
        state.transactions.append(
            RewardTransaction(
                kidID: kidID,
                kind: kind,
                points: points,
                note: note,
                date: Date(),
                currencyAmount: currencyAmount
            )
        )
    }

    private func addApprovalRequest(
        kidID: UUID,
        kind: ApprovalRequest.Kind,
        points: Int,
        note: String
    ) {
        state.approvalRequests.removeAll { existing in
            existing.kidID == kidID && existing.kind == kind
        }
        state.approvalRequests.append(
            ApprovalRequest(
                kidID: kidID,
                kind: kind,
                points: points,
                note: note,
                date: Date()
            )
        )
    }

    private func decodeImportData(_ data: Data) -> (state: RewardState, savedAt: Date?, deviceName: String?, isCloudBackup: Bool)? {
        if let envelope = try? decoder.decode(CloudBackupEnvelope.self, from: data) {
            return (envelope.state, envelope.savedAt, envelope.deviceName, true)
        }
        if let state = try? decoder.decode(RewardState.self, from: data) {
            return (state, nil, nil, false)
        }
        return nil
    }

    private func iCloudBackupData() -> Data? {
        let cloudStore = NSUbiquitousKeyValueStore.default
        if let json = cloudStore.string(forKey: cloudBackupKey),
           let data = json.data(using: .utf8) {
            return data
        }
        guard let legacyJSON = cloudStore.string(forKey: legacyCloudBackupKey) else { return nil }
        return legacyJSON.data(using: .utf8)
    }

    private func cashOutExact(points: Int, for kid: Kid) -> Bool {
        guard points > 0 else { return false }
        var didCashOut = false
        updateKid(kid.id) { current in
            guard current.availablePoints >= points else { return }
            current.availablePoints -= points
            addTransaction(
                kidID: kid.id,
                kind: .cashedOut,
                points: points,
                note: "Cash out",
                currencyAmount: Decimal(points) * state.settings.currencyPerPoint
            )
            didCashOut = true
        }
        if didCashOut {
            save()
        }
        return didCashOut
    }

    @discardableResult
    private func save() -> Bool {
        do {
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: [.atomic])
            persistenceErrorMessage = nil
            return true
        } catch {
            persistenceErrorMessage = error.localizedDescription
            return false
        }
    }
}
