import SwiftUI

struct AddReadingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle

    @State private var date = Date.now
    @State private var odometerText = ""
    @State private var source = ReadingSource.manual
    @State private var photoData: Data?

    private var odometer: Double? { Double(odometerText) }

    var body: some View {
        NavigationStack {
            Form {
                OdometerCaptureSection(odometerText: $odometerText, source: $source, photoData: $photoData)
                Section { DatePicker("Date", selection: $date) }
            }
            .navigationTitle("Odometer Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let odometer else { return }
                        let reading = OdometerReading(date: date, miles: odometer, source: source, photoData: photoData)
                        reading.vehicle = vehicle
                        context.insert(reading)
                        dismiss()
                    }
                    .disabled(odometer == nil)
                }
            }
        }
    }
}

struct AddFuelEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    let vehicle: Vehicle

    @State private var date = Date.now
    @State private var odometerText = ""
    @State private var quantityText = ""
    @State private var costText = ""
    @State private var source = ReadingSource.manual
    @State private var photoData: Data?

    private var unit: String { vehicle.powerType.quantityUnit }
    private var odometer: Double? { Double(odometerText) }
    private var quantity: Double? { Double(quantityText).flatMap { $0 > 0 ? $0 : nil } }

    private var odometerWarning: String? {
        guard let odometer, let current = vehicle.currentOdometer, odometer < current else { return nil }
        return "This is lower than the latest reading (\(Int(current)) mi)."
    }

    var body: some View {
        NavigationStack {
            Form {
                OdometerCaptureSection(odometerText: $odometerText, source: $source, photoData: $photoData)
                if let odometerWarning {
                    Section { Label(odometerWarning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
                Section {
                    HStack {
                        TextField(vehicle.powerType == .ev ? "kWh added" : "Gallons added", text: $quantityText)
                            .keyboardType(.decimalPad)
                        Text(unit).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("$")
                        TextField("Total cost (optional)", text: $costText).keyboardType(.decimalPad)
                    }
                    DatePicker("Date", selection: $date)
                } header: {
                    Text(vehicle.powerType.entryTitle)
                } footer: {
                    if vehicle.powerType == .ev {
                        Text("Without a cost, your default rate of \(settings.defaultElectricityRate, format: .currency(code: "USD"))/kWh is used. Charge to the same level each time for accurate efficiency.")
                    } else {
                        Text("Fill the tank each time for accurate MPG.")
                    }
                }
            }
            .navigationTitle("Log \(vehicle.powerType.entryTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(odometer == nil || quantity == nil)
                }
            }
        }
    }

    private func save() {
        guard let odometer, let quantity else { return }
        let entry = FuelEntry(date: date, odometer: odometer, quantity: quantity,
                              totalCost: Double(costText), source: source, photoData: photoData)
        entry.vehicle = vehicle
        context.insert(entry)
        dismiss()
    }
}
