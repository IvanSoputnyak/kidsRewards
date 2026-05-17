import Foundation

@MainActor
final class RewardStore: ObservableObject {
    @Published private(set) var state: RewardState

    private let fileURL: URL
    private let pinManager: ParentPINManaging
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
        } else {
            state = initialState
            migrateLegacyParentPINIfNeeded()
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

    func award(task: RewardTask, to kid: Kid) {
        updateKid(kid.id) { $0.availablePoints += task.points }
        addTransaction(
            kidID: kid.id,
            kind: .earned,
            points: task.points,
            note: task.title,
            currencyAmount: nil
        )
        save()
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

    func cashOut(points: Int, for kid: Kid) {
        guard points > 0 else { return }
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
        }
        save()
    }

    func requestCashOut(points: Int, for kid: Kid) {
        guard points > 0 else { return }
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

    func applyInterest(to kid: Kid) {
        updateKid(kid.id) { current in
            let interest = (Decimal(current.vaultPoints) * state.settings.vaultInterestRate)
            let rounded = NSDecimalNumber(decimal: interest).rounding(accordingToBehavior: nil).intValue
            guard rounded > 0 else { return }
            current.vaultPoints += rounded
            addTransaction(
                kidID: kid.id,
                kind: .interest,
                points: rounded,
                note: "Vault interest",
                currencyAmount: nil
            )
        }
        save()
    }

    func requestInterest(for kid: Kid) {
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

    func updateSettings(currencyCode: String, currencyPerPoint: Decimal, vaultInterestRate: Decimal, allowancePoints: Int? = nil) {
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
            allowancePoints: max(allowancePoints ?? state.settings.allowancePoints, 0)
        )
        save()
    }

    func applyAllowanceToAllKids() {
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
        save()
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

        switch currentRequest.kind {
        case .cashOut:
            cashOut(points: currentRequest.points, for: kid)
        case .interest:
            applyInterest(to: kid)
        }

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

    @discardableResult
    func importStateData(_ data: Data) -> Bool {
        guard let decoded = try? decoder.decode(RewardState.self, from: data) else { return false }
        state = decoded
        migrateLegacyParentPINIfNeeded()
        save()
        return true
    }

    func syncToICloud() {
        guard let data = exportStateData(),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        let cloudStore = NSUbiquitousKeyValueStore.default
        cloudStore.set(json, forKey: "kidsRewardsState")
        cloudStore.synchronize()
    }

    @discardableResult
    func restoreFromICloud() -> Bool {
        let cloudStore = NSUbiquitousKeyValueStore.default
        guard let json = cloudStore.string(forKey: "kidsRewardsState"),
              let data = json.data(using: .utf8) else {
            return false
        }
        return importStateData(data)
    }

    private func updateKid(_ id: UUID, mutate: (inout Kid) -> Void) {
        guard let index = state.kids.firstIndex(where: { $0.id == id }) else { return }
        mutate(&state.kids[index])
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

    private func save() {
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
