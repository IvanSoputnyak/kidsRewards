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
        XCTAssertEqual(store.state.settings.lastAllowanceAppliedAt, appliedAt)
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
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 1, day: 5, hour: 12)))
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
        let lastWeek = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 1, day: 5, hour: 12)))
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

    func testSavingsGoalProgressIncludesAvailableAndVault() {
        let kid = Kid(name: "Avery", availablePoints: 7, vaultPoints: 5, savingsGoal: SavingsGoal(title: "Bike", targetPoints: 20))
        let store = makeStore(kids: [kid])

        XCTAssertEqual(store.savingsGoalProgress(for: kid), 12)
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
        let settings = RewardSettings(
            currencyCode: "USD",
            currencyPerPoint: 1,
            vaultInterestRate: 0.05,
            allowancePoints: 5,
            allowanceRecurrence: .weekly
        )
        let store = makeStore(
            kids: [Kid(name: "Avery", availablePoints: 0, vaultPoints: 0)],
            settings: settings
        )

        XCTAssertTrue(store.isAllowanceScheduleDue())
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

    func testAutomaticInterestAppliesOnlyWhenRecurrenceIsDue() {
        let start = Date(timeIntervalSince1970: 4_102_444_800)
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
        let store = RewardStore(
            initialState: RewardState(kids: kids, tasks: [], settings: settings, transactions: []),
            fileURL: temporaryStateURL()
        )

        XCTAssertEqual(store.state.kids.map(\.vaultPoints), [100, 20])

        XCTAssertFalse(store.applyDueInterestIfNeeded(now: start.addingTimeInterval(3 * 24 * 60 * 60)))

        XCTAssertTrue(store.applyDueInterestIfNeeded(now: start.addingTimeInterval(8 * 24 * 60 * 60)))
        XCTAssertEqual(store.state.kids[0].vaultPoints, 105)
        XCTAssertEqual(store.state.kids[1].vaultPoints, 21)
        XCTAssertEqual(store.state.transactions.filter { $0.kind == .interest }.count, 2)
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
        XCTAssertEqual(plan[0].delay, 24 * 60 * 60)
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
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 1, day: 5, hour: 12)))
        let nextWeek = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: anchor))

        let delay = RewardNotifications.recurringDelay(
            recurrence: .weekly,
            lastApplied: anchor,
            now: anchor,
            calendar: calendar
        )

        XCTAssertEqual(delay, nextWeek.timeIntervalSince(anchor))
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
