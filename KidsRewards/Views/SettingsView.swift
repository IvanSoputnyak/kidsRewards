import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: RewardStore

    @State private var currencyCode = ""
    @State private var currencyPerPointText = ""
    @State private var interestRateText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Point Value") {
                    TextField("Currency code", text: $currencyCode)
                        .textInputAutocapitalization(.characters)
                    TextField("Currency per point", text: $currencyPerPointText)
                        .keyboardType(.decimalPad)
                }

                Section("Vault") {
                    TextField("Interest rate, for example 0.05", text: $interestRateText)
                        .keyboardType(.decimalPad)
                    Text("Current interest: \(Formatters.percent(store.state.settings.vaultInterestRate))")
                        .foregroundStyle(.secondary)
                }

                Button {
                    saveSettings()
                } label: {
                    Label("Save Settings", systemImage: "checkmark.circle.fill")
                }
            }
            .navigationTitle("Settings")
            .onAppear(perform: loadSettings)
        }
    }

    private func loadSettings() {
        currencyCode = store.state.settings.currencyCode
        currencyPerPointText = "\(store.state.settings.currencyPerPoint)"
        interestRateText = "\(store.state.settings.vaultInterestRate)"
    }

    private func saveSettings() {
        store.updateSettings(
            currencyCode: currencyCode.isEmpty ? "USD" : currencyCode,
            currencyPerPoint: Decimal(string: currencyPerPointText) ?? store.state.settings.currencyPerPoint,
            vaultInterestRate: Decimal(string: interestRateText) ?? store.state.settings.vaultInterestRate
        )
        loadSettings()
    }
}
