import XCTest
@testable import KidsRewards

@MainActor
final class RewardStoreTests: XCTestCase {
    func testStoreStartsEmptyByDefaultWhenNoSavedStateExists() {
        let store = RewardStore(fileURL: temporaryStateURL())

        XCTAssertTrue(store.state.kids.isEmpty)
        XCTAssertTrue(store.state.tasks.isEmpty)
        XCTAssertTrue(store.state.transactions.isEmpty)
        XCTAssertEqual(store.state.settings, .defaults)
    }

    func testCurrencyCodeIsTrimmedUppercasedLimitedAndBlankPreservesExistingValue() {
        let store = RewardStore(fileURL: temporaryStateURL())

        store.updateSettings(currencyCode: " cadx ", currencyPerPoint: 2, vaultInterestRate: 0.1)
        XCTAssertEqual(store.state.settings.currencyCode, "CAD")

        store.updateSettings(currencyCode: "   ", currencyPerPoint: 3, vaultInterestRate: 0.2)
        XCTAssertEqual(store.state.settings.currencyCode, "CAD")
    }

    func testDeletingKidRemovesTheirTransactions() {
        let kid = Kid(name: "Avery", availablePoints: 5, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 2)
        let store = RewardStore(
            initialState: RewardState(kids: [kid], tasks: [task], settings: .defaults, transactions: []),
            fileURL: temporaryStateURL()
        )

        store.award(task: task, to: kid)
        XCTAssertEqual(store.transactions(for: kid).count, 1)

        store.deleteKid(kid)
        XCTAssertTrue(store.state.kids.isEmpty)
        XCTAssertTrue(store.state.transactions.isEmpty)
    }

    func testCashOutTransactionDisplayLabelUsesNegativePoints() {
        let transaction = RewardTransaction(
            kidID: UUID(),
            kind: .cashedOut,
            points: 4,
            note: "Cash out",
            date: Date(),
            currencyAmount: 4
        )

        XCTAssertEqual(transaction.pointsDisplayLabel, "-4")
    }

    private func temporaryStateURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }
}
