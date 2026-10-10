import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Picker("State", selection: $settings.stateCode) {
                        ForEach(GasPriceService.allStates, id: \.self) { Text($0).tag($0) }
                    }
                    SecureField("EIA API key", text: $settings.eiaAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Enter gas price manually", isOn: $settings.useManualGasPrice)
                    HStack {
                        Text("Manual price ($/gal)")
                        Spacer()
                        TextField("0.00", value: $settings.manualGasPrice, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    Button {
                        Task { await settings.refreshGasPrice() }
                    } label: {
                        HStack {
                            Text("Refresh gas price")
                            if settings.isFetching { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(settings.isFetching || settings.eiaAPIKey.isEmpty)
                } header: {
                    Text("Gas Price")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let price = settings.gasPrice {
                            Text("Using \(price, format: .currency(code: "USD"))/gal — \(settings.gasPriceDescription)")
                        }
                        if let error = settings.fetchError { Text(error).foregroundStyle(.red) }
                        Text("Local prices come from the free U.S. EIA open data API. Get a key at eia.gov/opendata.")
                    }
                }
                Section {
                    HStack {
                        Text("Default rate ($/kWh)")
                        Spacer()
                        TextField("0.17", value: $settings.defaultElectricityRate, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                } header: {
                    Text("Electricity")
                } footer: {
                    Text("Used for EV charges where you don't enter a cost.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
