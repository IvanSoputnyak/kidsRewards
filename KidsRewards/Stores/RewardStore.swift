import Foundation

@MainActor
final class RewardStore: ObservableObject {
    @Published private(set) var state: RewardState

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("kids-rewards-state.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? decoder.decode(RewardState.self, from: data) {
            state = decoded
        } else {
            state = .sample
            save()
        }
    }

    var totalAvailablePoints: Int {
        state.kids.reduce(0) { $0 + $1.availablePoints }
    }

    var totalVaultPoints: Int {
        state.kids.reduce(0) { $0 + $1.vaultPoints }
    }

    func addKid(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.kids.append(Kid(name: trimmed, availablePoints: 0, vaultPoints: 0))
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

    func updateSettings(currencyCode: String, currencyPerPoint: Decimal, vaultInterestRate: Decimal) {
        state.settings = RewardSettings(
            currencyCode: currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            currencyPerPoint: max(currencyPerPoint, 0),
            vaultInterestRate: max(vaultInterestRate, 0)
        )
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

    private func updateKid(_ id: UUID, mutate: (inout Kid) -> Void) {
        guard let index = state.kids.firstIndex(where: { $0.id == id }) else { return }
        mutate(&state.kids[index])
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

    private func save() {
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
