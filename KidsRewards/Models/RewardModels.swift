import Foundation

struct Kid: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var availablePoints: Int
    var vaultPoints: Int
}

struct RewardTask: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var title: String
    var points: Int
}

struct RewardSettings: Codable, Equatable {
    var currencyCode: String
    var currencyPerPoint: Decimal
    var vaultInterestRate: Decimal

    static let defaults = RewardSettings(
        currencyCode: "USD",
        currencyPerPoint: 1,
        vaultInterestRate: 0.05
    )
}

struct RewardTransaction: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case earned
        case deposited
        case cashedOut
        case interest
    }

    var id = UUID()
    var kidID: UUID
    var kind: Kind
    var points: Int
    var note: String
    var date: Date
    var currencyAmount: Decimal?
}

struct RewardState: Codable, Equatable {
    var kids: [Kid]
    var tasks: [RewardTask]
    var settings: RewardSettings
    var transactions: [RewardTransaction]

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
        transactions: []
    )
}
