import Foundation

struct Kid: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var availablePoints: Int
    var vaultPoints: Int
    var savingsGoal: SavingsGoal?
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
    }

    var id = UUID()
    var title: String
    var points: Int
    var recurrence: Recurrence

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case points
        case recurrence
    }

    init(id: UUID = UUID(), title: String, points: Int, recurrence: Recurrence = .none) {
        self.id = id
        self.title = title
        self.points = points
        self.recurrence = recurrence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        points = try container.decode(Int.self, forKey: .points)
        recurrence = try container.decodeIfPresent(Recurrence.self, forKey: .recurrence) ?? .none
    }
}

struct RewardSettings: Codable, Equatable {
    var currencyCode: String
    var currencyPerPoint: Decimal
    var vaultInterestRate: Decimal
    var approvalFlowEnabled: Bool
    var allowancePoints: Int
    var legacyParentPIN: String?

    static let defaults = RewardSettings(
        currencyCode: "USD",
        currencyPerPoint: 1,
        vaultInterestRate: 0.05,
        approvalFlowEnabled: false,
        allowancePoints: 5,
        legacyParentPIN: nil
    )

    private enum CodingKeys: String, CodingKey {
        case currencyCode
        case currencyPerPoint
        case vaultInterestRate
        case parentPIN
        case approvalFlowEnabled
        case allowancePoints
    }

    init(
        currencyCode: String,
        currencyPerPoint: Decimal,
        vaultInterestRate: Decimal,
        approvalFlowEnabled: Bool = false,
        allowancePoints: Int = 5,
        legacyParentPIN: String? = nil
    ) {
        self.currencyCode = currencyCode
        self.currencyPerPoint = currencyPerPoint
        self.vaultInterestRate = vaultInterestRate
        self.approvalFlowEnabled = approvalFlowEnabled
        self.allowancePoints = allowancePoints
        self.legacyParentPIN = legacyParentPIN
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currencyCode = try container.decode(String.self, forKey: .currencyCode)
        currencyPerPoint = try container.decode(Decimal.self, forKey: .currencyPerPoint)
        vaultInterestRate = try container.decode(Decimal.self, forKey: .vaultInterestRate)
        approvalFlowEnabled = try container.decodeIfPresent(Bool.self, forKey: .approvalFlowEnabled) ?? false
        allowancePoints = try container.decodeIfPresent(Int.self, forKey: .allowancePoints) ?? 5
        legacyParentPIN = try container.decodeIfPresent(String.self, forKey: .parentPIN)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(currencyPerPoint, forKey: .currencyPerPoint)
        try container.encode(vaultInterestRate, forKey: .vaultInterestRate)
        try container.encode(approvalFlowEnabled, forKey: .approvalFlowEnabled)
        try container.encode(allowancePoints, forKey: .allowancePoints)
    }
}

struct RewardTransaction: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case earned
        case deposited
        case cashedOut
        case interest
        case adjusted
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
        case .cashedOut:
            return "-\(points)"
        case .deposited:
            return "moved \(points)"
        case .adjusted:
            return points < 0 ? "\(points)" : "+\(points)"
        case .earned, .interest:
            return "+\(points)"
        }
    }
}

struct ApprovalRequest: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case cashOut
        case interest
    }

    var id = UUID()
    var kidID: UUID
    var kind: Kind
    var points: Int
    var note: String
    var date: Date
}

struct RewardState: Codable, Equatable {
    var kids: [Kid]
    var tasks: [RewardTask]
    var settings: RewardSettings
    var transactions: [RewardTransaction]
    var approvalRequests: [ApprovalRequest]

    private enum CodingKeys: String, CodingKey {
        case kids
        case tasks
        case settings
        case transactions
        case approvalRequests
    }

    init(
        kids: [Kid],
        tasks: [RewardTask],
        settings: RewardSettings,
        transactions: [RewardTransaction],
        approvalRequests: [ApprovalRequest] = []
    ) {
        self.kids = kids
        self.tasks = tasks
        self.settings = settings
        self.transactions = transactions
        self.approvalRequests = approvalRequests
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kids = try container.decode([Kid].self, forKey: .kids)
        tasks = try container.decode([RewardTask].self, forKey: .tasks)
        settings = try container.decode(RewardSettings.self, forKey: .settings)
        transactions = try container.decode([RewardTransaction].self, forKey: .transactions)
        approvalRequests = try container.decodeIfPresent([ApprovalRequest].self, forKey: .approvalRequests) ?? []
    }

    static let empty = RewardState(
        kids: [],
        tasks: [],
        settings: .defaults,
        transactions: [],
        approvalRequests: []
    )

    static let sample = RewardState(
        kids: [
            Kid(name: "Avery", availablePoints: 12, vaultPoints: 20),
            Kid(name: "Milo", availablePoints: 5, vaultPoints: 0)
        ],
        tasks: [
            RewardTask(title: "Mow the lawn", points: 5),
            RewardTask(title: "Clean bedroom", points: 3),
            RewardTask(title: "Help with dishes", points: 2)
        ],
        settings: .defaults,
        transactions: [],
        approvalRequests: []
    )
}
