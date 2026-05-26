import Foundation

struct Kid: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var availablePoints: Int
    var vaultPoints: Int
    /// Points deposited into the savings goal bucket.
    var goalPoints: Int
    var savingsGoal: SavingsGoal?
    /// When set, overrides the global allowance amount for this kid.
    var allowancePoints: Int?
    /// 0–100: percentage of each earn auto-moved to vault.
    var autoVaultPercent: Int
    /// 0–100: percentage of each earn auto-moved to goal.
    var autoGoalPercent: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case availablePoints
        case vaultPoints
        case goalPoints
        case savingsGoal
        case allowancePoints
        case autoVaultPercent
        case autoGoalPercent
    }

    init(
        id: UUID = UUID(),
        name: String,
        availablePoints: Int,
        vaultPoints: Int,
        goalPoints: Int = 0,
        savingsGoal: SavingsGoal? = nil,
        allowancePoints: Int? = nil,
        autoVaultPercent: Int = 0,
        autoGoalPercent: Int = 0
    ) {
        self.id = id
        self.name = name
        self.availablePoints = availablePoints
        self.vaultPoints = vaultPoints
        self.goalPoints = goalPoints
        self.savingsGoal = savingsGoal
        self.allowancePoints = allowancePoints
        self.autoVaultPercent = autoVaultPercent
        self.autoGoalPercent = autoGoalPercent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        availablePoints = try container.decode(Int.self, forKey: .availablePoints)
        vaultPoints = try container.decode(Int.self, forKey: .vaultPoints)
        goalPoints = try container.decodeIfPresent(Int.self, forKey: .goalPoints) ?? 0
        savingsGoal = try container.decodeIfPresent(SavingsGoal.self, forKey: .savingsGoal)
        allowancePoints = try container.decodeIfPresent(Int.self, forKey: .allowancePoints)
        autoVaultPercent = try container.decodeIfPresent(Int.self, forKey: .autoVaultPercent) ?? 0
        autoGoalPercent = try container.decodeIfPresent(Int.self, forKey: .autoGoalPercent) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(availablePoints, forKey: .availablePoints)
        try container.encode(vaultPoints, forKey: .vaultPoints)
        try container.encode(goalPoints, forKey: .goalPoints)
        try container.encodeIfPresent(savingsGoal, forKey: .savingsGoal)
        try container.encodeIfPresent(allowancePoints, forKey: .allowancePoints)
        try container.encode(autoVaultPercent, forKey: .autoVaultPercent)
        try container.encode(autoGoalPercent, forKey: .autoGoalPercent)
    }

    var totalPoints: Int {
        availablePoints + vaultPoints + goalPoints
    }

    func savingsGoalProgress(toward goal: SavingsGoal) -> Int {
        min(goalPoints, goal.targetPoints)
    }
}

struct SavingsGoal: Codable, Equatable, Hashable {
    var title: String
    var targetPoints: Int
}

struct RewardTask: Identifiable, Codable, Equatable, Hashable {
    enum Recurrence: String, Codable, CaseIterable {
        case none
        case daily
        case weekly
        case biweekly
        case monthly

        var label: String {
            switch self {
            case .none:     return "Off"
            case .daily:    return "Daily"
            case .weekly:   return "Weekly"
            case .biweekly: return "Biweekly"
            case .monthly:  return "Monthly"
            }
        }
    }

    var id = UUID()
    var title: String
    var points: Int
    var recurrence: Recurrence
    /// When empty or nil, the chore is available to every kid.
    var assignedKidIDs: [UUID]

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case points
        case recurrence
        case assignedKidIDs
    }

    init(
        id: UUID = UUID(),
        title: String,
        points: Int,
        recurrence: Recurrence = .none,
        assignedKidIDs: [UUID] = []
    ) {
        self.id = id
        self.title = title
        self.points = points
        self.recurrence = recurrence
        self.assignedKidIDs = assignedKidIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        points = try container.decode(Int.self, forKey: .points)
        recurrence = try container.decodeIfPresent(Recurrence.self, forKey: .recurrence) ?? .none
        assignedKidIDs = try container.decodeIfPresent([UUID].self, forKey: .assignedKidIDs) ?? []
    }

    func isAssigned(to kidID: UUID) -> Bool {
        assignedKidIDs.isEmpty || assignedKidIDs.contains(kidID)
    }
}

struct RewardSettings: Codable, Equatable {
    var currencyCode: String
    var currencyPerPoint: Decimal
    var vaultInterestRate: Decimal
    var approvalFlowEnabled: Bool
    var allowancePoints: Int
    var allowanceRecurrence: RewardTask.Recurrence
    var lastAllowanceAppliedAt: Date?
    /// Which day of the week allowance fires (1=Sun…7=Sat). Used for .weekly and .biweekly.
    var allowanceWeekday: Int?
    /// Which day of the month allowance fires (1–28). Used for .monthly.
    var allowanceMonthDay: Int?
    var interestRecurrence: RewardTask.Recurrence
    var lastInterestAppliedAt: Date?
    var notificationsEnabled: Bool
    var iCloudAutoSyncEnabled: Bool
    var legacyParentPIN: String?

    static let defaults = RewardSettings(
        currencyCode: "USD",
        currencyPerPoint: 1,
        vaultInterestRate: 0.05,
        approvalFlowEnabled: false,
        allowancePoints: 5,
        allowanceRecurrence: .none,
        lastAllowanceAppliedAt: nil,
        allowanceWeekday: nil,
        allowanceMonthDay: nil,
        interestRecurrence: .none,
        lastInterestAppliedAt: nil,
        notificationsEnabled: true,
        iCloudAutoSyncEnabled: false,
        legacyParentPIN: nil
    )

    private enum CodingKeys: String, CodingKey {
        case currencyCode
        case currencyPerPoint
        case vaultInterestRate
        case parentPIN
        case approvalFlowEnabled
        case allowancePoints
        case allowanceRecurrence
        case lastAllowanceAppliedAt
        case allowanceWeekday
        case allowanceMonthDay
        case interestRecurrence
        case lastInterestAppliedAt
        case notificationsEnabled
        case iCloudAutoSyncEnabled
    }

    init(
        currencyCode: String,
        currencyPerPoint: Decimal,
        vaultInterestRate: Decimal,
        approvalFlowEnabled: Bool = false,
        allowancePoints: Int = 5,
        allowanceRecurrence: RewardTask.Recurrence = .none,
        lastAllowanceAppliedAt: Date? = nil,
        allowanceWeekday: Int? = nil,
        allowanceMonthDay: Int? = nil,
        interestRecurrence: RewardTask.Recurrence = .none,
        lastInterestAppliedAt: Date? = nil,
        notificationsEnabled: Bool = true,
        iCloudAutoSyncEnabled: Bool = false,
        legacyParentPIN: String? = nil
    ) {
        self.currencyCode = currencyCode
        self.currencyPerPoint = currencyPerPoint
        self.vaultInterestRate = vaultInterestRate
        self.approvalFlowEnabled = approvalFlowEnabled
        self.allowancePoints = allowancePoints
        self.allowanceRecurrence = allowanceRecurrence
        self.lastAllowanceAppliedAt = lastAllowanceAppliedAt
        self.allowanceWeekday = allowanceWeekday
        self.allowanceMonthDay = allowanceMonthDay
        self.interestRecurrence = interestRecurrence
        self.lastInterestAppliedAt = lastInterestAppliedAt
        self.notificationsEnabled = notificationsEnabled
        self.iCloudAutoSyncEnabled = iCloudAutoSyncEnabled
        self.legacyParentPIN = legacyParentPIN
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currencyCode = try container.decode(String.self, forKey: .currencyCode)
        currencyPerPoint = try container.decode(Decimal.self, forKey: .currencyPerPoint)
        vaultInterestRate = try container.decode(Decimal.self, forKey: .vaultInterestRate)
        approvalFlowEnabled = try container.decodeIfPresent(Bool.self, forKey: .approvalFlowEnabled) ?? false
        allowancePoints = try container.decodeIfPresent(Int.self, forKey: .allowancePoints) ?? 5
        allowanceRecurrence = try container.decodeIfPresent(RewardTask.Recurrence.self, forKey: .allowanceRecurrence) ?? .none
        lastAllowanceAppliedAt = try container.decodeIfPresent(Date.self, forKey: .lastAllowanceAppliedAt)
        allowanceWeekday = try container.decodeIfPresent(Int.self, forKey: .allowanceWeekday)
        allowanceMonthDay = try container.decodeIfPresent(Int.self, forKey: .allowanceMonthDay)
        interestRecurrence = try container.decodeIfPresent(RewardTask.Recurrence.self, forKey: .interestRecurrence) ?? .none
        lastInterestAppliedAt = try container.decodeIfPresent(Date.self, forKey: .lastInterestAppliedAt)
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        iCloudAutoSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .iCloudAutoSyncEnabled) ?? false
        legacyParentPIN = try container.decodeIfPresent(String.self, forKey: .parentPIN)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(currencyPerPoint, forKey: .currencyPerPoint)
        try container.encode(vaultInterestRate, forKey: .vaultInterestRate)
        try container.encode(approvalFlowEnabled, forKey: .approvalFlowEnabled)
        try container.encode(allowancePoints, forKey: .allowancePoints)
        try container.encode(allowanceRecurrence, forKey: .allowanceRecurrence)
        try container.encodeIfPresent(lastAllowanceAppliedAt, forKey: .lastAllowanceAppliedAt)
        try container.encodeIfPresent(allowanceWeekday, forKey: .allowanceWeekday)
        try container.encodeIfPresent(allowanceMonthDay, forKey: .allowanceMonthDay)
        try container.encode(interestRecurrence, forKey: .interestRecurrence)
        try container.encodeIfPresent(lastInterestAppliedAt, forKey: .lastInterestAppliedAt)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(iCloudAutoSyncEnabled, forKey: .iCloudAutoSyncEnabled)
    }

    /// How many points equal one unit of currency (e.g. 10 means 10 points = $1).
    var pointsPerDollar: Decimal? {
        guard currencyPerPoint > 0 else { return nil }
        return Decimal(1) / currencyPerPoint
    }

    static func currencyPerPoint(pointsPerDollar: Decimal) -> Decimal? {
        guard pointsPerDollar > 0 else { return nil }
        return Decimal(1) / pointsPerDollar
    }
}

struct RewardTransaction: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case earned
        case deposited
        case withdrawn
        case cashedOut
        case interest
        case adjusted
        case goalDeposited
        case goalWithdrawn
        case goalCashedOut
        case goalInterest
    }

    var id = UUID()
    var kidID: UUID
    var kind: Kind
    var points: Int
    var note: String
    var date: Date
    var currencyAmount: Decimal?

    var pointsDisplayLabel: String {
        switch kind {
        case .cashedOut, .goalCashedOut:
            return "-\(points)"
        case .deposited, .goalDeposited:
            return "moved \(points)"
        case .withdrawn, .goalWithdrawn:
            return "+\(points)"
        case .adjusted:
            return points < 0 ? "\(points)" : "+\(points)"
        case .earned, .interest, .goalInterest:
            return "+\(points)"
        }
    }
}

struct ApprovalRequest: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case cashOut
        case interest
        case choreCompleted
        case vaultDeposit
        case allowance
        case goalDeposit
        case goalCashOut
    }

    var id = UUID()
    var kidID: UUID
    var kind: Kind
    var points: Int
    var note: String
    var date: Date
    var taskID: UUID?

    init(
        id: UUID = UUID(),
        kidID: UUID,
        kind: Kind,
        points: Int,
        note: String,
        date: Date = Date(),
        taskID: UUID? = nil
    ) {
        self.id = id
        self.kidID = kidID
        self.kind = kind
        self.points = points
        self.note = note
        self.date = date
        self.taskID = taskID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kidID = try container.decode(UUID.self, forKey: .kidID)
        kind = try container.decode(Kind.self, forKey: .kind)
        points = try container.decode(Int.self, forKey: .points)
        note = try container.decode(String.self, forKey: .note)
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        taskID = try container.decodeIfPresent(UUID.self, forKey: .taskID)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kidID
        case kind
        case points
        case note
        case date
        case taskID
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kidID, forKey: .kidID)
        try container.encode(kind, forKey: .kind)
        try container.encode(points, forKey: .points)
        try container.encode(note, forKey: .note)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(taskID, forKey: .taskID)
    }
}

struct TaskCompletion: Identifiable, Codable, Equatable {
    var id = UUID()
    var kidID: UUID
    var taskID: UUID
    var lastAwardedAt: Date
}

struct ImportPreview: Equatable {
    var kidsCount: Int
    var tasksCount: Int
    var transactionsCount: Int
    var approvalRequestsCount: Int
    var savedAt: Date?
    var deviceName: String?
    var isCloudBackup: Bool
}

struct CloudBackupEnvelope: Codable, Equatable {
    var schemaVersion: Int
    var savedAt: Date
    var deviceName: String
    var state: RewardState
}

struct RewardState: Codable, Equatable {
    var kids: [Kid]
    var tasks: [RewardTask]
    var settings: RewardSettings
    var transactions: [RewardTransaction]
    var approvalRequests: [ApprovalRequest]
    var taskCompletions: [TaskCompletion]

    private enum CodingKeys: String, CodingKey {
        case kids
        case tasks
        case settings
        case transactions
        case approvalRequests
        case taskCompletions
    }

    init(
        kids: [Kid],
        tasks: [RewardTask],
        settings: RewardSettings,
        transactions: [RewardTransaction],
        approvalRequests: [ApprovalRequest] = [],
        taskCompletions: [TaskCompletion] = []
    ) {
        self.kids = kids
        self.tasks = tasks
        self.settings = settings
        self.transactions = transactions
        self.approvalRequests = approvalRequests
        self.taskCompletions = taskCompletions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kids = try container.decode([Kid].self, forKey: .kids)
        tasks = try container.decode([RewardTask].self, forKey: .tasks)
        settings = try container.decode(RewardSettings.self, forKey: .settings)
        transactions = try container.decode([RewardTransaction].self, forKey: .transactions)
        approvalRequests = try container.decodeIfPresent([ApprovalRequest].self, forKey: .approvalRequests) ?? []
        taskCompletions = try container.decodeIfPresent([TaskCompletion].self, forKey: .taskCompletions) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kids, forKey: .kids)
        try container.encode(tasks, forKey: .tasks)
        try container.encode(settings, forKey: .settings)
        try container.encode(transactions, forKey: .transactions)
        try container.encode(approvalRequests, forKey: .approvalRequests)
        try container.encode(taskCompletions, forKey: .taskCompletions)
    }

    static let empty = RewardState(
        kids: [],
        tasks: [],
        settings: .defaults,
        transactions: [],
        approvalRequests: [],
        taskCompletions: []
    )

}

enum RecurrenceSchedule {
    static let calendarWeekFirstWeekday = 1

    static func configuredCalendar(from base: Calendar = .current) -> Calendar {
        var calendar = base
        calendar.firstWeekday = calendarWeekFirstWeekday
        return calendar
    }

    static func isDue(since lastOccurrence: Date, recurrence: RewardTask.Recurrence, now: Date, calendar: Calendar = .current) -> Bool {
        let calendar = configuredCalendar(from: calendar)
        switch recurrence {
        case .none:
            return true
        case .daily:
            return calendar.startOfDay(for: now) > calendar.startOfDay(for: lastOccurrence)
        case .weekly:
            return startOfWeek(for: now, calendar: calendar) > startOfWeek(for: lastOccurrence, calendar: calendar)
        case .biweekly:
            let lastWeekStart = startOfWeek(for: lastOccurrence, calendar: calendar)
            let nowWeekStart = startOfWeek(for: now, calendar: calendar)
            let days = calendar.dateComponents([.day], from: lastWeekStart, to: nowWeekStart).day ?? 0
            return days / 7 >= 2
        case .monthly:
            let lastComps = calendar.dateComponents([.year, .month], from: lastOccurrence)
            let nowComps = calendar.dateComponents([.year, .month], from: now)
            guard let lastStart = calendar.date(from: lastComps),
                  let nowStart = calendar.date(from: nowComps) else { return true }
            return nowStart > lastStart
        }
    }

    /// Allowance-specific due check that respects weekday (for .weekly/.biweekly) and monthDay (for .monthly).
    static func allowanceIsDue(
        since lastApplied: Date?,
        recurrence: RewardTask.Recurrence,
        weekday: Int?,
        monthDay: Int?,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let cal = configuredCalendar(from: calendar)
        guard let last = lastApplied else { return recurrence != .none }
        switch recurrence {
        case .none:
            return false
        case .daily:
            return isDue(since: last, recurrence: .daily, now: now, calendar: cal)
        case .weekly:
            if let weekday {
                return weeklyWeekdayIsDue(since: last, weekday: weekday, now: now, calendar: cal)
            }
            return isDue(since: last, recurrence: .weekly, now: now, calendar: cal)
        case .biweekly:
            if let weekday {
                return biweeklyWeekdayIsDue(since: last, weekday: weekday, now: now, calendar: cal)
            }
            return isDue(since: last, recurrence: .biweekly, now: now, calendar: cal)
        case .monthly:
            return monthlyDayIsDue(since: last, day: monthDay ?? 1, now: now, calendar: cal)
        }
    }

    private static func weeklyWeekdayIsDue(since lastApplied: Date, weekday: Int, now: Date, calendar: Calendar) -> Bool {
        guard startOfWeek(for: now, calendar: calendar) > startOfWeek(for: lastApplied, calendar: calendar) else {
            return false
        }
        return calendar.component(.weekday, from: now) >= weekday
    }

    private static func biweeklyWeekdayIsDue(since lastApplied: Date, weekday: Int, now: Date, calendar: Calendar) -> Bool {
        let lastWeekStart = startOfWeek(for: lastApplied, calendar: calendar)
        let nowWeekStart = startOfWeek(for: now, calendar: calendar)
        let days = calendar.dateComponents([.day], from: lastWeekStart, to: nowWeekStart).day ?? 0
        guard days / 7 >= 2 else { return false }
        return calendar.component(.weekday, from: now) >= weekday
    }

    private static func monthlyDayIsDue(since lastApplied: Date, day: Int, now: Date, calendar: Calendar) -> Bool {
        guard calendar.component(.day, from: now) >= day else { return false }
        var targetComps = calendar.dateComponents([.year, .month], from: now)
        targetComps.day = day
        guard let targetDate = calendar.date(from: targetComps) else { return true }
        return lastApplied < targetDate
    }

    static func startOfWeek(for date: Date, calendar: Calendar = .current) -> Date {
        let calendar = configuredCalendar(from: calendar)
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func nextOccurrence(
        after lastOccurrence: Date?,
        recurrence: RewardTask.Recurrence,
        from now: Date,
        calendar: Calendar = .current,
        weekday: Int? = nil,
        monthDay: Int? = nil
    ) -> Date? {
        let calendar = configuredCalendar(from: calendar)
        switch recurrence {
        case .none:
            return nil
        case .daily:
            let anchor = lastOccurrence ?? now
            let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: anchor)) ?? anchor
            return max(nextDay, now)
        case .weekly:
            let anchor = lastOccurrence ?? now
            let nextWeekStart = calendar.date(byAdding: .weekOfYear, value: 1, to: startOfWeek(for: anchor, calendar: calendar)) ?? anchor
            if let weekday {
                var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: nextWeekStart)
                comps.weekday = weekday
                let targetDate = calendar.date(from: comps) ?? nextWeekStart
                return max(targetDate, now)
            }
            return max(nextWeekStart, now)
        case .biweekly:
            let anchor = lastOccurrence ?? now
            let nextBiweekStart = calendar.date(byAdding: .weekOfYear, value: 2, to: startOfWeek(for: anchor, calendar: calendar)) ?? anchor
            if let weekday {
                var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: nextBiweekStart)
                comps.weekday = weekday
                let targetDate = calendar.date(from: comps) ?? nextBiweekStart
                return max(targetDate, now)
            }
            return max(nextBiweekStart, now)
        case .monthly:
            let anchor = lastOccurrence ?? now
            var comps = calendar.dateComponents([.year, .month], from: anchor)
            comps.month = (comps.month ?? 1) + 1
            comps.day = monthDay ?? 1
            let nextMonth = calendar.date(from: comps) ?? anchor
            return max(nextMonth, now)
        }
    }

    static func delayUntilNextOccurrence(
        recurrence: RewardTask.Recurrence,
        lastApplied: Date?,
        now: Date = Date(),
        calendar: Calendar = .current,
        weekday: Int? = nil,
        monthDay: Int? = nil
    ) -> TimeInterval? {
        guard recurrence != .none,
              let nextDate = nextOccurrence(
                  after: lastApplied,
                  recurrence: recurrence,
                  from: now,
                  calendar: calendar,
                  weekday: weekday,
                  monthDay: monthDay
              ) else {
            return nil
        }
        return max(nextDate.timeIntervalSince(now), minimumSchedulingDelay)
    }

    static let minimumSchedulingDelay: TimeInterval = 60
}
