import CryptoKit
import Security
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

    func testCanRenameKidAndEditTask() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 2)
        let store = RewardStore(
            initialState: RewardState(kids: [kid], tasks: [task], settings: .defaults, transactions: []),
            fileURL: temporaryStateURL()
        )

        store.updateKid(kid, name: "Milo")
        store.updateTask(task, title: "Clean room", points: 4)

        XCTAssertEqual(store.state.kids.first?.name, "Milo")
        XCTAssertEqual(store.state.tasks.first?.title, "Clean room")
        XCTAssertEqual(store.state.tasks.first?.points, 4)
    }

    func testCanSetSavingsGoalAndRecurringTask() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 10)
        let task = RewardTask(title: "Dishes", points: 2)
        let store = RewardStore(
            initialState: RewardState(kids: [kid], tasks: [task], settings: .defaults, transactions: []),
            fileURL: temporaryStateURL()
        )

        store.updateSavingsGoal(for: kid, title: "Bike", targetPoints: 50)
        store.updateTaskRecurrence(task, recurrence: .weekly)

        XCTAssertEqual(store.state.kids[0].savingsGoal?.title, "Bike")
        XCTAssertEqual(store.state.kids[0].savingsGoal?.targetPoints, 50)
        XCTAssertEqual(store.state.tasks[0].recurrence, .weekly)
    }

    func testRecurringTaskIsOnlyAvailableWhenDueForKid() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 2, recurrence: .daily)
        let start = Date(timeIntervalSince1970: 4_102_444_800)
        let store = RewardStore(
            initialState: RewardState(kids: [kid], tasks: [task], settings: .defaults, transactions: []),
            fileURL: temporaryStateURL()
        )

        XCTAssertTrue(store.isTaskAvailable(task, for: kid, now: start))
        store.award(task: task, to: kid, at: start)

        XCTAssertFalse(store.isTaskAvailable(task, for: kid, now: start.addingTimeInterval(60 * 60)))
        XCTAssertTrue(store.isTaskAvailable(task, for: kid, now: start.addingTimeInterval(25 * 60 * 60)))
    }

    func testManualAdjustmentAddsAndRemovesAvailablePoints() {
        let kid = Kid(name: "Avery", availablePoints: 3, vaultPoints: 0)
        let store = RewardStore(
            initialState: RewardState(kids: [kid], tasks: [], settings: .defaults, transactions: []),
            fileURL: temporaryStateURL()
        )

        store.adjust(points: 5, note: "Bonus", for: kid)
        let updatedKid = store.state.kids[0]
        XCTAssertEqual(updatedKid.availablePoints, 8)
        XCTAssertEqual(store.transactions(for: updatedKid).first?.points, 5)

        store.adjust(points: -20, note: "Correction", for: updatedKid)
        XCTAssertEqual(store.state.kids[0].availablePoints, 0)
        XCTAssertEqual(store.transactions(for: store.state.kids[0]).first?.points, -8)
    }

    func testDeleteTransactionReversesItsBalanceEffect() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 2)
        let store = RewardStore(
            initialState: RewardState(kids: [kid], tasks: [task], settings: .defaults, transactions: []),
            fileURL: temporaryStateURL()
        )

        store.award(task: task, to: kid)
        let updatedKid = store.state.kids[0]
        let transaction = store.transactions(for: updatedKid)[0]

        XCTAssertTrue(store.deleteTransaction(transaction))
        XCTAssertEqual(store.state.kids[0].availablePoints, 0)
        XCTAssertTrue(store.state.transactions.isEmpty)
    }

    func testCorrectTransactionUpdatesBalanceAndHistory() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 2)
        let store = RewardStore(
            initialState: RewardState(kids: [kid], tasks: [task], settings: .defaults, transactions: []),
            fileURL: temporaryStateURL()
        )

        store.award(task: task, to: kid)
        let transaction = store.transactions(for: store.state.kids[0])[0]

        XCTAssertTrue(store.correctTransaction(transaction, points: 5, note: "Big chore"))
        XCTAssertEqual(store.state.kids[0].availablePoints, 5)
        XCTAssertEqual(store.state.transactions[0].points, 5)
        XCTAssertEqual(store.state.transactions[0].note, "Big chore")
    }

    func testParentPINCanBeSetVerifiedAndRemoved() {
        let pinManager = InMemoryParentPINManager()
        let store = RewardStore(fileURL: temporaryStateURL(), pinManager: pinManager)

        XCTAssertTrue(store.verifyParentPIN(""))

        store.updateParentPIN("1234")
        XCTAssertTrue(store.hasParentPIN)
        XCTAssertTrue(store.verifyParentPIN("1234"))
        XCTAssertFalse(store.verifyParentPIN("0000"))

        store.updateParentPIN("   ")
        XCTAssertFalse(store.hasParentPIN)
        XCTAssertTrue(store.verifyParentPIN("anything"))
    }

    func testKeychainPINFailsClosedWhenStoredPayloadIsInvalid() {
        let service = "com.kidcoin-keeper.tests.\(UUID().uuidString)"
        let account = "parent-pin"
        let manager = KeychainParentPINManager(service: service, account: account)
        defer { manager.clear() }

        writeKeychainData(Data("not-json".utf8), service: service, account: account)

        XCTAssertTrue(manager.hasPIN)
        XCTAssertFalse(manager.verify(pin: "1234"))
    }

    func testKeychainPINCanVerifyLegacySingleHashPayload() throws {
        let service = "com.kidcoin-keeper.tests.\(UUID().uuidString)"
        let account = "parent-pin"
        let manager = KeychainParentPINManager(service: service, account: account)
        defer { manager.clear() }

        let salt = Data([1, 3, 5, 7, 9, 11, 13, 15])
        let payload = LegacyKeychainPayload(
            salt: salt,
            hash: singleHash(pin: "4321", salt: salt)
        )
        writeKeychainData(try JSONEncoder().encode(payload), service: service, account: account)

        XCTAssertTrue(manager.hasPIN)
        XCTAssertTrue(manager.verify(pin: "4321"))
        XCTAssertFalse(manager.verify(pin: "1234"))
    }

    func testLegacyPlainParentPINIsMigratedOutOfState() {
        let pinManager = InMemoryParentPINManager()
        let settings = RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: 1,
            vaultInterestRate: 0.05,
            legacyParentPIN: "4321"
        )
        let store = RewardStore(
            initialState: RewardState(kids: [], tasks: [], settings: settings, transactions: []),
            fileURL: temporaryStateURL(),
            pinManager: pinManager
        )

        XCTAssertTrue(store.hasParentPIN)
        XCTAssertTrue(store.verifyParentPIN("4321"))
        XCTAssertNil(store.state.settings.legacyParentPIN)
    }

    func testEncodedSettingsDoNotPersistPlainParentPIN() throws {
        let settings = RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: 1,
            vaultInterestRate: 0.05,
            legacyParentPIN: "4321"
        )

        let data = try JSONEncoder().encode(settings)
        let encoded = String(data: data, encoding: .utf8) ?? ""

        XCTAssertFalse(encoded.contains("parentPIN"))
        XCTAssertFalse(encoded.contains("4321"))
    }

    func testApprovalFlowQueuesAndApprovesCashOutRequest() {
        let kid = Kid(name: "Avery", availablePoints: 8, vaultPoints: 0)
        let store = RewardStore(
            initialState: RewardState(kids: [kid], tasks: [], settings: .defaults, transactions: []),
            fileURL: temporaryStateURL()
        )

        store.setApprovalFlowEnabled(true)
        store.requestCashOut(points: 5, for: kid)

        XCTAssertEqual(store.state.approvalRequests.count, 1)
        XCTAssertEqual(store.state.kids[0].availablePoints, 8)

        XCTAssertTrue(store.approveRequest(store.state.approvalRequests[0]))
        XCTAssertTrue(store.state.approvalRequests.isEmpty)
        XCTAssertEqual(store.state.kids[0].availablePoints, 3)
        XCTAssertEqual(store.state.transactions.first?.kind, .cashedOut)
    }

    func testApprovingCashOutRequestKeepsRequestWhenFullAmountCannotBeApplied() {
        let kid = Kid(name: "Avery", availablePoints: 8, vaultPoints: 0)
        let store = RewardStore(
            initialState: RewardState(kids: [kid], tasks: [], settings: .defaults, transactions: []),
            fileURL: temporaryStateURL()
        )

        store.setApprovalFlowEnabled(true)
        store.requestCashOut(points: 5, for: kid)
        let request = store.state.approvalRequests[0]
        store.adjust(points: -6, note: "Correction", for: store.state.kids[0])

        XCTAssertFalse(store.approveRequest(request))
        XCTAssertEqual(store.state.approvalRequests.map(\.id), [request.id])
        XCTAssertEqual(store.state.kids[0].availablePoints, 2)
        XCTAssertFalse(store.state.transactions.contains { $0.kind == .cashedOut })
    }

    func testApprovingInterestRequestAppliesRequestedAmount() {
        let settings = RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: 1,
            vaultInterestRate: 0.1
        )
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 20)
        let store = RewardStore(
            initialState: RewardState(kids: [kid], tasks: [], settings: settings, transactions: []),
            fileURL: temporaryStateURL()
        )

        store.setApprovalFlowEnabled(true)
        store.requestInterest(for: kid)
        let request = store.state.approvalRequests[0]
        store.updateSettings(currencyCode: "USD", currencyPerPoint: 1, vaultInterestRate: 0)

        XCTAssertTrue(store.approveRequest(request))
        XCTAssertTrue(store.state.approvalRequests.isEmpty)
        XCTAssertEqual(store.state.kids[0].vaultPoints, 22)
        XCTAssertEqual(store.state.transactions.first?.points, 2)
    }

    func testApprovalFlowQueuesAndDeclinesInterestRequest() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 20)
        let store = RewardStore(
            initialState: RewardState(kids: [kid], tasks: [], settings: .defaults, transactions: []),
            fileURL: temporaryStateURL()
        )

        store.setApprovalFlowEnabled(true)
        store.requestInterest(for: kid)

        XCTAssertEqual(store.state.approvalRequests.count, 1)
        XCTAssertEqual(store.state.approvalRequests[0].points, 1)

        store.declineRequest(store.state.approvalRequests[0])
        XCTAssertTrue(store.state.approvalRequests.isEmpty)
        XCTAssertEqual(store.state.kids[0].vaultPoints, 20)
        XCTAssertTrue(store.state.transactions.isEmpty)
    }

    func testAllowanceAppliesToAllKids() {
        let kids = [
            Kid(name: "Avery", availablePoints: 0, vaultPoints: 0),
            Kid(name: "Milo", availablePoints: 2, vaultPoints: 0)
        ]
        let store = RewardStore(
            initialState: RewardState(kids: kids, tasks: [], settings: .defaults, transactions: []),
            fileURL: temporaryStateURL()
        )

        store.updateSettings(currencyCode: "USD", currencyPerPoint: 1, vaultInterestRate: 0.05, allowancePoints: 4)
        store.applyAllowanceToAllKids()

        XCTAssertEqual(store.state.kids.map(\.availablePoints), [4, 6])
        XCTAssertEqual(store.state.transactions.count, 2)
    }

    func testAutomaticAllowanceAppliesOnlyWhenRecurrenceIsDue() {
        let start = Date(timeIntervalSince1970: 4_102_444_800)
        let kids = [
            Kid(name: "Avery", availablePoints: 0, vaultPoints: 0),
            Kid(name: "Milo", availablePoints: 2, vaultPoints: 0)
        ]
        let settings = RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: 1,
            vaultInterestRate: 0.05,
            allowancePoints: 3,
            allowanceRecurrence: .weekly,
            lastAllowanceAppliedAt: start
        )
        let store = RewardStore(
            initialState: RewardState(kids: kids, tasks: [], settings: settings, transactions: []),
            fileURL: temporaryStateURL()
        )

        XCTAssertFalse(store.applyDueAllowanceIfNeeded(now: start.addingTimeInterval(3 * 24 * 60 * 60)))
        XCTAssertEqual(store.state.kids.map(\.availablePoints), [0, 2])

        XCTAssertTrue(store.applyDueAllowanceIfNeeded(now: start.addingTimeInterval(8 * 24 * 60 * 60)))
        XCTAssertEqual(store.state.kids.map(\.availablePoints), [3, 5])
        XCTAssertEqual(store.state.transactions.count, 2)
    }

    func testCanExportAndImportStateData() {
        let kid = Kid(name: "Avery", availablePoints: 8, vaultPoints: 2)
        let source = RewardStore(
            initialState: RewardState(kids: [kid], tasks: [], settings: .defaults, transactions: []),
            fileURL: temporaryStateURL()
        )
        source.updateSavingsGoal(for: kid, title: "Skates", targetPoints: 30)

        let target = RewardStore(fileURL: temporaryStateURL())
        XCTAssertTrue(target.importStateData(source.exportStateData() ?? Data()))
        XCTAssertEqual(target.state.kids.first?.name, "Avery")
        XCTAssertEqual(target.state.kids.first?.savingsGoal?.title, "Skates")
    }

    func testImportPreviewReadsPlainStateAndCloudEnvelopeMetadata() throws {
        let kid = Kid(name: "Avery", availablePoints: 8, vaultPoints: 2)
        let state = RewardState(kids: [kid], tasks: [RewardTask(title: "Dishes", points: 2)], settings: .defaults, transactions: [])
        let store = RewardStore(fileURL: temporaryStateURL())
        let plainData = try JSONEncoder.configuredForTests.encode(state)

        let plainPreview = try XCTUnwrap(store.importPreview(from: plainData))
        XCTAssertEqual(plainPreview.kidsCount, 1)
        XCTAssertEqual(plainPreview.tasksCount, 1)
        XCTAssertFalse(plainPreview.isCloudBackup)

        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let envelope = CloudBackupEnvelope(schemaVersion: 2, savedAt: savedAt, deviceName: "Test Phone", state: state)
        let cloudData = try JSONEncoder.configuredForTests.encode(envelope)
        let cloudPreview = try XCTUnwrap(store.importPreview(from: cloudData))

        XCTAssertEqual(cloudPreview.savedAt, savedAt)
        XCTAssertEqual(cloudPreview.deviceName, "Test Phone")
        XCTAssertTrue(cloudPreview.isCloudBackup)
    }

    func testApprovalRequestsAreIgnoredWhenApprovalFlowIsDisabled() {
        let kid = Kid(name: "Avery", availablePoints: 8, vaultPoints: 20)
        let store = RewardStore(
            initialState: RewardState(kids: [kid], tasks: [], settings: .defaults, transactions: []),
            fileURL: temporaryStateURL()
        )

        store.requestCashOut(points: 5, for: kid)
        store.requestInterest(for: kid)

        XCTAssertTrue(store.state.approvalRequests.isEmpty)
    }

    func testImportRollsBackStateAndReportsErrorWhenPersistenceFails() throws {
        let sourceKid = Kid(name: "Imported", availablePoints: 8, vaultPoints: 2)
        let source = RewardStore(
            initialState: RewardState(kids: [sourceKid], tasks: [], settings: .defaults, transactions: []),
            fileURL: temporaryStateURL()
        )
        let importData = try XCTUnwrap(source.exportStateData())

        let originalKid = Kid(name: "Original", availablePoints: 1, vaultPoints: 0)
        let unwritableURL = temporaryDirectoryURL()
        try FileManager.default.createDirectory(at: unwritableURL, withIntermediateDirectories: true)
        let target = RewardStore(
            initialState: RewardState(kids: [originalKid], tasks: [], settings: .defaults, transactions: []),
            fileURL: unwritableURL
        )

        XCTAssertFalse(target.importStateData(importData))
        XCTAssertEqual(target.state.kids.first?.name, "Original")
        XCTAssertNotNil(target.persistenceErrorMessage)
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

    private func temporaryDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
    }

    private func writeKeychainData(_ data: Data, service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        XCTAssertEqual(SecItemAdd(addQuery as CFDictionary, nil), errSecSuccess)
    }

    private func singleHash(pin: String, salt: Data) -> Data {
        var input = Data()
        input.append(salt)
        input.append(Data(pin.utf8))
        return Data(SHA256.hash(data: input))
    }
}

private struct LegacyKeychainPayload: Codable {
    let salt: Data
    let hash: Data
}

private extension JSONEncoder {
    static var configuredForTests: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private final class InMemoryParentPINManager: ParentPINManaging {
    private var pin: String?

    var hasPIN: Bool {
        pin != nil
    }

    func save(pin: String) {
        self.pin = pin
    }

    func clear() {
        pin = nil
    }

    func verify(pin: String) -> Bool {
        guard let savedPIN = self.pin else { return true }
        return pin == savedPIN
    }
}
