import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class RewardStore: ObservableObject {
    @Published private(set) var state: RewardState
    @Published private(set) var persistenceErrorMessage: String?
    @Published private(set) var hasParentPIN: Bool
    @Published private(set) var parentPINLockoutUntil: Date?

    static let parentPINMaxFailedAttempts = 5
    static let parentPINLockoutDuration: TimeInterval = 60

    private var parentPINFailedAttempts = 0

    private let fileURL: URL
    private let pinManager: ParentPINManaging
    private let cloudBackupKey = "kidsRewardsState.v2"
    private let legacyCloudBackupKey = "kidsRewardsState"
    private let lastLocalSaveKey = "kidsRewards.lastSavedAt"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var iCloudObserver: NSObjectProtocol?
    /// Injected backup for unit tests when `NSUbiquitousKeyValueStore` is unavailable.
    var debugICloudBackupData: Data?

    init(
        initialState: RewardState = .empty,
        fileURL: URL? = nil,
        pinManager: ParentPINManaging = KeychainParentPINManager()
    ) {
        self.pinManager = pinManager
        self.hasParentPIN = pinManager.hasPIN
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.fileURL = documents.appendingPathComponent("kids-rewards-state.json")
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        if initialState == .empty,
           let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? decoder.decode(RewardState.self, from: data) {
            state = decoded
            migrateLegacyParentPINIfNeeded()
            runScheduledMaintenance()
        } else {
            state = initialState
            migrateLegacyParentPINIfNeeded()
            runScheduledMaintenance()
            save()
        }
        disableICloudBackupIfUnavailable()
        registerICloudObserverIfNeeded()
    }

    deinit {
        if let iCloudObserver {
            NotificationCenter.default.removeObserver(iCloudObserver)
        }
    }

    var totalAvailablePoints: Int {
        state.kids.reduce(0) { $0 + $1.availablePoints }
    }

    var totalVaultPoints: Int {
        state.kids.reduce(0) { $0 + $1.vaultPoints }
    }

    var totalHouseholdPoints: Int {
        totalAvailablePoints + totalVaultPoints
    }

    func kid(withID id: UUID) -> Kid? {
        state.kids.first { $0.id == id }
    }

    func kidName(for id: UUID) -> String {
        kid(withID: id)?.name ?? "Unknown"
    }

    func isAllowanceScheduleDue(now: Date = Date()) -> Bool {
        let recurrence = state.settings.allowanceRecurrence
        guard recurrence != .none,
              !state.kids.isEmpty,
              state.kids.contains(where: { allowancePoints(for: $0) > 0 }) else {
            return false
        }
        if let lastApplied = state.settings.lastAllowanceAppliedAt,
           !isDue(since: lastApplied, recurrence: recurrence, now: now) {
            return false
        }
        return true
    }

    func isInterestScheduleDue(now: Date = Date()) -> Bool {
        let recurrence = state.settings.interestRecurrence
        guard recurrence != .none,
              state.kids.contains(where: { interestPoints(for: $0) > 0 }) else {
            return false
        }
        if let lastApplied = state.settings.lastInterestAppliedAt,
           !isDue(since: lastApplied, recurrence: recurrence, now: now) {
            return false
        }
        return true
    }

    func readyChoreCount(for kid: Kid, now: Date = Date()) -> Int {
        tasks(for: kid).filter { isTaskAvailable($0, for: kid, now: now) }.count
    }

    func totalReadyChoreCount(now: Date = Date()) -> Int {
        state.kids.reduce(0) { $0 + readyChoreCount(for: $1, now: now) }
    }

    func firstKidWithReadyChores(now: Date = Date()) -> Kid? {
        state.kids.first { readyChoreCount(for: $0, now: now) > 0 }
    }

    func firstKidEligibleForVaultInterest() -> Kid? {
        state.kids.first { interestPoints(for: $0) > 0 }
    }

    func pendingRequestCount(for kid: Kid) -> Int {
        state.approvalRequests.filter { $0.kidID == kid.id }.count
    }

    func recentTransactions(limit: Int = 8, now: Date = Date()) -> [RewardTransaction] {
        let capped = max(limit, 0)
        guard capped > 0 else { return [] }
        return Array(
            state.transactions
                .sorted { $0.date > $1.date }
                .prefix(capped)
        )
    }

    func earnedPoints(in interval: DateInterval) -> Int {
        state.transactions.reduce(into: 0) { total, transaction in
            guard transaction.kind == .earned,
                  interval.contains(transaction.date) else {
                return
            }
            total += transaction.points
        }
    }

    func earnedPointsThisWeek(now: Date = Date()) -> Int {
        let calendar = Calendar.current
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
            return 0
        }
        return earnedPoints(in: DateInterval(start: weekStart, end: now))
    }

    func lastTransaction(for kid: Kid) -> RewardTransaction? {
        transactions(for: kid).first
    }

    func lastActivitySummary(for kid: Kid) -> String? {
        guard let transaction = lastTransaction(for: kid) else { return nil }
        let relative = transaction.date.formatted(.relative(presentation: .named))
        return "\(transaction.note) · \(relative)"
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

    func allowancePoints(for kid: Kid) -> Int {
        max(kid.allowancePoints ?? state.settings.allowancePoints, 0)
    }

    func updateKidAllowancePoints(_ kid: Kid, points: Int?) {
        updateKid(kid.id) {
            if let points {
                $0.allowancePoints = max(points, 0)
            } else {
                $0.allowancePoints = nil
            }
        }
        save()
    }

    func savingsGoalProgress(for kid: Kid) -> Int {
        guard let goal = kid.savingsGoal else { return kid.totalPoints }
        return kid.savingsGoalProgress(toward: goal)
    }

    var isParentPINLockedOut: Bool {
        guard let parentPINLockoutUntil else { return false }
        return parentPINLockoutUntil > Date()
    }

    func parentPINLockoutRemainingSeconds(now: Date = Date()) -> Int {
        guard let parentPINLockoutUntil, parentPINLockoutUntil > now else { return 0 }
        return Int(ceil(parentPINLockoutUntil.timeIntervalSince(now)))
    }

    func deleteKid(_ kid: Kid) {
        state.kids.removeAll { $0.id == kid.id }
        state.transactions.removeAll { $0.kidID == kid.id }
        state.approvalRequests.removeAll { $0.kidID == kid.id }
        state.taskCompletions.removeAll { $0.kidID == kid.id }
        for index in state.tasks.indices {
            state.tasks[index].assignedKidIDs.removeAll { $0 == kid.id }
        }
        save()
    }

    func addTask(
        title: String,
        points: Int,
        recurrence: RewardTask.Recurrence = .none,
        assignedKidIDs: [UUID] = []
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, points > 0 else { return }
        state.tasks.append(
            RewardTask(
                title: trimmed,
                points: points,
                recurrence: recurrence,
                assignedKidIDs: assignedKidIDs
            )
        )
        save()
    }

    func updateTask(
        _ task: RewardTask,
        title: String,
        points: Int,
        recurrence: RewardTask.Recurrence? = nil,
        assignedKidIDs: [UUID]? = nil
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, points > 0 else { return }
        guard let index = state.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        state.tasks[index].title = trimmed
        state.tasks[index].points = points
        if let recurrence {
            state.tasks[index].recurrence = recurrence
        }
        if let assignedKidIDs {
            state.tasks[index].assignedKidIDs = assignedKidIDs
        }
        save()
    }

    func tasks(for kid: Kid) -> [RewardTask] {
        state.tasks.filter { $0.isAssigned(to: kid.id) }
    }

    func deleteTask(_ task: RewardTask) {
        state.tasks.removeAll { $0.id == task.id }
        state.taskCompletions.removeAll { $0.taskID == task.id }
        save()
    }

    func award(task: RewardTask, to kid: Kid, at date: Date = Date()) {
        guard task.isAssigned(to: kid.id), isTaskAvailable(task, for: kid, now: date) else { return }
        updateKid(kid.id) { $0.availablePoints += task.points }
        addTransaction(
            kidID: kid.id,
            kind: .earned,
            points: task.points,
            note: task.title,
            currencyAmount: nil,
            date: date
        )
        updateTaskCompletion(task, for: kid, at: date)
        save()
    }

    func isTaskAvailable(_ task: RewardTask, for kid: Kid, now: Date = Date()) -> Bool {
        guard task.isAssigned(to: kid.id) else { return false }
        guard let completion = taskCompletion(for: task, kid: kid) else {
            return true
        }
        guard task.recurrence != .none else {
            return false
        }
        return isDue(since: completion.lastAwardedAt, recurrence: task.recurrence, now: now)
    }

    func withdraw(points: Int, for kid: Kid) {
        guard points > 0 else { return }
        var withdrawnAmount = 0
        updateKid(kid.id) { current in
            let amount = min(points, current.vaultPoints)
            guard amount > 0 else { return }
            withdrawnAmount = amount
            current.vaultPoints -= amount
            current.availablePoints += amount
        }
        guard withdrawnAmount > 0 else { return }
        addTransaction(
            kidID: kid.id,
            kind: .withdrawn,
            points: withdrawnAmount,
            note: "Vault withdrawal",
            currencyAmount: nil
        )
        save()
    }

    @discardableResult
    func deposit(points: Int, for kid: Kid) -> Bool {
        guard points > 0 else { return false }
        if state.settings.approvalFlowEnabled {
            requestDeposit(points: points, for: kid)
            return min(points, kid.availablePoints) > 0
        }
        var depositedAmount = 0
        updateKid(kid.id) { current in
            let amount = min(points, current.availablePoints)
            guard amount > 0 else { return }
            depositedAmount = amount
            current.availablePoints -= amount
            current.vaultPoints += amount
        }
        guard depositedAmount > 0 else { return false }
        addTransaction(
            kidID: kid.id,
            kind: .deposited,
            points: depositedAmount,
            note: "Vault deposit",
            currencyAmount: nil
        )
        save()
        return true
    }

    @discardableResult
    func cashOut(points: Int, for kid: Kid) -> Bool {
        guard points > 0 else { return false }
        var cashedOutAmount = 0
        updateKid(kid.id) { current in
            let amount = min(points, current.availablePoints)
            guard amount > 0 else { return }
            cashedOutAmount = amount
            current.availablePoints -= amount
        }
        guard cashedOutAmount > 0 else { return false }
        addTransaction(
            kidID: kid.id,
            kind: .cashedOut,
            points: cashedOutAmount,
            note: "Cash out",
            currencyAmount: Decimal(cashedOutAmount) * state.settings.currencyPerPoint
        )
        save()
        return true
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
    private func applyInterest(points: Int, to kid: Kid, persist: Bool = true) -> Bool {
        guard points > 0 else { return false }
        var didApplyInterest = false
        updateKid(kid.id) { current in
            current.vaultPoints += points
            didApplyInterest = true
        }
        guard didApplyInterest else { return false }
        addTransaction(
            kidID: kid.id,
            kind: .interest,
            points: points,
            note: "Vault interest",
            currencyAmount: nil
        )
        if persist {
            save()
        }
        return true
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

    func requestChoreCompletion(task: RewardTask, for kid: Kid) {
        guard state.settings.approvalFlowEnabled,
              task.isAssigned(to: kid.id),
              isTaskAvailable(task, for: kid) else {
            return
        }
        addApprovalRequest(
            kidID: kid.id,
            kind: .choreCompleted,
            points: task.points,
            note: "Chore: \(task.title)",
            taskID: task.id
        )
        save()
    }

    func requestDeposit(points: Int, for kid: Kid) {
        guard state.settings.approvalFlowEnabled, points > 0 else { return }
        let amount = min(points, kid.availablePoints)
        guard amount > 0 else { return }
        addApprovalRequest(
            kidID: kid.id,
            kind: .vaultDeposit,
            points: amount,
            note: "Vault deposit request"
        )
        save()
    }

    func pendingApprovalRequest(
        kind: ApprovalRequest.Kind,
        kidID: UUID,
        taskID: UUID? = nil
    ) -> ApprovalRequest? {
        state.approvalRequests.first { request in
            guard request.kidID == kidID, request.kind == kind else { return false }
            if let taskID {
                return request.taskID == taskID
            }
            return request.taskID == nil
        }
    }

    func interestPoints(for kid: Kid) -> Int {
        let interest = Decimal(kid.vaultPoints) * state.settings.vaultInterestRate
        return NSDecimalNumber(decimal: interest).rounding(accordingToBehavior: nil).intValue
    }

    func adjust(points requestedPoints: Int, note: String, for kid: Kid) {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard requestedPoints != 0 else { return }

        var appliedPoints = 0
        updateKid(kid.id) { current in
            let points = requestedPoints < 0
                ? -min(abs(requestedPoints), current.availablePoints)
                : requestedPoints
            guard points != 0 else { return }
            appliedPoints = points
            current.availablePoints += points
        }
        guard appliedPoints != 0 else { return }
        addTransaction(
            kidID: kid.id,
            kind: .adjusted,
            points: appliedPoints,
            note: trimmedNote.isEmpty ? "Manual adjustment" : trimmedNote,
            currencyAmount: nil
        )
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
        allowanceRecurrence: RewardTask.Recurrence? = nil,
        interestRecurrence: RewardTask.Recurrence? = nil,
        notificationsEnabled: Bool? = nil,
        iCloudAutoSyncEnabled: Bool? = nil
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
            lastAllowanceAppliedAt: state.settings.lastAllowanceAppliedAt,
            interestRecurrence: interestRecurrence ?? state.settings.interestRecurrence,
            lastInterestAppliedAt: state.settings.lastInterestAppliedAt,
            notificationsEnabled: notificationsEnabled ?? state.settings.notificationsEnabled,
            iCloudAutoSyncEnabled: iCloudAutoSyncEnabled ?? state.settings.iCloudAutoSyncEnabled
        )
        save()
        RewardNotifications.reschedule(using: self)
    }

    func applyAllowanceToAllKids(at date: Date = Date()) {
        guard !state.kids.isEmpty else { return }

        if state.settings.approvalFlowEnabled {
            var queuedAny = false
            for kid in state.kids where allowancePoints(for: kid) > 0 {
                if requestAllowance(points: allowancePoints(for: kid), for: kid) {
                    queuedAny = true
                }
            }
            guard queuedAny else { return }
            save()
            return
        }

        for index in state.kids.indices {
            let points = allowancePoints(for: state.kids[index])
            guard points > 0 else { continue }
            applyAllowancePoints(points, toKidAt: index, date: date)
        }
        recordAllowanceScheduleApplied(at: date)
        save()
    }

    func applyAllowance(to kid: Kid, at date: Date = Date()) {
        let points = allowancePoints(for: kid)
        guard points > 0,
              let index = state.kids.firstIndex(where: { $0.id == kid.id }) else {
            return
        }
        if state.settings.approvalFlowEnabled {
            if requestAllowance(points: points, for: kid) {
                save()
            }
            return
        }
        applyAllowancePoints(points, toKidAt: index, date: date)
        save()
    }

    @discardableResult
    func requestAllowance(points: Int, for kid: Kid) -> Bool {
        guard state.settings.approvalFlowEnabled else { return false }
        let amount = max(points, 0)
        guard amount > 0 else { return false }
        addApprovalRequest(
            kidID: kid.id,
            kind: .allowance,
            points: amount,
            note: "Allowance request"
        )
        save()
        return true
    }

    private func applyAllowancePoints(_ points: Int, toKidAt index: Int, date: Date) {
        state.kids[index].availablePoints += points
        addTransaction(
            kidID: state.kids[index].id,
            kind: .earned,
            points: points,
            note: "Allowance",
            currencyAmount: nil,
            date: date
        )
    }

    @discardableResult
    func applyDueAllowanceIfNeeded(now: Date = Date()) -> Bool {
        let recurrence = state.settings.allowanceRecurrence
        guard recurrence != .none,
              !state.kids.isEmpty,
              state.kids.contains(where: { allowancePoints(for: $0) > 0 }) else {
            return false
        }
        if let lastApplied = state.settings.lastAllowanceAppliedAt,
           !isDue(since: lastApplied, recurrence: recurrence, now: now) {
            return false
        }

        if state.settings.approvalFlowEnabled {
            var queuedAny = false
            for kid in state.kids {
                let points = allowancePoints(for: kid)
                guard points > 0 else { continue }
                if pendingApprovalRequest(kind: .allowance, kidID: kid.id) != nil {
                    continue
                }
                if requestAllowance(points: points, for: kid) {
                    queuedAny = true
                }
            }
            guard queuedAny else { return false }
            save()
            RewardNotifications.reschedule(using: self)
            return true
        }

        applyAllowanceToAllKids(at: now)
        RewardNotifications.reschedule(using: self)
        return true
    }

    @discardableResult
    func applyDueInterestIfNeeded(now: Date = Date()) -> Bool {
        let recurrence = state.settings.interestRecurrence
        guard recurrence != .none, !state.kids.isEmpty else { return false }
        if let lastApplied = state.settings.lastInterestAppliedAt,
           !isDue(since: lastApplied, recurrence: recurrence, now: now) {
            return false
        }

        var appliedAny = false
        for kid in state.kids {
            let points = interestPoints(for: kid)
            if applyInterest(points: points, to: kid, persist: false) {
                appliedAny = true
            }
        }
        guard appliedAny else { return false }

        state.settings.lastInterestAppliedAt = now
        save()
        RewardNotifications.reschedule(using: self)
        return true
    }

    func runScheduledMaintenance(now: Date = Date()) {
        _ = applyDueAllowanceIfNeeded(now: now)
        _ = applyDueInterestIfNeeded(now: now)
        if ICloudBackup.isAvailable, state.settings.iCloudAutoSyncEnabled {
            _ = pullFromICloudIfNewer()
        }
        RewardNotifications.reschedule(using: self)
    }

    func setNotificationsEnabled(_ isEnabled: Bool) {
        state.settings.notificationsEnabled = isEnabled
        save()
        RewardNotifications.reschedule(using: self)
    }

    func setICloudAutoSyncEnabled(_ isEnabled: Bool) {
        guard ICloudBackup.isAvailable else {
            disableICloudBackupIfUnavailable()
            return
        }
        state.settings.iCloudAutoSyncEnabled = isEnabled
        save()
        if isEnabled {
            _ = syncToICloud()
        }
    }

    func setInterestRecurrence(_ recurrence: RewardTask.Recurrence) {
        state.settings.interestRecurrence = recurrence
        save()
        RewardNotifications.reschedule(using: self)
    }

    @discardableResult
    func updateParentPIN(_ pin: String) async -> Bool {
        let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        let pinManager = pinManager
        let didUpdate: Bool
        if trimmed.isEmpty {
            didUpdate = await Task.detached(priority: .userInitiated) {
                pinManager.clear()
            }.value
            if didUpdate {
                hasParentPIN = false
            }
        } else {
            let normalizedPIN = String(trimmed.prefix(12))
            didUpdate = await Task.detached(priority: .userInitiated) {
                pinManager.save(pin: normalizedPIN)
            }.value
            if didUpdate {
                hasParentPIN = true
            }
        }
        if didUpdate {
            clearParentPINLockout()
            save()
        } else {
            persistenceErrorMessage = "Could not update parent PIN."
        }
        return didUpdate
    }

    func verifyParentPIN(_ pin: String, now: Date = Date()) async -> Bool {
        if isParentPINLockedOut(at: now) {
            return false
        }
        clearExpiredParentPINLockout(now: now)

        let pinManager = pinManager
        let isValid = await Task.detached(priority: .userInitiated) {
            pinManager.verify(pin: pin)
        }.value

        if isValid {
            clearParentPINLockout()
            return true
        }

        guard hasParentPIN else { return false }

        parentPINFailedAttempts += 1
        if parentPINFailedAttempts >= Self.parentPINMaxFailedAttempts {
            parentPINLockoutUntil = now.addingTimeInterval(Self.parentPINLockoutDuration)
            parentPINFailedAttempts = 0
        }
        return false
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
        case .choreCompleted:
            guard let taskID = currentRequest.taskID,
                  let task = state.tasks.first(where: { $0.id == taskID }) else {
                return false
            }
            let previousTransactionCount = state.transactions.count
            award(task: task, to: kid)
            didApply = state.transactions.count > previousTransactionCount
        case .vaultDeposit:
            didApply = depositExact(points: currentRequest.points, for: kid)
        case .allowance:
            guard let index = state.kids.firstIndex(where: { $0.id == kid.id }) else {
                return false
            }
            applyAllowancePoints(currentRequest.points, toKidAt: index, date: Date())
            recordAllowanceScheduleApplied()
            didApply = true
        }
        guard didApply else { return false }

        state.approvalRequests.removeAll { $0.id == currentRequest.id }
        save()
        RewardNotifications.reschedule(using: self)
        return true
    }

    func declineRequest(_ request: ApprovalRequest) {
        state.approvalRequests.removeAll { $0.id == request.id }
        save()
        RewardNotifications.reschedule(using: self)
    }

    var pendingApprovalCount: Int {
        state.approvalRequests.count
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
        var importedState = decoded
        let legacyPIN = importedState.settings.legacyParentPIN?.isEmpty == false
            ? importedState.settings.legacyParentPIN
            : nil
        importedState.settings.legacyParentPIN = nil

        let previousState = state
        let previousHasParentPIN = hasParentPIN
        state = importedState
        guard save() else {
            state = previousState
            hasParentPIN = previousHasParentPIN
            return false
        }
        if let legacyPIN {
            guard pinManager.save(pin: legacyPIN) else {
                state = previousState
                hasParentPIN = previousHasParentPIN
                save()
                return false
            }
            hasParentPIN = true
        }
        return true
    }

    @discardableResult
    func pullFromICloudIfNewer() -> Bool {
        guard ICloudBackup.isAvailable,
              state.settings.iCloudAutoSyncEnabled,
              let data = iCloudBackupData(),
              let decoded = decodeImportData(data),
              decoded.isCloudBackup,
              let cloudSavedAt = decoded.savedAt else {
            return false
        }
        if let localSavedAt = UserDefaults.standard.object(forKey: lastLocalSaveKey) as? Date,
           localSavedAt >= cloudSavedAt {
            return false
        }
        return importStateData(data)
    }

    @discardableResult
    func syncToICloud() -> Bool {
        guard ICloudBackup.isAvailable else { return false }
        let envelope = CloudBackupEnvelope(
            schemaVersion: 3,
            savedAt: Date(),
            deviceName: Self.currentDeviceName,
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
        guard ICloudBackup.isAvailable, let data = iCloudBackupData() else { return nil }
        return importPreview(from: data)
    }

    @discardableResult
    func restoreFromICloud() -> Bool {
        guard ICloudBackup.isAvailable, let data = iCloudBackupData() else {
            return false
        }
        return importStateData(data)
    }

    private func updateKid(_ id: UUID, mutate: (inout Kid) -> Void) {
        guard let index = state.kids.firstIndex(where: { $0.id == id }) else { return }
        mutate(&state.kids[index])
    }

    private func updateTaskCompletion(_ task: RewardTask, for kid: Kid, at date: Date) {
        if let index = state.taskCompletions.firstIndex(where: { $0.taskID == task.id && $0.kidID == kid.id }) {
            state.taskCompletions[index].lastAwardedAt = date
        } else {
            state.taskCompletions.append(TaskCompletion(kidID: kid.id, taskID: task.id, lastAwardedAt: date))
        }
    }

    private func recordAllowanceScheduleApplied(at date: Date = Date()) {
        guard state.settings.allowanceRecurrence != .none else { return }
        state.settings.lastAllowanceAppliedAt = date
    }

    private func taskCompletion(for task: RewardTask, kid: Kid) -> TaskCompletion? {
        state.taskCompletions.first { $0.taskID == task.id && $0.kidID == kid.id }
    }

    private func isDue(since date: Date, recurrence: RewardTask.Recurrence, now: Date) -> Bool {
        RecurrenceSchedule.isDue(since: date, recurrence: recurrence, now: now)
    }

    private func isParentPINLockedOut(at now: Date) -> Bool {
        guard let parentPINLockoutUntil else { return false }
        return parentPINLockoutUntil > now
    }

    private func clearExpiredParentPINLockout(now: Date = Date()) {
        guard let parentPINLockoutUntil, parentPINLockoutUntil <= now else { return }
        clearParentPINLockout()
    }

    private func clearParentPINLockout() {
        parentPINFailedAttempts = 0
        parentPINLockoutUntil = nil
    }

    @discardableResult
    private func depositExact(points: Int, for kid: Kid) -> Bool {
        guard points > 0 else { return false }
        var depositedAmount = 0
        updateKid(kid.id) { current in
            let amount = min(points, current.availablePoints)
            guard amount > 0 else { return }
            depositedAmount = amount
            current.availablePoints -= amount
            current.vaultPoints += amount
        }
        guard depositedAmount > 0 else { return false }
        addTransaction(
            kidID: kid.id,
            kind: .deposited,
            points: depositedAmount,
            note: "Vault deposit",
            currencyAmount: nil
        )
        save()
        return true
    }

    private func migrateLegacyParentPINIfNeeded() {
        guard let legacyPIN = state.settings.legacyParentPIN, !legacyPIN.isEmpty else { return }
        guard pinManager.save(pin: legacyPIN) else {
            persistenceErrorMessage = "Could not migrate parent PIN."
            return
        }
        hasParentPIN = true
        state.settings.legacyParentPIN = nil
        save()
    }

    private func normalizedCorrectionPoints(_ points: Int, for kind: RewardTransaction.Kind) -> Int {
        switch kind {
        case .adjusted:
            return points
        case .earned, .deposited, .withdrawn, .cashedOut, .interest:
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
        case .withdrawn:
            nextAvailable += multiplier * transaction.points
            nextVault -= multiplier * transaction.points
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
        currencyAmount: Decimal?,
        date: Date = Date()
    ) {
        state.transactions.append(
            RewardTransaction(
                kidID: kidID,
                kind: kind,
                points: points,
                note: note,
                date: date,
                currencyAmount: currencyAmount
            )
        )
    }

    private func addApprovalRequest(
        kidID: UUID,
        kind: ApprovalRequest.Kind,
        points: Int,
        note: String,
        taskID: UUID? = nil
    ) {
        state.approvalRequests.removeAll { existing in
            guard existing.kidID == kidID, existing.kind == kind else { return false }
            if let taskID {
                return existing.taskID == taskID
            }
            return existing.taskID == nil
        }
        state.approvalRequests.append(
            ApprovalRequest(
                kidID: kidID,
                kind: kind,
                points: points,
                note: note,
                taskID: taskID
            )
        )
        RewardNotifications.reschedule(using: self)
    }

    private func disableICloudBackupIfUnavailable() {
        guard !ICloudBackup.isAvailable, state.settings.iCloudAutoSyncEnabled else { return }
        state.settings.iCloudAutoSyncEnabled = false
        save()
    }

    private func registerICloudObserverIfNeeded() {
        guard ICloudBackup.isAvailable, iCloudObserver == nil else { return }
        iCloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pullFromICloudIfNewer()
            }
        }
    }

    private static var currentDeviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return ProcessInfo.processInfo.hostName
        #endif
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
        if let debugICloudBackupData {
            return debugICloudBackupData
        }
        guard ICloudBackup.isAvailable else { return nil }
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
            didCashOut = true
        }
        guard didCashOut else { return false }
        addTransaction(
            kidID: kid.id,
            kind: .cashedOut,
            points: points,
            note: "Cash out",
            currencyAmount: Decimal(points) * state.settings.currencyPerPoint
        )
        save()
        return true
    }

    @discardableResult
    private func save() -> Bool {
        do {
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: [.atomic])
            persistenceErrorMessage = nil
            let savedAt = Date()
            UserDefaults.standard.set(savedAt, forKey: lastLocalSaveKey)
            if ICloudBackup.isAvailable, state.settings.iCloudAutoSyncEnabled {
                _ = syncToICloud()
            }
            RewardNotifications.reschedule(using: self)
            return true
        } catch {
            persistenceErrorMessage = error.localizedDescription
            return false
        }
    }
}
