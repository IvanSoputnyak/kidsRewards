import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: RewardStore

    @State private var currencyCode = ""
    @State private var currencyPerPointText = ""
    @State private var interestRateText = ""
    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(eyebrow: "Economy", title: "Settings")

                SectionCard(title: "Point Value") {
                    SettingsField(label: "Currency code", hint: "ISO code used for formatting") {
                        TextField("USD", text: $currencyCode)
                            .textInputAutocapitalization(.characters)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 86)
                            .fieldPill()
                            .onChange(of: currencyCode) { _, newValue in
                                let normalized = String(newValue.uppercased().prefix(3))
                                if currencyCode != normalized {
                                    currencyCode = normalized
                                }
                            }
                    }

                    SettingsField(label: "Currency per point", hint: "What 1 point is worth when cashing out") {
                        TextField("1", text: $currencyPerPointText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 102)
                            .fieldPill()
                    }
                }

                SectionCard(title: "Vault") {
                    SettingsField(label: "Interest rate", hint: "Decimal, 0.05 means 5%") {
                        TextField("0.05", text: $interestRateText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 102)
                            .fieldPill()
                    }

                    HStack {
                        Text("Current interest")
                            .font(.subheadline)
                            .foregroundStyle(KidCoinTheme.mutedText)
                        Spacer()
                        Text(currentInterestLabel)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(KidCoinTheme.mintText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(KidCoinTheme.mint.opacity(0.28))
                            .clipShape(Capsule())
                    }

                    Text("Interest is applied manually per tap on a kid's vault, not automatically over time.")
                        .font(.caption)
                        .foregroundStyle(KidCoinTheme.mutedText)
                        .lineSpacing(2)
                }

                PillButton(
                    title: saved ? "Saved" : "Save Settings",
                    systemImage: "checkmark",
                    tone: .primary
                ) {
                    saveSettings()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 42)
            .padding(.bottom, 20)
        }
        .kidCoinBackground()
        .onAppear(perform: loadSettings)
    }

    private var currentInterestLabel: String {
        let rate = Decimal(string: interestRateText) ?? store.state.settings.vaultInterestRate
        return Formatters.percent(rate)
    }

    private func loadSettings() {
        currencyCode = store.state.settings.currencyCode
        currencyPerPointText = "\(store.state.settings.currencyPerPoint)"
        interestRateText = "\(store.state.settings.vaultInterestRate)"
    }

    private func saveSettings() {
        store.updateSettings(
            currencyCode: currencyCode,
            currencyPerPoint: Decimal(string: currencyPerPointText) ?? store.state.settings.currencyPerPoint,
            vaultInterestRate: Decimal(string: interestRateText) ?? store.state.settings.vaultInterestRate
        )
        loadSettings()
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            saved = false
        }
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: title)
            content
        }
        .padding(18)
        .tileCard(cornerRadius: 26)
    }
}

private struct SettingsField<Content: View>: View {
    let label: String
    let hint: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(KidCoinTheme.mutedText)
            }
            Spacer()
            content
        }
    }
}

private extension View {
    func fieldPill() -> some View {
        self
            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(KidCoinTheme.muted)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
