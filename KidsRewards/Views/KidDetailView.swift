import SwiftUI

struct KidDetailView: View {
    @EnvironmentObject private var store: RewardStore
    let kidID: UUID

    @State private var selectedTaskID: RewardTask.ID?
    @State private var depositPoints = 1
    @State private var cashOutPoints = 1

    private var kid: Kid? {
        store.state.kids.first { $0.id == kidID }
    }

    var body: some View {
        Group {
            if let kid {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(kid.name)
                                .font(.largeTitle.bold())
                            HStack {
                                BalanceTile(title: "Available", points: kid.availablePoints)
                                BalanceTile(title: "Vault", points: kid.vaultPoints)
                            }
                            Text("Cash value: \(Formatters.currency(store.currencyValue(for: kid.availablePoints), code: store.state.settings.currencyCode))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }

                    Section("Award Work") {
                        ForEach(store.state.tasks) { task in
                            Button {
                                store.award(task: task, to: kid)
                            } label: {
                                HStack {
                                    Text(task.title)
                                    Spacer()
                                    Text("+\(task.points)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Section("Vault") {
                        Stepper("Deposit \(depositPoints) points", value: $depositPoints, in: 1...max(kid.availablePoints, 1))
                        Button {
                            store.deposit(points: depositPoints, for: kid)
                            depositPoints = 1
                        } label: {
                            Label("Deposit", systemImage: "arrow.down.to.line")
                        }
                        .disabled(kid.availablePoints == 0)

                        Button {
                            store.applyInterest(to: kid)
                        } label: {
                            Label("Apply \(Formatters.percent(store.state.settings.vaultInterestRate)) Interest", systemImage: "percent")
                        }
                        .disabled(kid.vaultPoints == 0)
                    }

                    Section("Cash Out") {
                        Stepper("Cash out \(cashOutPoints) points", value: $cashOutPoints, in: 1...max(kid.availablePoints, 1))
                        Button {
                            store.cashOut(points: cashOutPoints, for: kid)
                            cashOutPoints = 1
                        } label: {
                            Label("Cash Out \(Formatters.currency(store.currencyValue(for: cashOutPoints), code: store.state.settings.currencyCode))", systemImage: "banknote")
                        }
                        .disabled(kid.availablePoints == 0)
                    }

                    Section("History") {
                        ForEach(store.transactions(for: kid)) { transaction in
                            TransactionRow(transaction: transaction, currencyCode: store.state.settings.currencyCode)
                        }
                    }
                }
                .navigationTitle(kid.name)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Kid Not Found", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
    }
}

private struct BalanceTile: View {
    let title: String
    let points: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(points)")
                .font(.title.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TransactionRow: View {
    let transaction: RewardTransaction
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(transaction.note)
                    .font(.headline)
                Spacer()
                Text(pointsLabel)
                    .foregroundStyle(transaction.kind == .cashedOut ? .red : .green)
            }
            if let amount = transaction.currencyAmount {
                Text(Formatters.currency(amount, code: currencyCode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(transaction.date, style: .date)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var pointsLabel: String {
        switch transaction.kind {
        case .cashedOut:
            return "-\(transaction.points)"
        case .deposited:
            return "moved \(transaction.points)"
        case .earned, .interest:
            return "+\(transaction.points)"
        }
    }
}
