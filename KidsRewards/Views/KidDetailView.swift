import SwiftUI

struct KidDetailView: View {
    @EnvironmentObject private var store: RewardStore
    let kidID: UUID

    @State private var depositPoints = 1
    @State private var cashOutPoints = 1

    private var kid: Kid? {
        store.state.kids.first { $0.id == kidID }
    }

    var body: some View {
        Group {
            if let kid {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        detailHeader(for: kid)
                        awardWorkSection(for: kid)
                        vaultSection(for: kid)
                        cashOutSection(for: kid)
                        historySection(for: kid)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }
                .kidCoinBackground()
                .navigationTitle("Kids")
                .navigationBarTitleDisplayMode(.inline)
                .tint(KidCoinTheme.primary)
            } else {
                ContentUnavailableView("Kid Not Found", systemImage: "person.crop.circle.badge.questionmark")
                    .kidCoinBackground()
            }
        }
    }

    private func detailHeader(for kid: Kid) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(kid.name)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(KidCoinTheme.foreground)

            HStack(spacing: 12) {
                MetricTile(title: "Available", value: kid.availablePoints, systemImage: "star.fill", tone: .coral)
                MetricTile(title: "Vault", value: kid.vaultPoints, systemImage: "lock.fill", tone: .mint)
            }

            Text("Cash value: \(Formatters.currency(store.currencyValue(for: kid.availablePoints), code: store.state.settings.currencyCode))")
                .font(.subheadline)
                .foregroundStyle(KidCoinTheme.mutedText)
                .padding(.horizontal, 4)
        }
    }

    private func awardWorkSection(for kid: Kid) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Award Work")
            if store.state.tasks.isEmpty {
                EmptyStatePanel(
                    systemImage: "checklist",
                    title: "No work yet",
                    message: "Add work in the Work tab to start earning."
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(store.state.tasks) { task in
                        Button {
                            store.award(task: task, to: kid)
                        } label: {
                            HStack {
                                Text(task.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("+\(task.points)")
                                    .font(.subheadline.weight(.bold))
                                    .monospacedDigit()
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(KidCoinTheme.primary.opacity(0.12))
                                    .foregroundStyle(KidCoinTheme.primary)
                                    .clipShape(Capsule())
                            }
                            .padding(15)
                            .tileCard(cornerRadius: 18)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func vaultSection(for kid: Kid) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Vault")
            VStack(spacing: 16) {
                HStack {
                    Text("Deposit")
                        .font(.subheadline)
                    Spacer()
                    CounterControl(value: $depositPoints, range: 1...max(kid.availablePoints, 1))
                }
                PillButton(
                    title: "Deposit \(depositPoints) \(depositPoints == 1 ? "point" : "points")",
                    systemImage: "arrow.down.to.line",
                    tone: .mint,
                    disabled: kid.availablePoints == 0
                ) {
                    store.deposit(points: depositPoints, for: kid)
                    depositPoints = 1
                }
                PillButton(
                    title: "Apply \(Formatters.percent(store.state.settings.vaultInterestRate)) Interest",
                    systemImage: "percent",
                    tone: .subtle,
                    disabled: kid.vaultPoints == 0
                ) {
                    store.applyInterest(to: kid)
                }
            }
            .padding(18)
            .tileCard(cornerRadius: 26)
        }
    }

    private func cashOutSection(for kid: Kid) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Cash Out")
            VStack(spacing: 16) {
                HStack {
                    Text("Cash out")
                        .font(.subheadline)
                    Spacer()
                    CounterControl(value: $cashOutPoints, range: 1...max(kid.availablePoints, 1))
                }
                PillButton(
                    title: "Cash Out \(Formatters.currency(store.currencyValue(for: cashOutPoints), code: store.state.settings.currencyCode))",
                    systemImage: "banknote",
                    tone: .primary,
                    disabled: kid.availablePoints == 0
                ) {
                    store.cashOut(points: cashOutPoints, for: kid)
                    cashOutPoints = 1
                }
            }
            .padding(18)
            .tileCard(cornerRadius: 26)
        }
    }

    private func historySection(for kid: Kid) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "History")
            let transactions = store.transactions(for: kid)
            if transactions.isEmpty {
                Text("No activity yet.")
                    .font(.subheadline)
                    .foregroundStyle(KidCoinTheme.mutedText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                VStack(spacing: 8) {
                    ForEach(transactions) { transaction in
                        TransactionRow(transaction: transaction, currencyCode: store.state.settings.currencyCode)
                    }
                }
            }
        }
    }
}

private struct TransactionRow: View {
    let transaction: RewardTransaction
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.note)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption2)
                    .foregroundStyle(KidCoinTheme.mutedText)
            }

            Spacer()

            Text(pointsLabel)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(pointsBackground)
                .foregroundStyle(pointsForeground)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .tileCard(cornerRadius: 14)
    }

    private var detailText: String {
        let formattedDate = transaction.date.formatted(date: .abbreviated, time: .omitted)
        if let amount = transaction.currencyAmount {
            return "\(formattedDate) · \(Formatters.currency(amount, code: currencyCode))"
        }
        return formattedDate
    }

    private var pointsLabel: String {
        transaction.pointsDisplayLabel
    }

    private var pointsBackground: Color {
        switch transaction.kind {
        case .cashedOut:
            return KidCoinTheme.destructive.opacity(0.12)
        case .deposited:
            return KidCoinTheme.mint.opacity(0.25)
        case .earned, .interest:
            return KidCoinTheme.primary.opacity(0.12)
        }
    }

    private var pointsForeground: Color {
        switch transaction.kind {
        case .cashedOut:
            return KidCoinTheme.destructive
        case .deposited:
            return KidCoinTheme.mintText
        case .earned, .interest:
            return KidCoinTheme.primary
        }
    }
}
