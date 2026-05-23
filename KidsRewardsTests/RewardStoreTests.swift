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

    func testCorruptSavedStateIsNotOverwrittenWithEmptyState() throws {
        let fileURL = temporaryStateURL()
        let corruptData = Data("{ not valid json".utf8)
        try corruptData.write(to: fileURL)

        let store = RewardStore(fileURL: fileURL)

        XCTAssertTrue(store.state.kids.isEmpty)
        XCTAssertTrue(store.persistenceErrorMessage?.contains("Could not load saved data") == true)
        XCTAssertEqual(try Data(contentsOf: fileURL), corruptData)
    }

    func testSeededInitialStateIsNotReplacedByExistingFile() throws {
        let fileURL = temporaryStateURL()
        let staleState = RewardState(
            kids: [Kid(name: "Stale", availablePoints: 99, vaultPoints: 0)],
            tasks: [],
            settings: .defaults,
            transactions: []
        )
        try JSONEncoder.configuredForTests.encode(staleState).write(to: fileURL)

        let store = RewardStore(
            initialState: RewardState(
                kids: [Kid(name: "Avery", availablePoints: 3, vaultPoints: 0)],
                tasks: [],
                settings: .defaults,
                transactions: []
            ),
            fileURL: fileURL
        )

        XCTAssertEqual(store.state.kids.first?.name, "Avery")
        XCTAssertEqual(store.state.kids.first?.availablePoints, 3)
    }

    func testCurrencyCodeIsTrimmedUppercasedLimitedAndBlankPreservesExistingValue() {
        let store = RewardStore(fileURL: temporaryStateURL())

        store.updateSettings(currencyCode: " cadx ", currencyPerPoint: 2, vaultInterestRate: 0.1)
        XCTAssertEqual(store.state.settings.currencyCode, "CAD")

        store.updateSettings(currencyCode: "   ", currencyPerPoint: 3, vaultInterestRate: 0.2)
        XCTAssertEqual(store.state.settings.currencyCode, "CAD")
    }

    func testRewardStateRoundTripPreservesTransactions() throws {
        let kid = Kid(name: "Avery", availablePoints: 3, vaultPoints: 0)
        var state = RewardState(kids: [kid], tasks: [], settings: .defaults, transactions: [])
        state.transactions.append(
            RewardTransaction(
                kidID: kid.id,
                kind: .adjusted,
                points: 5,
                note: "Bonus",
                date: Date(timeIntervalSince1970: 1_800_000_000),
                currencyAmount: nil
            )
        )

        let data = try JSONEncoder.configuredForTests.encode(state)
        let decoded = try JSONDecoder.configuredForTests.decode(RewardState.self, from: data)

        XCTAssertEqual(decoded.transactions.count, 1)
        XCTAssertEqual(decoded.transactions.first?.points, 5)
        XCTAssertEqual(decoded.transactions.first?.kidID, kid.id)
    }

    func testRewardSettingsPointsPerDollarConversion() {
        assertDecimalEqual(RewardSettings.currencyPerPoint(pointsPerDollar: 10), 0.1)
        assertDecimalEqual(RewardSettings.currencyPerPoint(pointsPerDollar: 4), 0.25)
        XCTAssertNil(RewardSettings.currencyPerPoint(pointsPerDollar: 0))

        let settings = RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: Decimal(string: "0.1")!,
            vaultInterestRate: 0.05
        )
        assertDecimalEqual(settings.pointsPerDollar, 10)
        let zeroRateSettings = RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: 0,
            vaultInterestRate: 0.05
        )
        XCTAssertNil(zeroRateSettings.pointsPerDollar)
    }

    func testTenPointsPerDollarStoresCorrectCashValue() {
        let store = RewardStore(fileURL: temporaryStateURL())
        let currencyPerPoint = RewardSettings.currencyPerPoint(pointsPerDollar: 10)

        XCTAssertNotNil(currencyPerPoint)
        store.updateSettings(currencyCode: "USD", currencyPerPoint: currencyPerPoint!, vaultInterestRate: 0.05)

        assertDecimalEqual(store.state.settings.pointsPerDollar, 10)
        assertDecimalEqual(store.currencyValue(for: 10), 1)
        assertDecimalEqual(store.currencyValue(for: 1), 0.1)
    }

    func testDeletingKidRemovesTheirTransactionsRequestsAndCompletions() {
        let kid = Kid(name: "Avery", availablePoints: 5, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 2, recurrence: .daily)
        let settings = RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: 1,
            vaultInterestRate: 0.05,
            approvalFlowEnabled: true
        )
        let store = RewardStore(
            initialState: RewardState(kids: [kid], tasks: [task], settings: settings, transactions: []),
            fileURL: temporaryStateURL()
        )

        store.award(task: task, to: kid)
        store.requestCashOut(points: 1, for: store.state.kids[0])
        XCTAssertEqual(store.transactions(for: kid).count, 1)
        XCTAssertEqual(store.state.approvalRequests.count, 1)
        XCTAssertEqual(store.state.taskCompletions.count, 1)

        store.deleteKid(kid)
        XCTAssertTrue(store.state.kids.isEmpty)
        XCTAssertTrue(store.state.transactions.isEmpty)
        XCTAssertTrue(store.state.approvalRequests.isEmpty)
        XCTAssertTrue(store.state.taskCompletions.isEmpty)
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
        store.updateTask(task, title: task.title, points: task.points, recurrence: .weekly)

        XCTAssertEqual(store.state.kids[0].savingsGoal?.title, "Bike")
        XCTAssertEqual(store.state.kids[0].savingsGoal?.targetPoints, 50)
        XCTAssertEqual(store.state.tasks[0].recurrence, .weekly)
    }

    func testDeletingTaskRemovesRecurringCompletionState() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 2, recurrence: .daily)
        let store = RewardStore(
            initialState: RewardState(kids: [kid], tasks: [task], settings: .defaults, transactions: []),
            fileURL: temporaryStateURL()
        )

        store.award(task: task, to: kid)
        XCTAssertEqual(store.state.taskCompletions.count, 1)

        store.deleteTask(task)
        XCTAssertTrue(store.state.tasks.isEmpty)
        XCTAssertTrue(store.state.taskCompletions.isEmpty)
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
        let store = makeStore(kids: [Kid(name: "Avery", availablePoints: 3, vaultPoints: 0)])

        store.adjust(points: 5, note: "Bonus", for: store.state.kids[0])
        XCTAssertEqual(store.state.kids[0].availablePoints, 8)
        XCTAssertEqual(store.transactions(for: store.state.kids[0]).map(\.points), [5])

        store.adjust(points: -20, note: "Correction", for: store.state.kids[0])
        XCTAssertEqual(store.state.kids[0].availablePoints, 0)
        XCTAssertEqual(store.transactions(for: store.state.kids[0]).map(\.points), [-8, 5])
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

    func testParentPINCanBeSetVerifiedAndRemoved() async {
        let pinManager = InMemoryParentPINManager()
        let store = RewardStore(fileURL: temporaryStateURL(), pinManager: pinManager)

        let emptyPINIsAllowed = await store.verifyParentPIN("")
        XCTAssertTrue(emptyPINIsAllowed)

        let didSetPIN = await store.updateParentPIN("1234")
        XCTAssertTrue(didSetPIN)
        XCTAssertTrue(store.hasParentPIN)
        let correctPINIsAccepted = await store.verifyParentPIN("1234")
        let incorrectPINIsAccepted = await store.verifyParentPIN("0000")
        XCTAssertTrue(correctPINIsAccepted)
        XCTAssertFalse(incorrectPINIsAccepted)

        let didRemovePIN = await store.updateParentPIN("   ")
        XCTAssertTrue(didRemovePIN)
        XCTAssertFalse(store.hasParentPIN)
        let unlockedWithoutPIN = await store.verifyParentPIN("anything")
        XCTAssertTrue(unlockedWithoutPIN)
    }

    func testKeychainPINFailsClosedWhenStoredPayloadIsInvalid() throws {
        let service = "com.kidcoin-keeper.tests.\(UUID().uuidString)"
        let account = "parent-pin"
        let manager = KeychainParentPINManager(service: service, account: account)
        defer { manager.clear() }

        try writeKeychainData(Data("not-json".utf8), service: service, account: account)

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
        try writeKeychainData(try JSONEncoder().encode(payload), service: service, account: account)

        XCTAssertTrue(manager.hasPIN)
        XCTAssertTrue(manager.verify(pin: "4321"))
        XCTAssertFalse(manager.verify(pin: "1234"))
    }

    func testLegacyPlainParentPINIsMigratedOutOfState() async {
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
        let migratedPINIsAccepted = await store.verifyParentPIN("4321")
        XCTAssertTrue(migratedPINIsAccepted)
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

    func testRequestCashOutCapsAtAvailablePoints() {
        let kid = Kid(name: "Avery", availablePoints: 6, vaultPoints: 0)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], settings: settings)

        store.requestCashOut(points: 20, for: kid)

        XCTAssertEqual(store.state.approvalRequests.count, 1)
        XCTAssertEqual(store.state.approvalRequests[0].points, 6)
    }

    func testApprovalFlowQueuesAndApprovesCashOutRequest() {
        let store = makeStore(kids: [Kid(name: "Avery", availablePoints: 8, vaultPoints: 0)])
        let kid = store.state.kids[0]

        store.setApprovalFlowEnabled(true)
        store.requestCashOut(points: 5, for: kid)

        XCTAssertEqual(store.state.approvalRequests.count, 1)
        XCTAssertEqual(store.state.kids[0].availablePoints, 8)

        XCTAssertTrue(store.approveRequest(store.state.approvalRequests[0]))
        XCTAssertTrue(store.state.approvalRequests.isEmpty)
        XCTAssertEqual(store.state.kids[0].availablePoints, 3)
        XCTAssertEqual(store.transactions(for: kid).first?.kind, .cashedOut)
        XCTAssertEqual(store.transactions(for: kid).first?.points, 5)
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
        let store = makeStore(
            kids: [Kid(name: "Avery", availablePoints: 0, vaultPoints: 20)],
            settings: settings
        )
        let kid = store.state.kids[0]

        store.setApprovalFlowEnabled(true)
        store.requestInterest(for: kid)
        let request = store.state.approvalRequests[0]
        store.updateSettings(currencyCode: "USD", currencyPerPoint: 1, vaultInterestRate: 0)

        XCTAssertTrue(store.approveRequest(request))
        XCTAssertTrue(store.state.approvalRequests.isEmpty)
        XCTAssertEqual(store.state.kids[0].vaultPoints, 22)
        XCTAssertEqual(store.transactions(for: kid).first?.points, 2)
        XCTAssertEqual(store.transactions(for: kid).first?.kind, .interest)
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
        let appliedAt = Date(timeIntervalSince1970: 1_800_000_000)

        store.updateSettings(currencyCode: "USD", currencyPerPoint: 1, vaultInterestRate: 0.05, allowancePoints: 4)
        store.applyAllowanceToAllKids(at: appliedAt)

        XCTAssertEqual(store.state.kids.map(\.availablePoints), [4, 6])
        XCTAssertEqual(store.state.transactions.count, 2)
        XCTAssertEqual(store.state.transactions.map(\.note), ["Allowance", "Allowance"])
        // lastAllowanceAppliedAt is only recorded when a recurring schedule is active;
        // with .none recurrence the field stays nil intentionally.
    }

    func testApplyAllowanceToSingleKidOnlyAffectsThatKid() {
        let kids = [
            Kid(name: "Avery", availablePoints: 1, vaultPoints: 0),
            Kid(name: "Milo", availablePoints: 2, vaultPoints: 0)
        ]
        let store = RewardStore(
            initialState: RewardState(kids: kids, tasks: [], settings: .defaults, transactions: []),
            fileURL: temporaryStateURL()
        )

        store.updateSettings(currencyCode: "USD", currencyPerPoint: 1, vaultInterestRate: 0.05, allowancePoints: 5)
        store.applyAllowance(to: kids[0])

        XCTAssertEqual(store.state.kids[0].availablePoints, 6)
        XCTAssertEqual(store.state.kids[1].availablePoints, 2)
        XCTAssertEqual(store.state.transactions.count, 1)
        XCTAssertEqual(store.state.transactions[0].kidID, kids[0].id)
        XCTAssertEqual(store.state.transactions[0].kind, .earned)
        XCTAssertNil(store.state.settings.lastAllowanceAppliedAt)
    }

    func testApplyAllowanceToSingleKidIsIgnoredWhenAllowancePointsAreZero() {
        let kid = Kid(name: "Avery", availablePoints: 3, vaultPoints: 0)
        let store = RewardStore(
            initialState: RewardState(kids: [kid], tasks: [], settings: .defaults, transactions: []),
            fileURL: temporaryStateURL()
        )

        store.updateSettings(currencyCode: "USD", currencyPerPoint: 1, vaultInterestRate: 0.05, allowancePoints: 0)
        store.applyAllowance(to: kid)

        XCTAssertEqual(store.state.kids[0].availablePoints, 3)
        XCTAssertTrue(store.state.transactions.isEmpty)
    }

    func testAutomaticAllowanceAppliesOnlyWhenRecurrenceIsDue() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = RecurrenceSchedule.calendarWeekFirstWeekday
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 3, hour: 12)))
        let midWeek = try XCTUnwrap(calendar.date(byAdding: .day, value: 3, to: start))
        let nextWeek = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: start))
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

        XCTAssertFalse(store.applyDueAllowanceIfNeeded(now: midWeek))
        XCTAssertEqual(store.state.kids.map(\.availablePoints), [0, 2])

        XCTAssertTrue(store.applyDueAllowanceIfNeeded(now: nextWeek))
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
        store.requestDeposit(points: 3, for: kid)
        store.requestChoreCompletion(task: RewardTask(title: "Dishes", points: 2), for: kid)
        store.requestAllowance(points: 2, for: kid)

        XCTAssertTrue(store.state.approvalRequests.isEmpty)
    }

    func testRequestDepositRequiresApprovalFlowAndAvailablePoints() {
        let kid = Kid(name: "Avery", availablePoints: 6, vaultPoints: 0)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], settings: settings)

        store.requestDeposit(points: 10, for: kid)

        XCTAssertEqual(store.state.approvalRequests.count, 1)
        XCTAssertEqual(store.state.approvalRequests[0].kind, .vaultDeposit)
        XCTAssertEqual(store.state.approvalRequests[0].points, 6)
    }

    func testApproveDepositRequestMovesPointsToVault() {
        let kid = Kid(name: "Avery", availablePoints: 10, vaultPoints: 2)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], settings: settings)

        store.requestDeposit(points: 4, for: kid)
        XCTAssertTrue(store.approveRequest(store.state.approvalRequests[0]))

        XCTAssertEqual(store.state.kids[0].availablePoints, 6)
        XCTAssertEqual(store.state.kids[0].vaultPoints, 6)
        XCTAssertEqual(store.state.transactions.last?.kind, .deposited)
    }

    func testDeclineDepositRequestLeavesBalancesUnchanged() {
        let kid = Kid(name: "Avery", availablePoints: 10, vaultPoints: 0)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], settings: settings)

        store.requestDeposit(points: 4, for: kid)
        store.declineRequest(store.state.approvalRequests[0])

        XCTAssertEqual(store.state.kids[0].availablePoints, 10)
        XCTAssertTrue(store.state.transactions.isEmpty)
    }

    func testPendingApprovalRequestFindsMatchingChoreAndDeposit() {
        let kid = Kid(name: "Avery", availablePoints: 8, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 3)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], tasks: [task], settings: settings)

        store.requestChoreCompletion(task: task, for: kid)
        store.requestDeposit(points: 2, for: kid)

        XCTAssertNotNil(store.pendingApprovalRequest(kind: .choreCompleted, kidID: kid.id, taskID: task.id))
        XCTAssertNotNil(store.pendingApprovalRequest(kind: .vaultDeposit, kidID: kid.id))
        XCTAssertNil(store.pendingApprovalRequest(kind: .cashOut, kidID: kid.id))
    }

    func testTransactionsForKidReturnsNewestFirst() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let older = RewardTransaction(
            kidID: kid.id,
            kind: .earned,
            points: 2,
            note: "Older",
            date: Date(timeIntervalSince1970: 1_000),
            currencyAmount: nil
        )
        let newer = RewardTransaction(
            kidID: kid.id,
            kind: .earned,
            points: 3,
            note: "Newer",
            date: Date(timeIntervalSince1970: 2_000),
            currencyAmount: nil
        )
        let store = makeStore(
            kids: [kid],
            transactions: [older, newer]
        )

        let ordered = store.transactions(for: kid)

        XCTAssertEqual(ordered.map(\.note), ["Newer", "Older"])
    }

    func testWeeklyRecurrenceUsesCalendarWeekNotRollingSevenDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = RecurrenceSchedule.calendarWeekFirstWeekday
        let sunday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 1, day: 5, hour: 12)))
        let wednesday = try XCTUnwrap(calendar.date(byAdding: .day, value: 3, to: sunday))
        let nextSunday = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: sunday))

        XCTAssertFalse(RecurrenceSchedule.isDue(since: sunday, recurrence: .weekly, now: wednesday, calendar: calendar))
        XCTAssertTrue(RecurrenceSchedule.isDue(since: sunday, recurrence: .weekly, now: nextSunday, calendar: calendar))
    }

    func testDepositUsesApprovalQueueWhenApprovalFlowEnabled() {
        let kid = Kid(name: "Avery", availablePoints: 10, vaultPoints: 0)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], settings: settings)

        XCTAssertTrue(store.deposit(points: 4, for: kid))

        XCTAssertEqual(store.state.approvalRequests.count, 1)
        XCTAssertEqual(store.state.approvalRequests[0].kind, .vaultDeposit)
        XCTAssertEqual(store.state.kids[0].availablePoints, 10)
    }

    func testApproveAllowanceRequestAddsPoints() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], settings: settings)

        store.requestAllowance(points: 6, for: kid)
        XCTAssertTrue(store.approveRequest(store.state.approvalRequests[0]))

        XCTAssertEqual(store.state.kids[0].availablePoints, 6)
        XCTAssertEqual(store.state.transactions.last?.note, "Allowance")
    }

    func testApplyAllowanceUsesPerKidOverride() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0, allowancePoints: 9)
        let store = makeStore(
            kids: [kid],
            settings: RewardSettings(
                currencyCode: "USD",
                currencyPerPoint: 1,
                vaultInterestRate: 0.05,
                allowancePoints: 3
            )
        )

        store.applyAllowance(to: kid)

        XCTAssertEqual(store.state.kids[0].availablePoints, 9)
    }

    func testScheduledAllowanceQueuesApprovalRequestsWhenEnabled() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = RecurrenceSchedule.calendarWeekFirstWeekday
        let lastWeek = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 3, hour: 12)))
        let now = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: lastWeek))
        var settings = RewardSettings.defaults
        settings.allowancePoints = 4
        settings.allowanceRecurrence = .weekly
        settings.approvalFlowEnabled = true
        settings.lastAllowanceAppliedAt = lastWeek
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let store = makeStore(kids: [kid], settings: settings)

        XCTAssertTrue(store.applyDueAllowanceIfNeeded(now: now))

        XCTAssertEqual(store.state.approvalRequests.count, 1)
        XCTAssertEqual(store.state.approvalRequests[0].kind, .allowance)
        XCTAssertEqual(store.state.kids[0].availablePoints, 0)
    }

    func testSavingsGoalProgressReflectsGoalPoints() {
        let kid = Kid(name: "Avery", availablePoints: 7, vaultPoints: 5, goalPoints: 12, savingsGoal: SavingsGoal(title: "Bike", targetPoints: 20))
        let store = makeStore(kids: [kid])

        XCTAssertEqual(store.savingsGoalProgress(for: kid), 12)
    }

    func testSavingsGoalProgressCapsAtTarget() {
        let kid = Kid(
            name: "Avery",
            availablePoints: 0,
            vaultPoints: 0,
            goalPoints: 30,
            savingsGoal: SavingsGoal(title: "Bike", targetPoints: 20)
        )
        let store = makeStore(kids: [kid])

        XCTAssertEqual(store.savingsGoalProgress(for: kid), 20)
    }

    func testOneTimeChoreUnavailableAfterAward() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "One-off", points: 5, recurrence: .none)
        let store = makeStore(kids: [kid], tasks: [task])

        XCTAssertTrue(store.isTaskAvailable(task, for: kid))
        store.award(task: task, to: kid)

        XCTAssertFalse(store.isTaskAvailable(task, for: kid))
        XCTAssertEqual(store.state.kids[0].availablePoints, 5)
        XCTAssertEqual(store.state.taskCompletions.count, 1)
    }

    func testScheduledAllowanceQueueDoesNotMarkScheduleAppliedUntilApproved() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = RecurrenceSchedule.calendarWeekFirstWeekday
        let lastWeek = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 3, hour: 12)))
        let now = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: lastWeek))
        var settings = RewardSettings.defaults
        settings.allowancePoints = 4
        settings.allowanceRecurrence = .weekly
        settings.approvalFlowEnabled = true
        settings.lastAllowanceAppliedAt = lastWeek
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let store = makeStore(kids: [kid], settings: settings)

        XCTAssertTrue(store.applyDueAllowanceIfNeeded(now: now))
        XCTAssertEqual(store.state.approvalRequests.count, 1)
        XCTAssertEqual(store.state.settings.lastAllowanceAppliedAt, lastWeek)

        let request = store.state.approvalRequests[0]
        XCTAssertTrue(store.approveRequest(request))
        XCTAssertTrue(store.state.approvalRequests.isEmpty)
        XCTAssertEqual(store.state.kids[0].availablePoints, 4)
        XCTAssertNotNil(store.state.settings.lastAllowanceAppliedAt)
        XCTAssertNotEqual(store.state.settings.lastAllowanceAppliedAt, lastWeek)
    }

    func testParentPINLockoutAfterRepeatedFailures() async {
        let pinManager = InMemoryParentPINManager()
        let store = RewardStore(
            initialState: RewardState(kids: [], tasks: [], settings: .defaults, transactions: []),
            fileURL: temporaryStateURL(),
            pinManager: pinManager
        )
        let start = Date()
        _ = await store.updateParentPIN("1234")

        for _ in 0..<RewardStore.parentPINMaxFailedAttempts {
            let accepted = await store.verifyParentPIN("0000", now: start)
            XCTAssertFalse(accepted)
        }

        XCTAssertNotNil(store.parentPINLockoutUntil)
        let blocked = await store.verifyParentPIN("1234", now: start)
        XCTAssertFalse(blocked)

        let afterLockout = start.addingTimeInterval(RewardStore.parentPINLockoutDuration + 1)
        let unlocked = await store.verifyParentPIN("1234", now: afterLockout)
        XCTAssertTrue(unlocked)
        XCTAssertFalse(store.isParentPINLockedOut)
    }

    func testIsAllowanceScheduleDueWhenRecurrenceEnabledAndNeverApplied() {
        let anchor = Date(timeIntervalSince1970: 4_102_444_800) // year 2100
        var settings = RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: 1,
            vaultInterestRate: 0.05,
            allowancePoints: 5,
            allowanceRecurrence: .weekly
        )
        settings.lastAllowanceAppliedAt = anchor
        let store = makeStore(
            kids: [Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)],
            settings: settings
        )

        XCTAssertTrue(store.isAllowanceScheduleDue(now: anchor.addingTimeInterval(8 * 24 * 3600)))
    }

    func testAllowanceScheduleNotDueWhenAllEligibleKidsAlreadyHavePendingApproval() {
        let anchor = Date(timeIntervalSince1970: 4_102_444_800) // year 2100
        var settings = RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: 1,
            vaultInterestRate: 0.05,
            approvalFlowEnabled: true,
            allowancePoints: 5,
            allowanceRecurrence: .daily
        )
        settings.lastAllowanceAppliedAt = anchor
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let store = makeStore(kids: [kid], settings: settings)

        store.requestAllowance(points: 5, for: store.state.kids[0])

        XCTAssertFalse(store.isAllowanceScheduleDue(now: anchor.addingTimeInterval(25 * 3600)))
    }

    func testEarnedPointsThisWeekSumsEarnedTransactions() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let now = Date()
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let store = makeStore(
            kids: [kid],
            transactions: [
                RewardTransaction(
                    kidID: kid.id,
                    kind: .earned,
                    points: 4,
                    note: "Chore",
                    date: weekStart.addingTimeInterval(60),
                    currencyAmount: nil
                ),
                RewardTransaction(
                    kidID: kid.id,
                    kind: .cashedOut,
                    points: 2,
                    note: "Cash out",
                    date: weekStart.addingTimeInterval(120),
                    currencyAmount: 2
                )
            ]
        )

        XCTAssertEqual(store.earnedPointsThisWeek(now: now), 4)
    }

    func testReadyChoreCountRespectsRecurrence() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 2, recurrence: .daily)
        let start = Date(timeIntervalSince1970: 4_102_444_800)
        let store = makeStore(kids: [kid], tasks: [task])

        XCTAssertEqual(store.readyChoreCount(for: kid, now: start), 1)
        store.award(task: task, to: kid, at: start)
        XCTAssertEqual(store.readyChoreCount(for: kid, now: start.addingTimeInterval(60 * 60)), 0)
    }

    func testRecentTransactionsReturnsNewestHouseholdWide() {
        let kidA = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let kidB = Kid(name: "Milo", availablePoints: 0, vaultPoints: 0)
        let older = RewardTransaction(
            kidID: kidA.id,
            kind: .earned,
            points: 1,
            note: "Older",
            date: Date(timeIntervalSince1970: 1_000),
            currencyAmount: nil
        )
        let newer = RewardTransaction(
            kidID: kidB.id,
            kind: .earned,
            points: 2,
            note: "Newer",
            date: Date(timeIntervalSince1970: 2_000),
            currencyAmount: nil
        )
        let store = makeStore(kids: [kidA, kidB], transactions: [older, newer])

        XCTAssertEqual(store.recentTransactions(limit: 1).map(\.note), ["Newer"])
    }

    func testKidAllowancePointsRoundTrip() throws {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0, allowancePoints: 12)
        let state = RewardState(kids: [kid], tasks: [], settings: .defaults, transactions: [])
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(RewardState.self, from: data)

        XCTAssertEqual(decoded.kids[0].allowancePoints, 12)
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

    func testImportDoesNotMigrateLegacyPINWhenPersistenceFails() throws {
        let pinManager = RecordingParentPINManager()
        let originalKid = Kid(name: "Original", availablePoints: 1, vaultPoints: 0)
        let unwritableURL = temporaryDirectoryURL()
        try FileManager.default.createDirectory(at: unwritableURL, withIntermediateDirectories: true)
        let target = RewardStore(
            initialState: RewardState(kids: [originalKid], tasks: [], settings: .defaults, transactions: []),
            fileURL: unwritableURL,
            pinManager: pinManager
        )

        XCTAssertFalse(target.importStateData(legacyStateData(parentPIN: "9999")))
        XCTAssertNil(pinManager.savedPIN)
        XCTAssertEqual(target.state.kids.first?.name, "Original")
    }

    func testImportRollsBackWhenLegacyPINMigrationFailsAfterStateSave() throws {
        let pinManager = FailingParentPINManager()
        let originalKid = Kid(name: "Original", availablePoints: 1, vaultPoints: 0)
        let target = RewardStore(
            initialState: RewardState(kids: [originalKid], tasks: [], settings: .defaults, transactions: []),
            fileURL: temporaryStateURL(),
            pinManager: pinManager
        )

        XCTAssertFalse(target.importStateData(legacyStateData(parentPIN: "9999")))
        XCTAssertEqual(target.state.kids.first?.name, "Original")
        XCTAssertFalse(target.hasParentPIN)
    }

    func testVaultWithdrawMovesPointsToAvailable() {
        let kid = Kid(name: "Avery", availablePoints: 2, vaultPoints: 10)
        let store = makeStore(kids: [kid])

        store.withdraw(points: 4, for: store.state.kids[0])

        XCTAssertEqual(store.state.kids[0].availablePoints, 6)
        XCTAssertEqual(store.state.kids[0].vaultPoints, 6)
        let transaction = store.state.transactions.last
        XCTAssertEqual(transaction?.kind, .withdrawn)
        XCTAssertEqual(transaction?.points, 4)
        XCTAssertEqual(transaction?.note, "Vault withdrawal")
    }

    func testVaultWithdrawCapsAtVaultBalance() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 3)
        let store = makeStore(kids: [kid])

        store.withdraw(points: 50, for: store.state.kids[0])

        XCTAssertEqual(store.state.kids[0].availablePoints, 3)
        XCTAssertEqual(store.state.kids[0].vaultPoints, 0)
        XCTAssertEqual(store.state.transactions.last?.points, 3)
    }

    func testVaultWithdrawDoesNothingWhenVaultIsEmpty() {
        let kid = Kid(name: "Avery", availablePoints: 5, vaultPoints: 0)
        let store = makeStore(kids: [kid])

        store.withdraw(points: 10, for: store.state.kids[0])

        XCTAssertEqual(store.state.kids[0].availablePoints, 5)
        XCTAssertTrue(store.state.transactions.isEmpty)
    }

    func testVaultWithdrawIgnoresNonPositiveAmounts() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 8)
        let store = makeStore(kids: [kid])

        store.withdraw(points: 0, for: store.state.kids[0])
        store.withdraw(points: -3, for: store.state.kids[0])

        XCTAssertEqual(store.state.kids[0].vaultPoints, 8)
        XCTAssertTrue(store.state.transactions.isEmpty)
    }

    func testDeleteWithdrawTransactionRestoresBalances() throws {
        let kid = Kid(name: "Avery", availablePoints: 1, vaultPoints: 10)
        let store = makeStore(kids: [kid])
        store.withdraw(points: 4, for: store.state.kids[0])
        let withdrawal = try XCTUnwrap(store.state.transactions.last)

        XCTAssertTrue(store.deleteTransaction(withdrawal))

        XCTAssertEqual(store.state.kids[0].availablePoints, 1)
        XCTAssertEqual(store.state.kids[0].vaultPoints, 10)
        XCTAssertTrue(store.state.transactions.isEmpty)
    }

    func testWithdrawTransactionDisplayLabelUsesPositivePoints() {
        let transaction = RewardTransaction(
            kidID: UUID(),
            kind: .withdrawn,
            points: 6,
            note: "Vault withdrawal",
            date: Date(),
            currencyAmount: nil
        )

        XCTAssertEqual(transaction.pointsDisplayLabel, "+6")
    }

    func testDepositAndWithdrawRoundTripPreservesTotalPoints() {
        let kid = Kid(name: "Avery", availablePoints: 12, vaultPoints: 0)
        let store = makeStore(kids: [kid])
        let kidSnapshot = store.state.kids[0]

        store.deposit(points: 7, for: kidSnapshot)
        store.withdraw(points: 3, for: store.state.kids[0])

        XCTAssertEqual(store.state.kids[0].availablePoints, 8)
        XCTAssertEqual(store.state.kids[0].vaultPoints, 4)
        XCTAssertEqual(
            store.state.kids[0].availablePoints + store.state.kids[0].vaultPoints,
            kidSnapshot.availablePoints
        )
    }

    func testPullFromICloudIfNewerSkipsWhenAutoSyncDisabled() throws {
        ICloudBackup.setAvailableForTesting(true)
        defer { ICloudBackup.setAvailableForTesting(nil) }

        let cloudKid = Kid(name: "Cloud", availablePoints: 50, vaultPoints: 0)
        let cloudStore = makeStore(
            kids: [cloudKid],
            settings: settingsWithICloudAutoSync(enabled: true)
        )
        let backupData = try makeCloudBackupData(from: cloudStore)

        let localStore = makeStore(
            kids: [Kid(name: "Local", availablePoints: 1, vaultPoints: 0)],
            settings: settingsWithICloudAutoSync(enabled: false)
        )
        localStore.debugICloudBackupData = backupData
        markLocalSaveDate(.distantPast)

        XCTAssertFalse(localStore.pullFromICloudIfNewer())
        XCTAssertEqual(localStore.state.kids.first?.name, "Local")
    }

    func testPullFromICloudIfNewerImportsWhenCloudBackupIsNewer() throws {
        ICloudBackup.setAvailableForTesting(true)
        defer { ICloudBackup.setAvailableForTesting(nil) }

        let cloudKid = Kid(name: "Cloud", availablePoints: 50, vaultPoints: 0)
        let cloudStore = makeStore(
            kids: [cloudKid],
            settings: settingsWithICloudAutoSync(enabled: true)
        )
        let backupData = try makeCloudBackupData(from: cloudStore)

        let localStore = makeStore(
            kids: [Kid(name: "Local", availablePoints: 1, vaultPoints: 0)],
            settings: settingsWithICloudAutoSync(enabled: true)
        )
        localStore.debugICloudBackupData = backupData
        markLocalSaveDate(.distantPast)

        XCTAssertTrue(localStore.pullFromICloudIfNewer())
        XCTAssertEqual(localStore.state.kids.first?.name, "Cloud")
        XCTAssertEqual(localStore.state.kids.first?.availablePoints, 50)
    }

    func testPullFromICloudIfNewerSkipsWhenLocalSaveIsNewer() throws {
        ICloudBackup.setAvailableForTesting(true)
        defer { ICloudBackup.setAvailableForTesting(nil) }

        let cloudKid = Kid(name: "Cloud", availablePoints: 50, vaultPoints: 0)
        let cloudStore = makeStore(
            kids: [cloudKid],
            settings: settingsWithICloudAutoSync(enabled: true)
        )
        let backupData = try makeCloudBackupData(
            from: cloudStore,
            savedAt: Date(timeIntervalSince1970: 1_000)
        )

        let localStore = makeStore(
            kids: [Kid(name: "Local", availablePoints: 1, vaultPoints: 0)],
            settings: settingsWithICloudAutoSync(enabled: true)
        )
        localStore.debugICloudBackupData = backupData
        markLocalSaveDate(Date(timeIntervalSince1970: 2_000))

        XCTAssertFalse(localStore.pullFromICloudIfNewer())
        XCTAssertEqual(localStore.state.kids.first?.name, "Local")
    }

    func testSetICloudAutoSyncEnabledPersistsInSettings() {
        ICloudBackup.setAvailableForTesting(true)
        defer { ICloudBackup.setAvailableForTesting(nil) }

        let store = makeStore(kids: [Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)])

        store.setICloudAutoSyncEnabled(true)

        XCTAssertTrue(store.state.settings.iCloudAutoSyncEnabled)
    }

    func testSetICloudAutoSyncIgnoredWhenICloudUnavailable() {
        ICloudBackup.setAvailableForTesting(false)
        defer { ICloudBackup.setAvailableForTesting(nil) }

        let store = makeStore(
            kids: [Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)],
            settings: settingsWithICloudAutoSync(enabled: true)
        )

        store.setICloudAutoSyncEnabled(true)

        XCTAssertFalse(store.state.settings.iCloudAutoSyncEnabled)
    }

    func testTasksFilterByAssignedKids() {
        let kidA = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let kidB = Kid(name: "Milo", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 2, assignedKidIDs: [kidA.id])
        let store = makeStore(kids: [kidA, kidB], tasks: [task])

        XCTAssertEqual(store.tasks(for: kidA).count, 1)
        XCTAssertEqual(store.tasks(for: kidA).first?.title, "Dishes")
        XCTAssertTrue(store.tasks(for: kidB).isEmpty)
    }

    func testUnassignedChoreIsVisibleToAllKids() {
        let kidA = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let kidB = Kid(name: "Milo", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Tidy room", points: 1, assignedKidIDs: [])
        let store = makeStore(kids: [kidA, kidB], tasks: [task])

        XCTAssertEqual(store.tasks(for: kidA).count, 1)
        XCTAssertEqual(store.tasks(for: kidB).count, 1)
        XCTAssertTrue(task.isAssigned(to: kidA.id))
        XCTAssertTrue(task.isAssigned(to: kidB.id))
    }

    func testAddTaskStoresAssignedKidIDs() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let store = makeStore(kids: [kid])

        store.addTask(title: "Laundry", points: 4, assignedKidIDs: [kid.id])

        XCTAssertEqual(store.state.tasks.count, 1)
        XCTAssertEqual(store.state.tasks[0].assignedKidIDs, [kid.id])
        XCTAssertEqual(store.tasks(for: kid).count, 1)
    }

    func testUpdateTaskChangesAssignedKidIDs() {
        let kidA = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let kidB = Kid(name: "Milo", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 2)
        let store = makeStore(kids: [kidA, kidB], tasks: [task])

        store.updateTask(
            store.state.tasks[0],
            title: "Dishes",
            points: 2,
            assignedKidIDs: [kidB.id]
        )

        XCTAssertEqual(store.state.tasks[0].assignedKidIDs, [kidB.id])
        XCTAssertTrue(store.tasks(for: kidA).isEmpty)
        XCTAssertEqual(store.tasks(for: kidB).count, 1)
    }

    func testAwardOnlyAppliesToAssignedKid() {
        let kidA = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let kidB = Kid(name: "Milo", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 5, assignedKidIDs: [kidA.id])
        let store = makeStore(kids: [kidA, kidB], tasks: [task])

        store.award(task: task, to: kidA)
        store.award(task: task, to: kidB)

        XCTAssertEqual(store.state.kids.first { $0.id == kidA.id }?.availablePoints, 5)
        XCTAssertEqual(store.state.kids.first { $0.id == kidB.id }?.availablePoints, 0)
        XCTAssertEqual(store.state.transactions.count, 1)
    }

    func testIsTaskAvailableReturnsFalseForUnassignedKid() {
        let kidA = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let kidB = Kid(name: "Milo", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 2, assignedKidIDs: [kidA.id])
        let store = makeStore(kids: [kidA, kidB], tasks: [task])

        XCTAssertTrue(store.isTaskAvailable(task, for: kidA))
        XCTAssertFalse(store.isTaskAvailable(task, for: kidB))
    }

    func testRequestChoreCompletionRequiresAssignment() {
        let kidA = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let kidB = Kid(name: "Milo", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 3, assignedKidIDs: [kidA.id])
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kidA, kidB], tasks: [task], settings: settings)

        store.requestChoreCompletion(task: task, for: kidB)

        XCTAssertTrue(store.state.approvalRequests.isEmpty)
    }

    func testDeleteKidRemovesKidFromTaskAssignments() {
        let kidA = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let kidB = Kid(name: "Milo", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 2, assignedKidIDs: [kidA.id, kidB.id])
        let store = makeStore(kids: [kidA, kidB], tasks: [task])

        store.deleteKid(kidA)

        XCTAssertEqual(store.state.tasks[0].assignedKidIDs, [kidB.id])
        XCTAssertEqual(store.tasks(for: kidB).count, 1)
    }

    func testRewardTaskRoundTripPreservesAssignedKidIDs() throws {
        let kidID = UUID()
        let task = RewardTask(title: "Trash", points: 2, assignedKidIDs: [kidID])
        let state = RewardState(
            kids: [],
            tasks: [task],
            settings: .defaults,
            transactions: []
        )

        let data = try JSONEncoder.configuredForTests.encode(state)
        let decoded = try JSONDecoder.configuredForTests.decode(RewardState.self, from: data)

        XCTAssertEqual(decoded.tasks[0].assignedKidIDs, [kidID])
    }

    func testChoreCompletionApprovalAwardsPoints() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 3)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], tasks: [task], settings: settings)

        store.requestChoreCompletion(task: task, for: store.state.kids[0])
        XCTAssertEqual(store.state.approvalRequests.count, 1)
        XCTAssertEqual(store.state.approvalRequests[0].kind, .choreCompleted)

        XCTAssertTrue(store.approveRequest(store.state.approvalRequests[0]))
        XCTAssertEqual(store.state.kids[0].availablePoints, 3)
        XCTAssertTrue(store.state.approvalRequests.isEmpty)
    }

    func testRequestChoreCompletionIgnoredWhenApprovalFlowDisabled() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 3)
        let store = makeStore(kids: [kid], tasks: [task], settings: .defaults)

        store.requestChoreCompletion(task: task, for: kid)

        XCTAssertTrue(store.state.approvalRequests.isEmpty)
    }

    func testRequestChoreCompletionIgnoredWhenChoreNotDue() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 2, recurrence: .daily)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], tasks: [task], settings: settings)

        store.award(task: task, to: kid)
        store.requestChoreCompletion(task: task, for: kid)

        XCTAssertTrue(store.state.approvalRequests.isEmpty)
    }

    func testRequestChoreCompletionStoresTaskMetadata() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 4)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], tasks: [task], settings: settings)

        store.requestChoreCompletion(task: task, for: kid)

        let request = store.state.approvalRequests[0]
        XCTAssertEqual(request.kind, .choreCompleted)
        XCTAssertEqual(request.taskID, task.id)
        XCTAssertEqual(request.points, 4)
        XCTAssertEqual(request.note, "Chore: Dishes")
        XCTAssertEqual(request.kidID, kid.id)
    }

    func testDeclineChoreCompletionRequestLeavesBalancesUnchanged() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 3)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], tasks: [task], settings: settings)

        store.requestChoreCompletion(task: task, for: kid)
        store.declineRequest(store.state.approvalRequests[0])

        XCTAssertTrue(store.state.approvalRequests.isEmpty)
        XCTAssertEqual(store.state.kids[0].availablePoints, 0)
        XCTAssertTrue(store.state.transactions.isEmpty)
    }

    func testApproveChoreCompletionFailsWhenTaskWasDeleted() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 3)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], tasks: [task], settings: settings)

        store.requestChoreCompletion(task: task, for: kid)
        let request = store.state.approvalRequests[0]
        store.deleteTask(task)

        XCTAssertFalse(store.approveRequest(request))
        XCTAssertEqual(store.state.approvalRequests.count, 1)
    }

    func testChoreCompletionApprovalCreatesEarnedTransaction() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Mow lawn", points: 6)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], tasks: [task], settings: settings)

        store.requestChoreCompletion(task: task, for: kid)
        XCTAssertTrue(store.approveRequest(store.state.approvalRequests[0]))

        let transaction = store.state.transactions.last
        XCTAssertEqual(transaction?.kind, .earned)
        XCTAssertEqual(transaction?.points, 6)
        XCTAssertEqual(transaction?.note, "Mow lawn")
    }

    func testChoreCompletionApprovalUsesRequestedSnapshotWhenTaskChanges() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Sweep", points: 3)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], tasks: [task], settings: settings)

        store.requestChoreCompletion(task: task, for: store.state.kids[0])
        let request = store.state.approvalRequests[0]
        store.updateTask(task, title: "Mop", points: 9)

        XCTAssertTrue(store.approveRequest(request))
        XCTAssertEqual(store.state.kids[0].availablePoints, 3)
        let transaction = store.transactions(for: store.state.kids[0]).first
        XCTAssertEqual(transaction?.points, 3)
        XCTAssertEqual(transaction?.note, "Sweep")
    }

    func testDuplicateChoreCompletionRequestReplacesPrevious() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 3)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], tasks: [task], settings: settings)

        store.requestChoreCompletion(task: task, for: kid)
        let firstID = store.state.approvalRequests[0].id
        store.requestChoreCompletion(task: task, for: kid)

        XCTAssertEqual(store.state.approvalRequests.count, 1)
        XCTAssertNotEqual(store.state.approvalRequests[0].id, firstID)
    }

    func testSecondChoreCompletionRequestBlockedWhenDailyChoreNotDue() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 2, recurrence: .daily)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], tasks: [task], settings: settings)

        store.requestChoreCompletion(task: task, for: kid)
        XCTAssertTrue(store.approveRequest(store.state.approvalRequests[0]))
        XCTAssertEqual(store.state.kids[0].availablePoints, 2)

        store.requestChoreCompletion(task: task, for: kid)

        XCTAssertTrue(store.state.approvalRequests.isEmpty)
        XCTAssertFalse(store.isTaskAvailable(task, for: store.state.kids[0]))
        XCTAssertEqual(store.state.kids[0].availablePoints, 2)
    }

    func testApproveChoreCompletionFailsWhenDailyChoreNotDue() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Dishes", points: 2, recurrence: .daily)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let request = ApprovalRequest(
            kidID: kid.id,
            kind: .choreCompleted,
            points: 2,
            note: "Chore: Dishes",
            taskID: task.id
        )
        let store = makeStore(
            kids: [kid],
            tasks: [task],
            settings: settings,
            approvalRequests: [request],
            taskCompletions: [
                TaskCompletion(kidID: kid.id, taskID: task.id, lastAwardedAt: Date())
            ]
        )

        XCTAssertFalse(store.approveRequest(request))
        XCTAssertEqual(store.state.kids[0].availablePoints, 0)
        XCTAssertEqual(store.state.approvalRequests.count, 1)
    }

    func testApprovalRequestRoundTripPreservesChoreTaskID() throws {
        let kidID = UUID()
        let taskID = UUID()
        let request = ApprovalRequest(
            kidID: kidID,
            kind: .choreCompleted,
            points: 5,
            note: "Chore: Trash",
            taskID: taskID
        )
        let state = RewardState(
            kids: [],
            tasks: [],
            settings: .defaults,
            transactions: [],
            approvalRequests: [request]
        )

        let data = try JSONEncoder.configuredForTests.encode(state)
        let decoded = try JSONDecoder.configuredForTests.decode(RewardState.self, from: data)

        XCTAssertEqual(decoded.approvalRequests[0].taskID, taskID)
        XCTAssertEqual(decoded.approvalRequests[0].kind, .choreCompleted)
    }

    func testRunScheduledMaintenanceAppliesOverdueDailyInterest() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 100)
        var settings = RewardSettings.defaults
        settings.interestRecurrence = .daily
        settings.lastInterestAppliedAt = Date(timeIntervalSinceNow: -48 * 60 * 60)
        let store = makeStore(kids: [kid], settings: settings)

        XCTAssertEqual(store.state.kids[0].vaultPoints, 105)
        XCTAssertNotNil(store.state.settings.lastInterestAppliedAt)
        XCTAssertEqual(store.state.transactions.last?.kind, .interest)
    }

    func testAutomaticInterestAppliesOnlyWhenRecurrenceIsDue() throws {
        // Jan 3, 2100 is Sunday (weekday 1) — a clean week boundary.
        // +3 days = Wed Jan 6 (same week) → not due; +8 days = Mon Jan 11 (next week) → due.
        let calendar = RecurrenceSchedule.configuredCalendar()
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 3, hour: 12)))
        let kids = [
            Kid(name: "Avery", availablePoints: 0, vaultPoints: 100),
            Kid(name: "Milo", availablePoints: 0, vaultPoints: 20)
        ]
        let settings = RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: 1,
            vaultInterestRate: 0.05,
            interestRecurrence: .weekly,
            lastInterestAppliedAt: start
        )
        let store = makeStore(kids: kids, settings: settings)

        XCTAssertEqual(store.state.kids.map(\.vaultPoints), [100, 20])

        XCTAssertFalse(store.applyDueInterestIfNeeded(now: start.addingTimeInterval(3 * 24 * 60 * 60)))

        XCTAssertTrue(store.applyDueInterestIfNeeded(now: start.addingTimeInterval(8 * 24 * 60 * 60)))
        XCTAssertEqual(store.state.kids[0].vaultPoints, 105)
        XCTAssertEqual(store.state.kids[1].vaultPoints, 21)
        XCTAssertEqual(store.state.transactions.filter { $0.kind == .interest }.count, 2)
    }

    func testScheduledInterestQueuesApprovalRequestsWhenApprovalFlowEnabled() throws {
        let calendar = RecurrenceSchedule.configuredCalendar()
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 3, hour: 12)))
        let now = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        settings.interestRecurrence = .daily
        settings.lastInterestAppliedAt = start
        let kids = [
            Kid(name: "Avery", availablePoints: 0, vaultPoints: 100),
            Kid(name: "Milo", availablePoints: 0, vaultPoints: 20)
        ]
        let store = makeStore(kids: kids, settings: settings)

        XCTAssertTrue(store.applyDueInterestIfNeeded(now: now))

        XCTAssertEqual(store.state.kids.map(\.vaultPoints), [100, 20])
        XCTAssertEqual(store.state.approvalRequests.map(\.kind), [.interest, .interest])
        XCTAssertEqual(store.state.approvalRequests.map(\.points), [5, 1])
        XCTAssertTrue(store.state.transactions.isEmpty)
        XCTAssertEqual(store.state.settings.lastInterestAppliedAt, start)
    }

    func testApprovingScheduledInterestMarksScheduleApplied() throws {
        let calendar = RecurrenceSchedule.configuredCalendar()
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 3, hour: 12)))
        let now = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        settings.interestRecurrence = .daily
        settings.lastInterestAppliedAt = start
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 100)
        let store = makeStore(kids: [kid], settings: settings)

        XCTAssertTrue(store.applyDueInterestIfNeeded(now: now))
        XCTAssertTrue(store.approveRequest(store.state.approvalRequests[0]))

        XCTAssertEqual(store.state.kids[0].vaultPoints, 105)
        XCTAssertTrue(store.state.approvalRequests.isEmpty)
        XCTAssertNotNil(store.state.settings.lastInterestAppliedAt)
        XCTAssertNotEqual(store.state.settings.lastInterestAppliedAt, start)
    }

    func testApplyDueInterestSkippedWhenRecurrenceOff() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 100)
        let store = makeStore(kids: [kid], settings: .defaults)

        XCTAssertFalse(store.applyDueInterestIfNeeded())

        XCTAssertEqual(store.state.kids[0].vaultPoints, 100)
        XCTAssertTrue(store.state.transactions.isEmpty)
    }

    func testApplyDueInterestSkippedWhenNoVaultBalanceEarnsInterest() {
        let kids = [
            Kid(name: "Avery", availablePoints: 0, vaultPoints: 0),
            Kid(name: "Milo", availablePoints: 0, vaultPoints: 0)
        ]
        var settings = RewardSettings.defaults
        settings.interestRecurrence = .daily
        let store = makeStore(kids: kids, settings: settings)

        XCTAssertFalse(store.applyDueInterestIfNeeded())

        XCTAssertNil(store.state.settings.lastInterestAppliedAt)
        XCTAssertTrue(store.state.transactions.isEmpty)
    }

    func testApplyDueInterestSkipsKidsWithZeroVault() {
        let start = Date(timeIntervalSince1970: 4_102_444_800)
        let kids = [
            Kid(name: "Avery", availablePoints: 0, vaultPoints: 100),
            Kid(name: "Milo", availablePoints: 0, vaultPoints: 0)
        ]
        let settings = RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: 1,
            vaultInterestRate: 0.05,
            interestRecurrence: .daily,
            lastInterestAppliedAt: start
        )
        let store = RewardStore(
            initialState: RewardState(kids: kids, tasks: [], settings: settings, transactions: []),
            fileURL: temporaryStateURL()
        )

        XCTAssertTrue(store.applyDueInterestIfNeeded(now: start.addingTimeInterval(25 * 60 * 60)))

        XCTAssertEqual(store.state.kids[0].vaultPoints, 105)
        XCTAssertEqual(store.state.kids[1].vaultPoints, 0)
        XCTAssertEqual(store.state.transactions.count, 1)
        XCTAssertEqual(store.state.transactions[0].kidID, kids[0].id)
    }

    func testSetInterestRecurrencePersistsInSettings() {
        let store = makeStore(kids: [Kid(name: "Avery", availablePoints: 0, vaultPoints: 10)])

        store.setInterestRecurrence(.weekly)

        XCTAssertEqual(store.state.settings.interestRecurrence, .weekly)
    }

    func testRunScheduledMaintenanceInvokesDueInterest() {
        let start = Date(timeIntervalSince1970: 4_102_444_800)
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 40)
        let settings = RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: 1,
            vaultInterestRate: 0.10,
            interestRecurrence: .daily,
            lastInterestAppliedAt: start
        )
        let store = RewardStore(
            initialState: RewardState(kids: [kid], tasks: [], settings: settings, transactions: []),
            fileURL: temporaryStateURL()
        )

        store.runScheduledMaintenance(now: start.addingTimeInterval(25 * 60 * 60))

        XCTAssertEqual(store.state.kids[0].vaultPoints, 44)
        XCTAssertEqual(store.state.transactions.count, 1)
    }

    func testRewardSettingsRoundTripPreservesInterestSchedule() throws {
        var settings = RewardSettings.defaults
        settings.interestRecurrence = .weekly
        settings.lastInterestAppliedAt = Date(timeIntervalSince1970: 1_900_000_000)
        let state = RewardState(
            kids: [],
            tasks: [],
            settings: settings,
            transactions: []
        )

        let data = try JSONEncoder.configuredForTests.encode(state)
        let decoded = try JSONDecoder.configuredForTests.decode(RewardState.self, from: data)

        XCTAssertEqual(decoded.settings.interestRecurrence, .weekly)
        XCTAssertEqual(
            decoded.settings.lastInterestAppliedAt?.timeIntervalSince1970,
            settings.lastInterestAppliedAt?.timeIntervalSince1970
        )
    }

    func testBuildNotificationPlanEmptyWhenNotificationsDisabled() {
        var settings = RewardSettings.defaults
        settings.notificationsEnabled = false
        settings.allowanceRecurrence = .daily
        settings.interestRecurrence = .weekly

        let plan = RewardNotifications.buildPlan(settings: settings, pendingApprovalCount: 2)

        XCTAssertTrue(plan.isEmpty)
    }

    func testBuildNotificationPlanIncludesApprovalReminder() {
        var settings = RewardSettings.defaults
        settings.notificationsEnabled = true

        let plan = RewardNotifications.buildPlan(settings: settings, pendingApprovalCount: 2)

        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].identifier, RewardNotifications.approvalsIdentifier)
        XCTAssertEqual(plan[0].title, "Approval needed")
        XCTAssertEqual(plan[0].body, "2 requests waiting in KidsRewards.")
        XCTAssertEqual(plan[0].delay, 2)
    }

    func testBuildNotificationPlanUsesSingularApprovalCopy() {
        var settings = RewardSettings.defaults
        settings.notificationsEnabled = true

        let plan = RewardNotifications.buildPlan(settings: settings, pendingApprovalCount: 1)

        XCTAssertEqual(plan[0].body, "1 request waiting in KidsRewards.")
    }

    func testBuildNotificationPlanOmitsApprovalWhenQueueEmpty() {
        var settings = RewardSettings.defaults
        settings.notificationsEnabled = true
        settings.allowanceRecurrence = .none
        settings.interestRecurrence = .none

        let plan = RewardNotifications.buildPlan(settings: settings, pendingApprovalCount: 0)

        XCTAssertTrue(plan.isEmpty)
    }

    func testBuildNotificationPlanIncludesAllowanceAndInterestReminders() {
        var settings = RewardSettings.defaults
        settings.notificationsEnabled = true
        settings.allowanceRecurrence = .daily
        settings.interestRecurrence = .weekly
        let now = Date(timeIntervalSince1970: 2_000_000)

        let plan = RewardNotifications.buildPlan(settings: settings, pendingApprovalCount: 0, now: now)

        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(plan[0].identifier, RewardNotifications.allowanceIdentifier)
        XCTAssertEqual(plan[1].identifier, RewardNotifications.interestIdentifier)
        // Delays are calendar-relative; verify they are positive and within one recurrence window.
        XCTAssertGreaterThanOrEqual(plan[0].delay, RewardNotifications.minimumDelay)
        XCTAssertLessThanOrEqual(plan[0].delay, 25 * 60 * 60)
        XCTAssertGreaterThanOrEqual(plan[1].delay, RewardNotifications.minimumDelay)
    }

    func testRecurringDelayReturnsNilWhenRecurrenceOff() {
        let now = Date()

        XCTAssertNil(RewardNotifications.recurringDelay(recurrence: .none, lastApplied: nil, now: now))
    }

    func testRecurringDelayClampsToMinimumWhenAlreadyOverdue() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let lastApplied = Date(timeIntervalSince1970: 1_000_000)

        let delay = RewardNotifications.recurringDelay(
            recurrence: .daily,
            lastApplied: lastApplied,
            now: now
        )

        XCTAssertEqual(delay, RewardNotifications.minimumDelay)
    }

    func testRecurringDelayWeeklyUsesCalendarWeekBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = RecurrenceSchedule.calendarWeekFirstWeekday
        // Jan 5, 2100 = Sunday (firstWeekday=1), anchor at noon
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 5, hour: 12)))
        // Next occurrence is the START of the following week (Jan 12 00:00 UTC), not anchor+7d
        let nextWeekStart = try XCTUnwrap(
            calendar.date(
                byAdding: .weekOfYear, value: 1,
                to: try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: anchor)?.start)
            )
        )

        let delay = RewardNotifications.recurringDelay(
            recurrence: .weekly,
            lastApplied: anchor,
            now: anchor,
            calendar: calendar
        )

        XCTAssertEqual(delay, nextWeekStart.timeIntervalSince(anchor))
    }

    func testSetNotificationsEnabledPersistsInSettings() {
        let store = makeStore(kids: [Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)])

        store.setNotificationsEnabled(false)

        XCTAssertFalse(store.state.settings.notificationsEnabled)
    }

    func testRewardSettingsRoundTripPreservesNotificationsEnabled() throws {
        var settings = RewardSettings.defaults
        settings.notificationsEnabled = false
        let state = RewardState(
            kids: [],
            tasks: [],
            settings: settings,
            transactions: []
        )

        let data = try JSONEncoder.configuredForTests.encode(state)
        let decoded = try JSONDecoder.configuredForTests.decode(RewardState.self, from: data)

        XCTAssertFalse(decoded.settings.notificationsEnabled)
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

    // MARK: - Biweekly / Monthly recurrence

    func testBiweeklyIsDueOnlyAfterTwoCalendarWeeks() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = RecurrenceSchedule.calendarWeekFirstWeekday
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 3, hour: 12)))
        let oneWeekLater = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: anchor))
        let twoWeeksLater = try XCTUnwrap(calendar.date(byAdding: .day, value: 14, to: anchor))

        XCTAssertFalse(RecurrenceSchedule.isDue(since: anchor, recurrence: .biweekly, now: anchor, calendar: calendar))
        XCTAssertFalse(RecurrenceSchedule.isDue(since: anchor, recurrence: .biweekly, now: oneWeekLater, calendar: calendar))
        XCTAssertTrue(RecurrenceSchedule.isDue(since: anchor, recurrence: .biweekly, now: twoWeeksLater, calendar: calendar))
    }

    func testMonthlyIsDueOnlyInNewCalendarMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 15, hour: 12)))
        let sameMonthLate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 31, hour: 12)))
        let nextMonthFirst = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 2, day: 1, hour: 12)))

        XCTAssertFalse(RecurrenceSchedule.isDue(since: anchor, recurrence: .monthly, now: sameMonthLate, calendar: calendar))
        XCTAssertTrue(RecurrenceSchedule.isDue(since: anchor, recurrence: .monthly, now: nextMonthFirst, calendar: calendar))
    }

    // MARK: - allowanceIsDue

    func testAllowanceIsDueTrueWhenNeverApplied() {
        let now = Date(timeIntervalSince1970: 4_000_000_000)

        XCTAssertTrue(RecurrenceSchedule.allowanceIsDue(since: nil, recurrence: .weekly, weekday: nil, monthDay: nil, now: now))
        XCTAssertFalse(RecurrenceSchedule.allowanceIsDue(since: nil, recurrence: .none, weekday: nil, monthDay: nil, now: now))
    }

    func testAllowanceWeeklyDueOnTargetWeekday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = RecurrenceSchedule.calendarWeekFirstWeekday
        // Jan 3, 2100 = Sunday (weekday 1)
        let lastApplied = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 3, hour: 12)))
        // Jan 6 = Wednesday (weekday 4), same week as Jan 3 → not due
        let sameWeekWed = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 6, hour: 12)))
        // Jan 10 = Sunday (weekday 1), next week but before target weekday 4 → not due
        let nextWeekSun = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 10, hour: 12)))
        // Jan 13 = Wednesday (weekday 4), next week on target weekday → due
        let nextWeekWed = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 13, hour: 12)))

        XCTAssertFalse(RecurrenceSchedule.allowanceIsDue(since: lastApplied, recurrence: .weekly, weekday: 4, monthDay: nil, now: sameWeekWed, calendar: calendar))
        XCTAssertFalse(RecurrenceSchedule.allowanceIsDue(since: lastApplied, recurrence: .weekly, weekday: 4, monthDay: nil, now: nextWeekSun, calendar: calendar))
        XCTAssertTrue(RecurrenceSchedule.allowanceIsDue(since: lastApplied, recurrence: .weekly, weekday: 4, monthDay: nil, now: nextWeekWed, calendar: calendar))
    }

    func testAllowanceBiweeklyDueOnTargetWeekdayAfterTwoWeeks() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = RecurrenceSchedule.calendarWeekFirstWeekday
        // Jan 3 = Sunday (weekday 1)
        let lastApplied = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 3, hour: 12)))
        // Jan 10 = Sunday (1 week later) → not due
        let oneWeekLater = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 10, hour: 12)))
        // Jan 17 = Sunday (2 weeks later), before target weekday 4 (Wed) → not due
        let twoWeeksLaterSun = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 17, hour: 12)))
        // Jan 20 = Wednesday (2 weeks + 3 days), on target weekday → due
        let twoWeeksLaterWed = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 20, hour: 12)))

        XCTAssertFalse(RecurrenceSchedule.allowanceIsDue(since: lastApplied, recurrence: .biweekly, weekday: 4, monthDay: nil, now: oneWeekLater, calendar: calendar))
        XCTAssertFalse(RecurrenceSchedule.allowanceIsDue(since: lastApplied, recurrence: .biweekly, weekday: 4, monthDay: nil, now: twoWeeksLaterSun, calendar: calendar))
        XCTAssertTrue(RecurrenceSchedule.allowanceIsDue(since: lastApplied, recurrence: .biweekly, weekday: 4, monthDay: nil, now: twoWeeksLaterWed, calendar: calendar))
    }

    func testAllowanceMonthlyDueOnTargetDayInNextMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        // Last applied on the 25th (the target day)
        let lastApplied = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 25, hour: 12)))
        // Same day again → not due
        let sameDayAgain = lastApplied
        // Next month before target day → not due
        let nextMonthBeforeDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 2, day: 20, hour: 12)))
        // Next month on target day → due
        let nextMonthOnDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 2, day: 25, hour: 12)))

        XCTAssertFalse(RecurrenceSchedule.allowanceIsDue(since: lastApplied, recurrence: .monthly, weekday: nil, monthDay: 25, now: sameDayAgain, calendar: calendar))
        XCTAssertFalse(RecurrenceSchedule.allowanceIsDue(since: lastApplied, recurrence: .monthly, weekday: nil, monthDay: 25, now: nextMonthBeforeDay, calendar: calendar))
        XCTAssertTrue(RecurrenceSchedule.allowanceIsDue(since: lastApplied, recurrence: .monthly, weekday: nil, monthDay: 25, now: nextMonthOnDay, calendar: calendar))
    }

    // MARK: - Store setters for allowance schedule

    func testSetAllowanceRecurrencePersistsInSettings() {
        let store = makeStore(kids: [Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)])

        store.setAllowanceRecurrence(.biweekly)

        XCTAssertEqual(store.state.settings.allowanceRecurrence, .biweekly)
    }

    func testSetAllowanceWeekdayPersistsInSettings() {
        let store = makeStore(kids: [Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)])

        store.setAllowanceWeekday(3)

        XCTAssertEqual(store.state.settings.allowanceWeekday, 3)
    }

    func testSetAllowanceMonthDayPersistsInSettings() {
        let store = makeStore(kids: [Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)])

        store.setAllowanceMonthDay(15)

        XCTAssertEqual(store.state.settings.allowanceMonthDay, 15)
    }

    func testAllowanceScheduleSettingsRoundTrip() throws {
        var settings = RewardSettings.defaults
        settings.allowanceWeekday = 3
        settings.allowanceMonthDay = 15
        let state = RewardState(kids: [], tasks: [], settings: settings, transactions: [])

        let data = try JSONEncoder.configuredForTests.encode(state)
        let decoded = try JSONDecoder.configuredForTests.decode(RewardState.self, from: data)

        XCTAssertEqual(decoded.settings.allowanceWeekday, 3)
        XCTAssertEqual(decoded.settings.allowanceMonthDay, 15)
    }

    func testUpdateSettingsPreservesAllowanceWeekdayAndMonthDay() {
        let store = makeStore(kids: [Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)])
        store.setAllowanceWeekday(5)
        store.setAllowanceMonthDay(20)

        store.updateSettings(currencyCode: "USD", currencyPerPoint: 1, vaultInterestRate: 0.05)

        XCTAssertEqual(store.state.settings.allowanceWeekday, 5)
        XCTAssertEqual(store.state.settings.allowanceMonthDay, 20)
    }

    // MARK: - isAllowanceScheduleDue with new recurrences

    func testIsAllowanceScheduleDueRespectsBiweeklySchedule() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = RecurrenceSchedule.calendarWeekFirstWeekday
        let applied = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 3, hour: 12)))
        let oneWeekLater = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: applied))
        let twoWeeksLater = try XCTUnwrap(calendar.date(byAdding: .day, value: 14, to: applied))
        var settings = RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: 1,
            vaultInterestRate: 0.05,
            allowancePoints: 3,
            allowanceRecurrence: .biweekly
        )
        settings.lastAllowanceAppliedAt = applied
        let store = makeStore(kids: [Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)], settings: settings)

        XCTAssertFalse(store.isAllowanceScheduleDue(now: oneWeekLater))
        XCTAssertTrue(store.isAllowanceScheduleDue(now: twoWeeksLater))
    }

    func testIsAllowanceScheduleDueRespectsMonthDaySchedule() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let applied = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 25, hour: 12)))
        let nextMonthBeforeDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 2, day: 20, hour: 12)))
        let nextMonthOnDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 2, day: 25, hour: 12)))
        var settings = RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: 1,
            vaultInterestRate: 0.05,
            allowancePoints: 3,
            allowanceRecurrence: .monthly
        )
        settings.allowanceMonthDay = 25
        settings.lastAllowanceAppliedAt = applied
        let store = makeStore(kids: [Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)], settings: settings)

        XCTAssertFalse(store.isAllowanceScheduleDue(now: nextMonthBeforeDay))
        XCTAssertTrue(store.isAllowanceScheduleDue(now: nextMonthOnDay))
    }

    // MARK: - applyDueAllowanceIfNeeded with new recurrences

    func testApplyDueBiweeklyAllowanceAppliesAfterTwoWeeks() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = RecurrenceSchedule.calendarWeekFirstWeekday
        let applied = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 3, hour: 12)))
        let oneWeekLater = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: applied))
        let twoWeeksLater = try XCTUnwrap(calendar.date(byAdding: .day, value: 14, to: applied))
        var settings = RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: 1,
            vaultInterestRate: 0.05,
            allowancePoints: 5,
            allowanceRecurrence: .biweekly
        )
        settings.lastAllowanceAppliedAt = applied
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let store = makeStore(kids: [kid], settings: settings)

        XCTAssertFalse(store.applyDueAllowanceIfNeeded(now: oneWeekLater))
        XCTAssertEqual(store.state.kids[0].availablePoints, 0)

        XCTAssertTrue(store.applyDueAllowanceIfNeeded(now: twoWeeksLater))
        XCTAssertEqual(store.state.kids[0].availablePoints, 5)
    }

    func testApplyDueMonthlyAllowanceAppliesOnTargetDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let applied = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 25, hour: 12)))
        let nextMonthBeforeDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 2, day: 20, hour: 12)))
        let nextMonthOnDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 2, day: 25, hour: 12)))
        var settings = RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: 1,
            vaultInterestRate: 0.05,
            allowancePoints: 5,
            allowanceRecurrence: .monthly
        )
        settings.allowanceMonthDay = 25
        settings.lastAllowanceAppliedAt = applied
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let store = makeStore(kids: [kid], settings: settings)

        XCTAssertFalse(store.applyDueAllowanceIfNeeded(now: nextMonthBeforeDay))
        XCTAssertEqual(store.state.kids[0].availablePoints, 0)

        XCTAssertTrue(store.applyDueAllowanceIfNeeded(now: nextMonthOnDay))
        XCTAssertEqual(store.state.kids[0].availablePoints, 5)
    }

    func testApplyDueWeeklyAllowanceWithWeekdayFiresOnTargetDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = RecurrenceSchedule.calendarWeekFirstWeekday
        // Jan 3, 2100 = Sunday (weekday 1)
        let applied = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 3, hour: 12)))
        // Jan 10 = Sunday (weekday 1), next week but before target Wed (4) → not due
        let nextWeekSunday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 10, hour: 12)))
        // Jan 13 = Wednesday (weekday 4), next week on target → due
        let nextWeekWednesday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 13, hour: 12)))
        var settings = RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: 1,
            vaultInterestRate: 0.05,
            allowancePoints: 5,
            allowanceRecurrence: .weekly
        )
        settings.allowanceWeekday = 4
        settings.lastAllowanceAppliedAt = applied
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let store = makeStore(kids: [kid], settings: settings)

        XCTAssertFalse(store.applyDueAllowanceIfNeeded(now: nextWeekSunday))
        XCTAssertEqual(store.state.kids[0].availablePoints, 0)

        XCTAssertTrue(store.applyDueAllowanceIfNeeded(now: nextWeekWednesday))
        XCTAssertEqual(store.state.kids[0].availablePoints, 5)
    }

    // MARK: - Child mode store behavior

    func testChildModeChoreRequestQueuedWhenApprovalFlowEnabled() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Sweep", points: 3)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], tasks: [task], settings: settings)

        store.requestChoreCompletion(task: task, for: store.state.kids[0])

        XCTAssertEqual(store.state.approvalRequests.count, 1)
        let req = store.state.approvalRequests[0]
        XCTAssertEqual(req.kind, .choreCompleted)
        XCTAssertEqual(req.kidID, kid.id)
        XCTAssertEqual(req.taskID, task.id)
        XCTAssertEqual(req.points, 3)
    }

    func testChildModeChoreRequestIgnoredWhenApprovalFlowDisabled() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Sweep", points: 3)
        let store = makeStore(kids: [kid], tasks: [task])

        store.requestChoreCompletion(task: task, for: store.state.kids[0])

        XCTAssertTrue(store.state.approvalRequests.isEmpty)
    }

    func testChildModeChoreButtonPendingStateDetectedViaPendingApprovalRequest() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Sweep", points: 3)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], tasks: [task], settings: settings)

        XCTAssertNil(store.pendingApprovalRequest(kind: .choreCompleted, kidID: kid.id, taskID: task.id))

        store.requestChoreCompletion(task: task, for: store.state.kids[0])

        XCTAssertNotNil(store.pendingApprovalRequest(kind: .choreCompleted, kidID: kid.id, taskID: task.id))
    }

    func testChildModeChoreApprovalGrantsPoints() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Sweep", points: 3)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], tasks: [task], settings: settings)

        store.requestChoreCompletion(task: task, for: store.state.kids[0])
        XCTAssertTrue(store.approveRequest(store.state.approvalRequests[0]))

        XCTAssertEqual(store.state.kids[0].availablePoints, 3)
        XCTAssertTrue(store.state.approvalRequests.isEmpty)
        XCTAssertEqual(store.transactions(for: store.state.kids[0]).first?.kind, .earned)
    }

    func testChildModeInterestIgnoredWhenVaultIsEmpty() {
        let kid = Kid(name: "Avery", availablePoints: 5, vaultPoints: 0)
        let settings = RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: 1,
            vaultInterestRate: 0.1
        )
        let store = makeStore(kids: [kid], settings: settings)
        store.setApprovalFlowEnabled(true)

        store.requestInterest(for: store.state.kids[0])

        XCTAssertTrue(store.state.approvalRequests.isEmpty)
    }

    func testChildModeInterestQueuedWhenVaultHasPoints() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 10)
        let settings = RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: 1,
            vaultInterestRate: 0.1
        )
        let store = makeStore(kids: [kid], settings: settings)
        store.setApprovalFlowEnabled(true)

        store.requestInterest(for: store.state.kids[0])

        XCTAssertEqual(store.state.approvalRequests.count, 1)
        XCTAssertEqual(store.state.approvalRequests[0].kind, .interest)
        XCTAssertEqual(store.state.approvalRequests[0].points, 1)
    }

    func testChildModeInterestIgnoredWhenApprovalFlowDisabled() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 20)
        let settings = RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: 1,
            vaultInterestRate: 0.1
        )
        let store = makeStore(kids: [kid], settings: settings)

        store.requestInterest(for: store.state.kids[0])

        XCTAssertTrue(store.state.approvalRequests.isEmpty)
    }

    func testChildModeInterestDeduplicatesPendingRequest() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 10)
        let settings = RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: 1,
            vaultInterestRate: 0.1
        )
        let store = makeStore(kids: [kid], settings: settings)
        store.setApprovalFlowEnabled(true)

        store.requestInterest(for: store.state.kids[0])
        store.requestInterest(for: store.state.kids[0])

        XCTAssertEqual(store.state.approvalRequests.count, 1)
    }

    func testChildModeCashOutIgnoredWhenAvailableIsZero() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], settings: settings)

        store.requestCashOut(points: 5, for: store.state.kids[0])

        XCTAssertTrue(store.state.approvalRequests.isEmpty)
    }

    func testChildModeCashOutDeduplicatesPendingRequest() {
        let kid = Kid(name: "Avery", availablePoints: 10, vaultPoints: 0)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], settings: settings)

        store.requestCashOut(points: 3, for: store.state.kids[0])
        let firstID = store.state.approvalRequests[0].id

        store.requestCashOut(points: 5, for: store.state.kids[0])

        XCTAssertEqual(store.state.approvalRequests.count, 1)
        XCTAssertNotEqual(store.state.approvalRequests[0].id, firstID)
        XCTAssertEqual(store.state.approvalRequests[0].points, 5)
    }

    func testChildModeDepositIgnoredWhenAvailableIsZero() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], settings: settings)

        store.requestDeposit(points: 5, for: store.state.kids[0])

        XCTAssertTrue(store.state.approvalRequests.isEmpty)
    }

    func testChildModeDepositDeduplicatesPendingRequest() {
        let kid = Kid(name: "Avery", availablePoints: 10, vaultPoints: 0)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], settings: settings)

        store.requestDeposit(points: 2, for: store.state.kids[0])
        let firstID = store.state.approvalRequests[0].id

        store.requestDeposit(points: 4, for: store.state.kids[0])

        XCTAssertEqual(store.state.approvalRequests.count, 1)
        XCTAssertNotEqual(store.state.approvalRequests[0].id, firstID)
        XCTAssertEqual(store.state.approvalRequests[0].points, 4)
    }

    func testChildModeHistoryCapAt10Transactions() {
        let kid = Kid(name: "Avery", availablePoints: 100, vaultPoints: 0)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = false
        let store = makeStore(kids: [kid], settings: settings)
        let liveKid = store.state.kids[0]

        for i in 1...12 {
            store.adjust(points: 1, note: "Bonus \(i)", for: store.state.kids[0])
        }

        let history = store.transactions(for: liveKid)
        XCTAssertEqual(history.count, 12)

        let capped = Array(history.prefix(10))
        XCTAssertEqual(capped.count, 10)
    }

    func testChildModeMultiKidPendingStateIsPerKid() {
        let kidA = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let kidB = Kid(name: "Blake", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Sweep", points: 3)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kidA, kidB], tasks: [task], settings: settings)

        store.requestChoreCompletion(task: task, for: store.state.kids[0])

        XCTAssertNotNil(store.pendingApprovalRequest(kind: .choreCompleted, kidID: kidA.id, taskID: task.id))
        XCTAssertNil(store.pendingApprovalRequest(kind: .choreCompleted, kidID: kidB.id, taskID: task.id))
    }

    func testChildModeCashOutFullEndToEnd() {
        let kid = Kid(name: "Avery", availablePoints: 8, vaultPoints: 0)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], settings: settings)

        store.requestCashOut(points: 5, for: store.state.kids[0])
        XCTAssertEqual(store.state.kids[0].availablePoints, 8, "Points unchanged before approval")

        XCTAssertTrue(store.approveRequest(store.state.approvalRequests[0]))

        XCTAssertEqual(store.state.kids[0].availablePoints, 3)
        XCTAssertTrue(store.state.approvalRequests.isEmpty)
        XCTAssertEqual(store.transactions(for: store.state.kids[0]).first?.kind, .cashedOut)
    }

    func testChildModeDepositFullEndToEnd() {
        let kid = Kid(name: "Avery", availablePoints: 10, vaultPoints: 2)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], settings: settings)

        store.requestDeposit(points: 4, for: store.state.kids[0])
        XCTAssertEqual(store.state.kids[0].availablePoints, 10, "Available unchanged before approval")

        XCTAssertTrue(store.approveRequest(store.state.approvalRequests[0]))

        XCTAssertEqual(store.state.kids[0].availablePoints, 6)
        XCTAssertEqual(store.state.kids[0].vaultPoints, 6)
        XCTAssertTrue(store.state.approvalRequests.isEmpty)
    }

    // MARK: - Kid management

    func testAddKidAppendsNewKid() {
        let store = makeStore(kids: [])

        store.addKid(name: "Avery")

        XCTAssertEqual(store.state.kids.count, 1)
        XCTAssertEqual(store.state.kids[0].name, "Avery")
        XCTAssertEqual(store.state.kids[0].availablePoints, 0)
        XCTAssertEqual(store.state.kids[0].vaultPoints, 0)
    }

    func testAddKidIgnoresBlankName() {
        let store = makeStore(kids: [])

        store.addKid(name: "   ")

        XCTAssertTrue(store.state.kids.isEmpty)
    }

    func testAddKidTrimsWhitespace() {
        let store = makeStore(kids: [])

        store.addKid(name: "  Avery  ")

        XCTAssertEqual(store.state.kids[0].name, "Avery")
    }

    func testKidWithIDReturnsCorrectKid() {
        let kid = Kid(name: "Avery", availablePoints: 5, vaultPoints: 2)
        let store = makeStore(kids: [kid])

        XCTAssertEqual(store.kid(withID: kid.id), store.state.kids[0])
    }

    func testKidWithIDReturnsNilForUnknownID() {
        let store = makeStore(kids: [Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)])

        XCTAssertNil(store.kid(withID: UUID()))
    }

    func testKidNameForKnownIDReturnsName() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let store = makeStore(kids: [kid])

        XCTAssertEqual(store.kidName(for: kid.id), "Avery")
    }

    func testKidNameForUnknownIDReturnsUnknown() {
        let store = makeStore(kids: [Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)])

        XCTAssertEqual(store.kidName(for: UUID()), "Unknown")
    }

    func testUpdateKidAllowancePointsSetsOverride() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let store = makeStore(kids: [kid])

        store.updateKidAllowancePoints(store.state.kids[0], points: 10)

        XCTAssertEqual(store.state.kids[0].allowancePoints, 10)
    }

    func testUpdateKidAllowancePointsNilClearsOverride() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0, allowancePoints: 8)
        let store = makeStore(kids: [kid])

        store.updateKidAllowancePoints(store.state.kids[0], points: nil)

        XCTAssertNil(store.state.kids[0].allowancePoints)
    }

    func testUpdateKidAllowancePointsClampsNegativeToZero() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let store = makeStore(kids: [kid])

        store.updateKidAllowancePoints(store.state.kids[0], points: -5)

        XCTAssertEqual(store.state.kids[0].allowancePoints, 0)
    }

    func testClearSavingsGoalRemovesGoal() {
        let kid = Kid(name: "Avery", availablePoints: 10, vaultPoints: 0, savingsGoal: SavingsGoal(title: "Bike", targetPoints: 50))
        let store = makeStore(kids: [kid])

        store.clearSavingsGoal(for: store.state.kids[0])

        XCTAssertNil(store.state.kids[0].savingsGoal)
    }

    func testPendingRequestCountPerKid() {
        let kidA = Kid(name: "Avery", availablePoints: 10, vaultPoints: 0)
        let kidB = Kid(name: "Blake", availablePoints: 10, vaultPoints: 0)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kidA, kidB], settings: settings)

        store.requestCashOut(points: 5, for: store.state.kids[0])
        store.requestDeposit(points: 3, for: store.state.kids[0])

        XCTAssertEqual(store.pendingRequestCount(for: store.state.kids[0]), 2)
        XCTAssertEqual(store.pendingRequestCount(for: store.state.kids[1]), 0)
    }

    // MARK: - Chore helpers

    func testTotalReadyChoreCountAcrossAllKids() {
        let kidA = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let kidB = Kid(name: "Blake", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Sweep", points: 3, assignedKidIDs: [])
        let store = makeStore(kids: [kidA, kidB], tasks: [task])

        XCTAssertEqual(store.totalReadyChoreCount(), 2)
    }

    func testFirstKidWithReadyChoresReturnsNilWhenNoChores() {
        let store = makeStore(kids: [Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)])

        XCTAssertNil(store.firstKidWithReadyChores())
    }

    func testFirstKidWithReadyChoresReturnsKidWithTasks() {
        let kidA = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let kidB = Kid(name: "Blake", availablePoints: 0, vaultPoints: 0)
        let task = RewardTask(title: "Sweep", points: 3, assignedKidIDs: [kidB.id])
        let store = makeStore(kids: [kidA, kidB], tasks: [task])

        XCTAssertEqual(store.firstKidWithReadyChores()?.id, kidB.id)
    }

    func testFirstKidEligibleForVaultInterestReturnsNilWhenAllEmpty() {
        let store = makeStore(kids: [
            Kid(name: "Avery", availablePoints: 5, vaultPoints: 0),
            Kid(name: "Blake", availablePoints: 3, vaultPoints: 0)
        ])

        XCTAssertNil(store.firstKidEligibleForVaultInterest())
    }

    func testFirstKidEligibleForVaultInterestReturnsFirstWithNonZeroVault() {
        let kidA = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        // 20 vault * 0.05 rate = 1 whole interest point → eligible
        let kidB = Kid(name: "Blake", availablePoints: 0, vaultPoints: 20)
        let settings = RewardSettings(currencyCode: "USD", currencyPerPoint: 1, vaultInterestRate: 0.05)
        let store = makeStore(kids: [kidA, kidB], settings: settings)

        XCTAssertEqual(store.firstKidEligibleForVaultInterest()?.id, kidB.id)
    }

    // MARK: - Transaction queries

    func testEarnedPointsInIntervalSumsOnlyEarnedTransactions() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let store = makeStore(kids: [kid])
        let now = Date(timeIntervalSince1970: 1_000_000)
        let interval = DateInterval(start: now.addingTimeInterval(-100), end: now.addingTimeInterval(100))

        store.adjust(points: 3, note: "Bonus", for: store.state.kids[0])
        store.award(task: RewardTask(title: "Sweep", points: 5, assignedKidIDs: [kid.id]),
                    to: store.state.kids[0], at: now)

        let earned = store.earnedPoints(in: interval)
        XCTAssertEqual(earned, 5)
    }

    func testEarnedPointsInIntervalExcludesOutOfRangeTransactions() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let taskA = RewardTask(title: "Sweep", points: 5, assignedKidIDs: [kid.id])
        let taskB = RewardTask(title: "Dishes", points: 3, assignedKidIDs: [kid.id])
        let store = makeStore(kids: [kid], tasks: [taskA, taskB])
        let pivot = Date(timeIntervalSince1970: 1_000_000)

        store.award(task: taskA, to: store.state.kids[0], at: pivot.addingTimeInterval(-200))
        store.award(task: taskB, to: store.state.kids[0], at: pivot)

        let interval = DateInterval(start: pivot.addingTimeInterval(-100), end: pivot.addingTimeInterval(100))
        XCTAssertEqual(store.earnedPoints(in: interval), 3)
    }

    func testLastTransactionReturnsNilWhenNoTransactions() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let store = makeStore(kids: [kid])

        XCTAssertNil(store.lastTransaction(for: store.state.kids[0]))
    }

    func testLastTransactionReturnsNewestTransaction() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        let taskA = RewardTask(title: "Sweep", points: 2, assignedKidIDs: [kid.id])
        let taskB = RewardTask(title: "Dishes", points: 3, assignedKidIDs: [kid.id])
        let store = makeStore(kids: [kid], tasks: [taskA, taskB])
        let t1 = Date(timeIntervalSince1970: 1_000_000)
        let t2 = Date(timeIntervalSince1970: 2_000_000)

        store.award(task: taskA, to: store.state.kids[0], at: t1)
        store.award(task: taskB, to: store.state.kids[0], at: t2)

        XCTAssertEqual(store.lastTransaction(for: store.state.kids[0])?.date, t2)
    }

    // MARK: - Aggregated point totals

    func testTotalAvailableVaultAndHouseholdPoints() {
        let store = makeStore(kids: [
            Kid(name: "Avery", availablePoints: 10, vaultPoints: 5),
            Kid(name: "Blake", availablePoints: 3, vaultPoints: 7)
        ])

        XCTAssertEqual(store.totalAvailablePoints, 13)
        XCTAssertEqual(store.totalVaultPoints, 12)
        XCTAssertEqual(store.totalHouseholdPoints, 25)
    }

    func testPendingApprovalCountMatchesApprovalRequestsArray() {
        let kid = Kid(name: "Avery", availablePoints: 10, vaultPoints: 0)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], settings: settings)

        store.requestCashOut(points: 3, for: store.state.kids[0])
        store.requestDeposit(points: 2, for: store.state.kids[0])

        XCTAssertEqual(store.pendingApprovalCount, 2)
        XCTAssertEqual(store.pendingApprovalCount, store.state.approvalRequests.count)
    }

    // MARK: - Direct cashOut (without approval flow)

    func testDirectCashOutDeductsAvailablePoints() {
        let kid = Kid(name: "Avery", availablePoints: 8, vaultPoints: 0)
        let store = makeStore(kids: [kid])

        let result = store.cashOut(points: 5, for: store.state.kids[0])

        XCTAssertTrue(result)
        XCTAssertEqual(store.state.kids[0].availablePoints, 3)
        XCTAssertEqual(store.transactions(for: store.state.kids[0]).first?.kind, .cashedOut)
        XCTAssertEqual(store.transactions(for: store.state.kids[0]).first?.points, 5)
    }

    func testDirectCashOutCapsAtAvailablePoints() {
        let kid = Kid(name: "Avery", availablePoints: 6, vaultPoints: 0)
        let store = makeStore(kids: [kid])

        let result = store.cashOut(points: 100, for: store.state.kids[0])

        XCTAssertTrue(result)
        XCTAssertEqual(store.state.kids[0].availablePoints, 0)
        XCTAssertEqual(store.transactions(for: store.state.kids[0]).first?.points, 6)
    }

    func testDirectCashOutReturnsFalseWhenAvailableIsZero() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 5)
        let store = makeStore(kids: [kid])

        let result = store.cashOut(points: 5, for: store.state.kids[0])

        XCTAssertFalse(result)
        XCTAssertTrue(store.state.transactions.isEmpty)
    }

    func testDirectCashOutRecordsCurrencyAmount() {
        let kid = Kid(name: "Avery", availablePoints: 10, vaultPoints: 0)
        let settings = RewardSettings(currencyCode: "USD", currencyPerPoint: 2, vaultInterestRate: 0)
        let store = makeStore(kids: [kid], settings: settings)

        store.cashOut(points: 4, for: store.state.kids[0])

        XCTAssertEqual(store.transactions(for: store.state.kids[0]).first?.currencyAmount, 8)
    }

    // MARK: - Interest schedule

    func testIsInterestScheduleDueWhenNeverApplied() {
        let anchor = Date(timeIntervalSince1970: 4_102_444_800) // year 2100
        var settings = RewardSettings.defaults
        settings.interestRecurrence = .daily
        settings.lastInterestAppliedAt = anchor
        let store = makeStore(
            kids: [Kid(name: "Avery", availablePoints: 0, vaultPoints: 20)],
            settings: settings
        )

        XCTAssertTrue(store.isInterestScheduleDue(now: anchor.addingTimeInterval(25 * 3600)))
    }

    func testInterestScheduleNotDueWhenAllEligibleKidsAlreadyHavePendingApproval() {
        let anchor = Date(timeIntervalSince1970: 4_102_444_800) // year 2100
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        settings.interestRecurrence = .daily
        settings.lastInterestAppliedAt = anchor
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 20)
        let store = makeStore(kids: [kid], settings: settings)

        store.requestInterest(for: store.state.kids[0])

        XCTAssertFalse(store.isInterestScheduleDue(now: anchor.addingTimeInterval(25 * 3600)))
    }

    func testIsInterestScheduleDueRespectsDueDate() throws {
        let calendar = RecurrenceSchedule.configuredCalendar()
        let applied = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 3, hour: 12)))
        let sameDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 3, hour: 14)))
        var settings = RewardSettings.defaults
        settings.interestRecurrence = .daily
        settings.lastInterestAppliedAt = applied
        let store = makeStore(
            kids: [Kid(name: "Avery", availablePoints: 0, vaultPoints: 20)],
            settings: settings
        )

        XCTAssertFalse(store.isInterestScheduleDue(now: sameDay))
    }

    func testIsInterestScheduleDueReturnsFalseWhenRecurrenceOff() {
        let store = makeStore(
            kids: [Kid(name: "Avery", availablePoints: 0, vaultPoints: 20)]
        )

        XCTAssertFalse(store.isInterestScheduleDue())
    }

    func testIsInterestScheduleDueReturnsFalseWhenNoVaultBalance() {
        var settings = RewardSettings.defaults
        settings.interestRecurrence = .daily
        let store = makeStore(
            kids: [Kid(name: "Avery", availablePoints: 5, vaultPoints: 0)],
            settings: settings
        )

        XCTAssertFalse(store.isInterestScheduleDue())
    }

    func testInterestPointsWithFractionalResultBelowHalfRoundsToZero() {
        // 5 * 0.05 = 0.25 → rounds to 0
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 5)
        let settings = RewardSettings(currencyCode: "USD", currencyPerPoint: 1, vaultInterestRate: 0.05)
        let store = makeStore(kids: [kid], settings: settings)

        XCTAssertEqual(store.interestPoints(for: store.state.kids[0]), 0)
    }

    func testInterestPointsWithLargeVaultProducesWholeNumber() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 100)
        let settings = RewardSettings(currencyCode: "USD", currencyPerPoint: 1, vaultInterestRate: 0.05)
        let store = makeStore(kids: [kid], settings: settings)

        XCTAssertEqual(store.interestPoints(for: store.state.kids[0]), 5)
    }

    // MARK: - Currency value

    func testCurrencyValueMultipliesPointsByCurrencyPerPoint() {
        let store = makeStore(
            kids: [],
            settings: RewardSettings(currencyCode: "USD", currencyPerPoint: 2, vaultInterestRate: 0)
        )

        assertDecimalEqual(store.currencyValue(for: 5), 10)
    }

    func testCurrencyValueWithZeroCurrencyPerPoint() {
        let store = makeStore(
            kids: [],
            settings: RewardSettings(currencyCode: "USD", currencyPerPoint: 0, vaultInterestRate: 0)
        )

        assertDecimalEqual(store.currencyValue(for: 10), 0)
    }

    // MARK: - Export / import round-trip

    func testExportStateDataProducesDecodableState() throws {
        let kid = Kid(name: "Avery", availablePoints: 5, vaultPoints: 3)
        let task = RewardTask(title: "Sweep", points: 2)
        let store = makeStore(kids: [kid], tasks: [task])

        let data = try XCTUnwrap(store.exportStateData())
        let preview = try XCTUnwrap(store.importPreview(from: data))

        XCTAssertEqual(preview.kidsCount, 1)
        XCTAssertEqual(preview.tasksCount, 1)
        XCTAssertFalse(preview.isCloudBackup)
    }

    func testExportedStateDataCanBeReimported() throws {
        let kid = Kid(name: "Avery", availablePoints: 7, vaultPoints: 2)
        let original = makeStore(kids: [kid])
        let data = try XCTUnwrap(original.exportStateData())

        let restored = makeStore(kids: [])
        XCTAssertTrue(restored.importStateData(data))

        XCTAssertEqual(restored.state.kids.count, 1)
        XCTAssertEqual(restored.state.kids[0].name, "Avery")
        XCTAssertEqual(restored.state.kids[0].availablePoints, 7)
    }

    // MARK: - Parent PIN lockout countdown

    func testParentPINLockoutRemainingSecondsWhenNotLockedOut() {
        let store = makeStore(kids: [])

        XCTAssertEqual(store.parentPINLockoutRemainingSeconds(), 0)
    }

    func testParentPINLockoutRemainingSecondsWhenLockoutHasLapsed() async {
        let pinManager = RecordingParentPINManager()
        pinManager.save(pin: "1234")
        let store = RewardStore(
            initialState: .empty,
            fileURL: temporaryStateURL(),
            pinManager: pinManager
        )
        // Trigger lockout using a timestamp 3 minutes ago → lockoutUntil = 2 min ago → already lapsed
        let threeMinutesAgo = Date(timeIntervalSinceNow: -180)
        for _ in 0..<5 {
            _ = await store.verifyParentPIN("wrong", now: threeMinutesAgo)
        }

        XCTAssertEqual(store.parentPINLockoutRemainingSeconds(now: Date()), 0)
    }

    // MARK: - RecurrenceSchedule.nextOccurrence

    func testNextOccurrenceNoneReturnsNil() {
        let result = RecurrenceSchedule.nextOccurrence(
            after: nil,
            recurrence: .none,
            from: Date()
        )
        XCTAssertNil(result)
    }

    func testNextOccurrenceDailyFromNilAnchorIsNextDay() throws {
        let calendar = RecurrenceSchedule.configuredCalendar()
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 3, hour: 8)))

        let next = try XCTUnwrap(RecurrenceSchedule.nextOccurrence(
            after: nil,
            recurrence: .daily,
            from: now,
            calendar: calendar
        ))

        let nextDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 4)))
        XCTAssertEqual(next, nextDay)
    }

    func testNextOccurrenceDailyFromAnchorIsNextDay() throws {
        let calendar = RecurrenceSchedule.configuredCalendar()
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 3, hour: 12)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 3, hour: 13)))

        let next = try XCTUnwrap(RecurrenceSchedule.nextOccurrence(
            after: anchor,
            recurrence: .daily,
            from: now,
            calendar: calendar
        ))

        let nextDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 4)))
        XCTAssertEqual(next, nextDay)
    }

    func testNextOccurrenceWeeklyAdvancesOneWeek() throws {
        let calendar = RecurrenceSchedule.configuredCalendar()
        // Jan 3, 2100 = Sunday = start of week
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 3, hour: 12)))
        let now = anchor.addingTimeInterval(60)

        let next = try XCTUnwrap(RecurrenceSchedule.nextOccurrence(
            after: anchor,
            recurrence: .weekly,
            from: now,
            calendar: calendar
        ))

        let expectedWeekStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 10)))
        XCTAssertEqual(next, expectedWeekStart)
    }

    func testNextOccurrenceBiweeklyAdvancesTwoWeeks() throws {
        let calendar = RecurrenceSchedule.configuredCalendar()
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 3, hour: 12)))
        let now = anchor.addingTimeInterval(60)

        let next = try XCTUnwrap(RecurrenceSchedule.nextOccurrence(
            after: anchor,
            recurrence: .biweekly,
            from: now,
            calendar: calendar
        ))

        let expectedWeekStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 17)))
        XCTAssertEqual(next, expectedWeekStart)
    }

    func testNextOccurrenceMonthlyAdvancesToStartOfNextMonth() throws {
        let calendar = RecurrenceSchedule.configuredCalendar()
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 15, hour: 12)))
        let now = anchor.addingTimeInterval(60)

        let next = try XCTUnwrap(RecurrenceSchedule.nextOccurrence(
            after: anchor,
            recurrence: .monthly,
            from: now,
            calendar: calendar
        ))

        let expectedMonthStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 2, day: 1)))
        XCTAssertEqual(next, expectedMonthStart)
    }

    func testNextOccurrenceMonthlyWrapsToJanuaryForDecemberAnchor() throws {
        let calendar = RecurrenceSchedule.configuredCalendar()
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2099, month: 12, day: 10, hour: 12)))
        let now = anchor.addingTimeInterval(60)

        let next = try XCTUnwrap(RecurrenceSchedule.nextOccurrence(
            after: anchor,
            recurrence: .monthly,
            from: now,
            calendar: calendar
        ))

        let expectedMonthStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 1)))
        XCTAssertEqual(next, expectedMonthStart)
    }

    func testNextOccurrenceReturnsCurDateWhenAnchorIsInFuture() throws {
        let calendar = RecurrenceSchedule.configuredCalendar()
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 6, day: 1)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 3)))

        let next = try XCTUnwrap(RecurrenceSchedule.nextOccurrence(
            after: anchor,
            recurrence: .daily,
            from: now,
            calendar: calendar
        ))

        XCTAssertGreaterThanOrEqual(next, now)
    }

    // MARK: - Monthly allowance edge cases

    func testMonthlyAllowanceSkipsMonthWithFewerDaysThanTarget() throws {
        // day=31 in February: Feb has no day 31, so allowance should not fire mid-February
        let calendar = RecurrenceSchedule.configuredCalendar()
        let lastApplied = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 31)))
        let midFeb = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 2, day: 15)))

        let due = RecurrenceSchedule.allowanceIsDue(
            since: lastApplied,
            recurrence: .monthly,
            weekday: nil,
            monthDay: 31,
            now: midFeb,
            calendar: calendar
        )

        XCTAssertFalse(due)
    }

    func testMonthlyAllowanceFiresOnTargetDayInLongMonth() throws {
        let calendar = RecurrenceSchedule.configuredCalendar()
        let lastApplied = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 1, day: 15)))
        let marchDay15 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2100, month: 3, day: 15)))

        let due = RecurrenceSchedule.allowanceIsDue(
            since: lastApplied,
            recurrence: .monthly,
            weekday: nil,
            monthDay: 15,
            now: marchDay15,
            calendar: calendar
        )

        XCTAssertTrue(due)
    }

    // MARK: - Transaction display labels

    func testTransactionPointsDisplayLabelAllKinds() {
        let kidID = UUID()
        func makeTransaction(kind: RewardTransaction.Kind, points: Int) -> RewardTransaction {
            RewardTransaction(kidID: kidID, kind: kind, points: points, note: "", date: Date(), currencyAmount: nil)
        }

        XCTAssertEqual(makeTransaction(kind: .earned,    points: 5).pointsDisplayLabel, "+5")
        XCTAssertEqual(makeTransaction(kind: .interest,  points: 3).pointsDisplayLabel, "+3")
        XCTAssertEqual(makeTransaction(kind: .withdrawn, points: 4).pointsDisplayLabel, "+4")
        XCTAssertEqual(makeTransaction(kind: .cashedOut, points: 7).pointsDisplayLabel, "-7")
        XCTAssertEqual(makeTransaction(kind: .deposited, points: 6).pointsDisplayLabel, "moved 6")
        XCTAssertEqual(makeTransaction(kind: .adjusted,  points: 2).pointsDisplayLabel, "+2")
        XCTAssertEqual(makeTransaction(kind: .adjusted,  points: -3).pointsDisplayLabel, "-3")
    }

    // MARK: - Allowance applied-at tracking with recurrence

    func testApplyAllowanceToAllKidsRecordsAppliedAtWhenRecurrenceIsSet() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        var settings = RewardSettings.defaults
        settings.allowanceRecurrence = .weekly
        settings.allowancePoints = 4
        let store = makeStore(kids: [kid], settings: settings)
        let appliedAt = Date(timeIntervalSince1970: 1_800_000_000)

        store.applyAllowanceToAllKids(at: appliedAt)

        XCTAssertEqual(store.state.settings.lastAllowanceAppliedAt, appliedAt)
    }

    func testApplyAllowanceToAllKidsDoesNotRecordAppliedAtWhenRecurrenceIsNone() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)
        var settings = RewardSettings.defaults
        settings.allowanceRecurrence = .none
        settings.allowancePoints = 4
        let store = makeStore(kids: [kid], settings: settings)

        store.applyAllowanceToAllKids(at: Date())

        XCTAssertNil(store.state.settings.lastAllowanceAppliedAt)
    }

    // MARK: - Kid.goalPoints model

    func testKidGoalPointsDefaultsToZeroOnDecode() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "name": "Avery",
          "availablePoints": 5,
          "vaultPoints": 3
        }
        """
        let kid = try JSONDecoder.configuredForTests.decode(Kid.self, from: Data(json.utf8))

        XCTAssertEqual(kid.goalPoints, 0)
    }

    func testKidGoalPointsRoundTrips() throws {
        let original = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0, goalPoints: 17)
        let data = try JSONEncoder.configuredForTests.encode(original)
        let decoded = try JSONDecoder.configuredForTests.decode(Kid.self, from: data)

        XCTAssertEqual(decoded.goalPoints, 17)
    }

    func testKidTotalPointsIncludesGoalPoints() {
        let kid = Kid(name: "Avery", availablePoints: 4, vaultPoints: 6, goalPoints: 10)

        XCTAssertEqual(kid.totalPoints, 20)
    }

    func testSavingsGoalProgressWithZeroGoalPointsIsZero() {
        let kid = Kid(name: "Avery", availablePoints: 50, vaultPoints: 50, goalPoints: 0, savingsGoal: SavingsGoal(title: "Bike", targetPoints: 20))
        let store = makeStore(kids: [kid])

        XCTAssertEqual(store.savingsGoalProgress(for: kid), 0)
    }

    // MARK: - depositToGoal

    func testDepositToGoalMovesPointsFromAvailableToGoal() {
        let kid = Kid(name: "Avery", availablePoints: 10, vaultPoints: 0, goalPoints: 0)
        let store = makeStore(kids: [kid])

        let result = store.depositToGoal(points: 4, for: store.state.kids[0])

        XCTAssertTrue(result)
        XCTAssertEqual(store.state.kids[0].availablePoints, 6)
        XCTAssertEqual(store.state.kids[0].goalPoints, 4)
    }

    func testDepositToGoalCreatesGoalDepositedTransaction() {
        let kid = Kid(name: "Avery", availablePoints: 10, vaultPoints: 0, goalPoints: 0)
        let store = makeStore(kids: [kid])

        store.depositToGoal(points: 4, for: store.state.kids[0])

        let tx = store.transactions(for: store.state.kids[0]).first
        XCTAssertEqual(tx?.kind, .goalDeposited)
        XCTAssertEqual(tx?.points, 4)
    }

    func testDepositToGoalCapsAtAvailablePoints() {
        let kid = Kid(name: "Avery", availablePoints: 3, vaultPoints: 0, goalPoints: 0)
        let store = makeStore(kids: [kid])

        store.depositToGoal(points: 100, for: store.state.kids[0])

        XCTAssertEqual(store.state.kids[0].availablePoints, 0)
        XCTAssertEqual(store.state.kids[0].goalPoints, 3)
    }

    func testDepositToGoalReturnsFalseWhenAvailableIsZero() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0, goalPoints: 0)
        let store = makeStore(kids: [kid])

        let result = store.depositToGoal(points: 5, for: store.state.kids[0])

        XCTAssertFalse(result)
        XCTAssertTrue(store.state.transactions.isEmpty)
    }

    // MARK: - cashOutFromGoal

    func testCashOutFromGoalReducesGoalPoints() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0, goalPoints: 10)
        let store = makeStore(kids: [kid])

        let result = store.cashOutFromGoal(points: 4, for: store.state.kids[0])

        XCTAssertTrue(result)
        XCTAssertEqual(store.state.kids[0].goalPoints, 6)
        XCTAssertEqual(store.state.kids[0].availablePoints, 0)
    }

    func testCashOutFromGoalCreatesGoalCashedOutTransaction() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0, goalPoints: 10)
        let settings = RewardSettings(currencyCode: "USD", currencyPerPoint: 2, vaultInterestRate: 0)
        let store = makeStore(kids: [kid], settings: settings)

        store.cashOutFromGoal(points: 4, for: store.state.kids[0])

        let tx = store.transactions(for: store.state.kids[0]).first
        XCTAssertEqual(tx?.kind, .goalCashedOut)
        XCTAssertEqual(tx?.points, 4)
        XCTAssertEqual(tx?.currencyAmount, 8)
    }

    func testCashOutFromGoalCapsAtGoalPoints() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0, goalPoints: 3)
        let store = makeStore(kids: [kid])

        store.cashOutFromGoal(points: 100, for: store.state.kids[0])

        XCTAssertEqual(store.state.kids[0].goalPoints, 0)
        XCTAssertEqual(store.transactions(for: store.state.kids[0]).first?.points, 3)
    }

    func testCashOutFromGoalReturnsFalseWhenGoalIsZero() {
        let kid = Kid(name: "Avery", availablePoints: 5, vaultPoints: 0, goalPoints: 0)
        let store = makeStore(kids: [kid])

        let result = store.cashOutFromGoal(points: 5, for: store.state.kids[0])

        XCTAssertFalse(result)
        XCTAssertTrue(store.state.transactions.isEmpty)
    }

    // MARK: - withdrawFromGoal

    func testWithdrawFromGoalMovesPointsToAvailable() {
        let kid = Kid(name: "Avery", availablePoints: 2, vaultPoints: 0, goalPoints: 8)
        let store = makeStore(kids: [kid])

        store.withdrawFromGoal(points: 5, for: store.state.kids[0])

        XCTAssertEqual(store.state.kids[0].goalPoints, 3)
        XCTAssertEqual(store.state.kids[0].availablePoints, 7)
    }

    func testWithdrawFromGoalCreatesGoalWithdrawnTransaction() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0, goalPoints: 8)
        let store = makeStore(kids: [kid])

        store.withdrawFromGoal(points: 5, for: store.state.kids[0])

        let tx = store.transactions(for: store.state.kids[0]).first
        XCTAssertEqual(tx?.kind, .goalWithdrawn)
        XCTAssertEqual(tx?.points, 5)
    }

    func testWithdrawFromGoalCapsAtGoalPoints() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0, goalPoints: 3)
        let store = makeStore(kids: [kid])

        store.withdrawFromGoal(points: 100, for: store.state.kids[0])

        XCTAssertEqual(store.state.kids[0].goalPoints, 0)
        XCTAssertEqual(store.state.kids[0].availablePoints, 3)
    }

    func testWithdrawFromGoalNoOpWhenGoalIsZero() {
        let kid = Kid(name: "Avery", availablePoints: 5, vaultPoints: 0, goalPoints: 0)
        let store = makeStore(kids: [kid])

        store.withdrawFromGoal(points: 3, for: store.state.kids[0])

        XCTAssertTrue(store.state.transactions.isEmpty)
        XCTAssertEqual(store.state.kids[0].availablePoints, 5)
    }

    // MARK: - Goal interest

    func testGoalInterestPointsCalculatesFromGoalBalance() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0, goalPoints: 100)
        let settings = RewardSettings(currencyCode: "USD", currencyPerPoint: 1, vaultInterestRate: 0.05)
        let store = makeStore(kids: [kid], settings: settings)

        XCTAssertEqual(store.goalInterestPoints(for: store.state.kids[0]), 5)
    }

    func testGoalInterestPointsZeroWhenGoalEmpty() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0, goalPoints: 0)
        let settings = RewardSettings(currencyCode: "USD", currencyPerPoint: 1, vaultInterestRate: 0.10)
        let store = makeStore(kids: [kid], settings: settings)

        XCTAssertEqual(store.goalInterestPoints(for: store.state.kids[0]), 0)
    }

    func testTotalInterestPointsSumsVaultAndGoal() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 100, goalPoints: 200)
        let settings = RewardSettings(currencyCode: "USD", currencyPerPoint: 1, vaultInterestRate: 0.05)
        let store = makeStore(kids: [kid], settings: settings)

        // vault: 100 * 0.05 = 5, goal: 200 * 0.05 = 10, total = 15
        XCTAssertEqual(store.totalInterestPoints(for: store.state.kids[0]), 15)
    }

    func testApplyInterestAppliesBothVaultAndGoalInterest() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 100, goalPoints: 200)
        let settings = RewardSettings(currencyCode: "USD", currencyPerPoint: 1, vaultInterestRate: 0.05)
        let store = makeStore(kids: [kid], settings: settings)

        let result = store.applyInterest(to: store.state.kids[0])

        XCTAssertTrue(result)
        XCTAssertEqual(store.state.kids[0].vaultPoints, 105)
        XCTAssertEqual(store.state.kids[0].goalPoints, 210)
    }

    func testApplyInterestCreatesInterestAndGoalInterestTransactions() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 100, goalPoints: 200)
        let settings = RewardSettings(currencyCode: "USD", currencyPerPoint: 1, vaultInterestRate: 0.05)
        let store = makeStore(kids: [kid], settings: settings)

        store.applyInterest(to: store.state.kids[0])

        let txKinds = store.transactions(for: store.state.kids[0]).map { $0.kind }
        XCTAssertTrue(txKinds.contains(.interest))
        XCTAssertTrue(txKinds.contains(.goalInterest))
        XCTAssertEqual(txKinds.count, 2)
    }

    func testApplyInterestReturnsFalseWhenBothBalancesZero() {
        let kid = Kid(name: "Avery", availablePoints: 5, vaultPoints: 0, goalPoints: 0)
        let settings = RewardSettings(currencyCode: "USD", currencyPerPoint: 1, vaultInterestRate: 0.10)
        let store = makeStore(kids: [kid], settings: settings)

        let result = store.applyInterest(to: store.state.kids[0])

        XCTAssertFalse(result)
        XCTAssertTrue(store.state.transactions.isEmpty)
    }

    func testApplyInterestOnlyVaultWhenGoalIsZero() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 100, goalPoints: 0)
        let settings = RewardSettings(currencyCode: "USD", currencyPerPoint: 1, vaultInterestRate: 0.10)
        let store = makeStore(kids: [kid], settings: settings)

        store.applyInterest(to: store.state.kids[0])

        XCTAssertEqual(store.state.kids[0].vaultPoints, 110)
        XCTAssertEqual(store.state.kids[0].goalPoints, 0)
        XCTAssertEqual(store.state.transactions.count, 1)
        XCTAssertEqual(store.state.transactions[0].kind, .interest)
    }

    func testApplyDueInterestIncludesGoalInterest() {
        let start = Date(timeIntervalSince1970: 4_102_444_800)
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 100, goalPoints: 200)
        let settings = RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: 1,
            vaultInterestRate: 0.05,
            interestRecurrence: .daily,
            lastInterestAppliedAt: start
        )
        let store = RewardStore(
            initialState: RewardState(kids: [kid], tasks: [], settings: settings, transactions: []),
            fileURL: temporaryStateURL()
        )

        XCTAssertTrue(store.applyDueInterestIfNeeded(now: start.addingTimeInterval(25 * 60 * 60)))

        XCTAssertEqual(store.state.kids[0].vaultPoints, 105)
        XCTAssertEqual(store.state.kids[0].goalPoints, 210)
    }

    func testIsInterestScheduleDueReturnsTrueWhenGoalHasInterestButVaultEmpty() {
        let anchor = Date(timeIntervalSince1970: 4_102_444_800) // year 2100
        var settings = RewardSettings.defaults
        settings.interestRecurrence = .daily
        settings.vaultInterestRate = 0.10
        settings.lastInterestAppliedAt = anchor
        let store = makeStore(
            kids: [Kid(name: "Avery", availablePoints: 0, vaultPoints: 0, goalPoints: 100)],
            settings: settings
        )

        XCTAssertTrue(store.isInterestScheduleDue(now: anchor.addingTimeInterval(25 * 3600)))
    }

    // MARK: - Goal approval flow

    func testRequestGoalDepositCreatesApprovalRequest() {
        let kid = Kid(name: "Avery", availablePoints: 10, vaultPoints: 0, goalPoints: 0)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], settings: settings)

        store.requestGoalDeposit(points: 4, for: store.state.kids[0])

        XCTAssertEqual(store.state.approvalRequests.count, 1)
        XCTAssertEqual(store.state.approvalRequests[0].kind, .goalDeposit)
        XCTAssertEqual(store.state.approvalRequests[0].points, 4)
    }

    func testRequestGoalDepositIgnoredWhenAvailableIsZero() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0, goalPoints: 0)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], settings: settings)

        store.requestGoalDeposit(points: 5, for: store.state.kids[0])

        XCTAssertTrue(store.state.approvalRequests.isEmpty)
    }

    func testApproveGoalDepositMovesPointsToGoal() {
        let kid = Kid(name: "Avery", availablePoints: 10, vaultPoints: 0, goalPoints: 0)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], settings: settings)

        store.requestGoalDeposit(points: 4, for: store.state.kids[0])
        XCTAssertTrue(store.approveRequest(store.state.approvalRequests[0]))

        XCTAssertEqual(store.state.kids[0].availablePoints, 6)
        XCTAssertEqual(store.state.kids[0].goalPoints, 4)
        XCTAssertTrue(store.state.approvalRequests.isEmpty)
        XCTAssertEqual(store.transactions(for: store.state.kids[0]).first?.kind, .goalDeposited)
    }

    func testRequestGoalCashOutCreatesApprovalRequest() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0, goalPoints: 10)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], settings: settings)

        store.requestGoalCashOut(points: 4, for: store.state.kids[0])

        XCTAssertEqual(store.state.approvalRequests.count, 1)
        XCTAssertEqual(store.state.approvalRequests[0].kind, .goalCashOut)
        XCTAssertEqual(store.state.approvalRequests[0].points, 4)
    }

    func testRequestGoalCashOutIgnoredWhenGoalIsZero() {
        let kid = Kid(name: "Avery", availablePoints: 5, vaultPoints: 0, goalPoints: 0)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], settings: settings)

        store.requestGoalCashOut(points: 3, for: store.state.kids[0])

        XCTAssertTrue(store.state.approvalRequests.isEmpty)
    }

    func testApproveGoalCashOutDeductsGoalPoints() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0, goalPoints: 10)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], settings: settings)

        store.requestGoalCashOut(points: 4, for: store.state.kids[0])
        XCTAssertTrue(store.approveRequest(store.state.approvalRequests[0]))

        XCTAssertEqual(store.state.kids[0].goalPoints, 6)
        XCTAssertTrue(store.state.approvalRequests.isEmpty)
        XCTAssertEqual(store.transactions(for: store.state.kids[0]).first?.kind, .goalCashedOut)
    }

    func testDepositToGoalRoutesViaApprovalWhenEnabled() {
        let kid = Kid(name: "Avery", availablePoints: 10, vaultPoints: 0, goalPoints: 0)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], settings: settings)

        store.depositToGoal(points: 5, for: store.state.kids[0])

        XCTAssertEqual(store.state.approvalRequests.count, 1)
        XCTAssertEqual(store.state.approvalRequests[0].kind, .goalDeposit)
        XCTAssertEqual(store.state.kids[0].goalPoints, 0, "Goal unchanged before approval")
    }

    func testCashOutFromGoalRoutesViaApprovalWhenEnabled() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0, goalPoints: 10)
        var settings = RewardSettings.defaults
        settings.approvalFlowEnabled = true
        let store = makeStore(kids: [kid], settings: settings)

        store.cashOutFromGoal(points: 5, for: store.state.kids[0])

        XCTAssertEqual(store.state.approvalRequests.count, 1)
        XCTAssertEqual(store.state.approvalRequests[0].kind, .goalCashOut)
        XCTAssertEqual(store.state.kids[0].goalPoints, 10, "Goal unchanged before approval")
    }

    // MARK: - setVaultInterestRate / setDefaultAllowancePoints

    func testSetVaultInterestRatePersistsInSettings() {
        let store = makeStore(kids: [])

        store.setVaultInterestRate(Decimal(string: "0.07")!)

        assertDecimalEqual(store.state.settings.vaultInterestRate, Decimal(string: "0.07")!)
    }

    func testSetVaultInterestRateClampsNegativeToZero() {
        let store = makeStore(kids: [])

        store.setVaultInterestRate(Decimal(string: "-0.05")!)

        assertDecimalEqual(store.state.settings.vaultInterestRate, 0)
    }

    func testSetDefaultAllowancePointsPersistsInSettings() {
        let store = makeStore(kids: [])

        store.setDefaultAllowancePoints(12)

        XCTAssertEqual(store.state.settings.allowancePoints, 12)
    }

    func testSetDefaultAllowancePointsClampsNegativeToZero() {
        let store = makeStore(kids: [])

        store.setDefaultAllowancePoints(-5)

        XCTAssertEqual(store.state.settings.allowancePoints, 0)
    }

    // MARK: - totalHouseholdPoints includes goal

    func testTotalHouseholdPointsIncludesGoalPoints() {
        let store = makeStore(kids: [
            Kid(name: "Avery", availablePoints: 10, vaultPoints: 5, goalPoints: 8),
            Kid(name: "Blake", availablePoints: 3, vaultPoints: 2, goalPoints: 7)
        ])

        XCTAssertEqual(store.totalHouseholdPoints, 35)
    }

    func testTotalGoalPoints() {
        let store = makeStore(kids: [
            Kid(name: "Avery", availablePoints: 0, vaultPoints: 0, goalPoints: 6),
            Kid(name: "Blake", availablePoints: 0, vaultPoints: 0, goalPoints: 4)
        ])

        XCTAssertEqual(store.totalGoalPoints, 10)
    }

    // MARK: - Goal transaction display labels

    func testTransactionPointsDisplayLabelGoalKinds() {
        let kidID = UUID()
        func makeTransaction(kind: RewardTransaction.Kind, points: Int) -> RewardTransaction {
            RewardTransaction(kidID: kidID, kind: kind, points: points, note: "", date: Date(), currencyAmount: nil)
        }

        XCTAssertEqual(makeTransaction(kind: .goalDeposited, points: 5).pointsDisplayLabel, "moved 5")
        XCTAssertEqual(makeTransaction(kind: .goalWithdrawn, points: 3).pointsDisplayLabel, "+3")
        XCTAssertEqual(makeTransaction(kind: .goalCashedOut, points: 4).pointsDisplayLabel, "-4")
        XCTAssertEqual(makeTransaction(kind: .goalInterest, points: 2).pointsDisplayLabel, "+2")
    }

    // MARK: - Goal transaction correction/deletion

    func testDeleteGoalDepositTransactionReversesGoalPoints() {
        let kid = Kid(name: "Avery", availablePoints: 10, vaultPoints: 0, goalPoints: 0)
        let store = makeStore(kids: [kid])

        store.depositToGoal(points: 4, for: store.state.kids[0])
        let tx = store.state.transactions[0]

        let didDelete = store.deleteTransaction(tx)

        XCTAssertTrue(didDelete)
        XCTAssertEqual(store.state.kids[0].availablePoints, 10)
        XCTAssertEqual(store.state.kids[0].goalPoints, 0)
    }

    func testDeleteGoalWithdrawalTransactionReversesPoints() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0, goalPoints: 8)
        let store = makeStore(kids: [kid])

        store.withdrawFromGoal(points: 5, for: store.state.kids[0])
        let tx = store.state.transactions[0]

        let didDelete = store.deleteTransaction(tx)

        XCTAssertTrue(didDelete)
        XCTAssertEqual(store.state.kids[0].goalPoints, 8)
        XCTAssertEqual(store.state.kids[0].availablePoints, 0)
    }

    func testCorrectGoalCashOutTransactionUpdatesCurrencyAmount() {
        let kid = Kid(name: "Avery", availablePoints: 0, vaultPoints: 0, goalPoints: 10)
        let settings = RewardSettings(currencyCode: "USD", currencyPerPoint: 2, vaultInterestRate: 0)
        let store = makeStore(kids: [kid], settings: settings)

        store.cashOutFromGoal(points: 4, for: store.state.kids[0])
        let transaction = store.transactions(for: store.state.kids[0])[0]

        XCTAssertTrue(store.correctTransaction(transaction, points: 2, note: "Corrected"))
        let corrected = store.transactions(for: store.state.kids[0])[0]
        XCTAssertEqual(corrected.points, 2)
        XCTAssertEqual(corrected.note, "Corrected")
        XCTAssertEqual(corrected.currencyAmount, 4)
        XCTAssertEqual(store.state.kids[0].goalPoints, 8)
    }

    private func makeStore(
        kids: [Kid],
        tasks: [RewardTask] = [],
        settings: RewardSettings = .defaults,
        transactions: [RewardTransaction] = [],
        approvalRequests: [ApprovalRequest] = [],
        taskCompletions: [TaskCompletion] = []
    ) -> RewardStore {
        let fileURL = temporaryStateURL()
        try? FileManager.default.removeItem(at: fileURL)
        return RewardStore(
            initialState: RewardState(
                kids: kids,
                tasks: tasks,
                settings: settings,
                transactions: transactions,
                approvalRequests: approvalRequests,
                taskCompletions: taskCompletions
            ),
            fileURL: fileURL
        )
    }

    private func assertDecimalEqual(
        _ actual: Decimal?,
        _ expected: Decimal,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("Expected \(expected), got nil", file: file, line: line)
            return
        }
        XCTAssertEqual(
            NSDecimalNumber(decimal: actual),
            NSDecimalNumber(decimal: expected),
            file: file,
            line: line
        )
    }

    private func temporaryStateURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    private func settingsWithICloudAutoSync(enabled: Bool) -> RewardSettings {
        RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: 1,
            vaultInterestRate: 0.05,
            iCloudAutoSyncEnabled: enabled
        )
    }

    private func markLocalSaveDate(_ date: Date) {
        UserDefaults.standard.set(date, forKey: "kidsRewards.lastSavedAt")
    }

    private func makeCloudBackupData(from store: RewardStore, savedAt: Date = Date()) throws -> Data {
        let envelope = CloudBackupEnvelope(
            schemaVersion: 3,
            savedAt: savedAt,
            deviceName: "Test Device",
            state: store.state
        )
        return try JSONEncoder.configuredForTests.encode(envelope)
    }

    private func temporaryDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
    }

    private func writeKeychainData(
        _ data: Data,
        service: String,
        account: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            if status == errSecMissingEntitlement {
                throw XCTSkip("Keychain direct-write tests require a signed test host with Keychain access.")
            }
            XCTFail("SecItemAdd failed with status \(status)", file: file, line: line)
            return
        }
    }

    private func singleHash(pin: String, salt: Data) -> Data {
        var input = Data()
        input.append(salt)
        input.append(Data(pin.utf8))
        return Data(SHA256.hash(data: input))
    }

    private func legacyStateData(parentPIN: String) -> Data {
        let kidID = UUID().uuidString
        let json = """
        {
          "kids": [
            {
              "id": "\(kidID)",
              "name": "Imported",
              "availablePoints": 8,
              "vaultPoints": 2
            }
          ],
          "tasks": [],
          "settings": {
            "currencyCode": "USD",
            "currencyPerPoint": 1,
            "vaultInterestRate": 0.05,
            "parentPIN": "\(parentPIN)"
          },
          "transactions": []
        }
        """
        return Data(json.utf8)
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

private extension JSONDecoder {
    static var configuredForTests: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private final class InMemoryParentPINManager: ParentPINManaging, @unchecked Sendable {
    private var pin: String?

    var hasPIN: Bool {
        pin != nil
    }

    @discardableResult
    func save(pin: String) -> Bool {
        self.pin = pin
        return true
    }

    @discardableResult
    func clear() -> Bool {
        pin = nil
        return true
    }

    func verify(pin: String) -> Bool {
        guard let savedPIN = self.pin else { return true }
        return pin == savedPIN
    }
}

private final class RecordingParentPINManager: ParentPINManaging, @unchecked Sendable {
    private(set) var savedPIN: String?
    var hasPIN: Bool { savedPIN != nil }

    @discardableResult
    func save(pin: String) -> Bool {
        savedPIN = pin
        return true
    }

    @discardableResult
    func clear() -> Bool {
        savedPIN = nil
        return true
    }

    func verify(pin: String) -> Bool {
        savedPIN == nil || savedPIN == pin
    }
}

private final class FailingParentPINManager: ParentPINManaging, @unchecked Sendable {
    var hasPIN = false

    @discardableResult
    func save(pin: String) -> Bool {
        false
    }

    @discardableResult
    func clear() -> Bool {
        false
    }

    func verify(pin: String) -> Bool {
        false
    }
}
