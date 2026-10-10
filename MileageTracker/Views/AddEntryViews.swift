import SwiftUI

private func odometerPlaceholder(for vehicle: Vehicle) -> String {
    guard let last = vehicle.currentOdometer else { return "Odometer (mi)" }
    return "Odometer (last: \(Int(last)))"
}

struct AddReadingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    var startWithCamera = false

    @State private var date = Date.now
    @State private var odometerText = ""
    @State private var source = ReadingSource.manual
    @State private var photoData: Data?
    @FocusState private var focus: EntryField?

    private var odometer: Double? { Double(odometerText) }

    var body: some View {
        NavigationStack {
            Form {
                Section { LabeledContent("Vehicle", value: vehicle.name) }
                OdometerCaptureSection(odometerText: $odometerText, source: $source, photoData: $photoData,
                                       focus: $focus, placeholder: odometerPlaceholder(for: vehicle),
                                       autoScan: startWithCamera, onScanned: { focus = nil })
                Section { DatePicker("Date", selection: $date) }
            }
            .navigationTitle("Odometer Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(odometer == nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Save") { save() }.disabled(odometer == nil)
                }
            }
            .task {
                guard !startWithCamera else { return }
                try? await Task.sleep(for: .milliseconds(350))
                focus = .odometer
            }
        }
    }

    private func save() {
        guard let odometer else { return }
        let reading = OdometerReading(date: date, miles: odometer, source: source, photoData: photoData)
        reading.vehicle = vehicle
        context.insert(reading)
        dismiss()
    }
}

struct AddFuelEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    let vehicle: Vehicle
    var startWithCamera = false

    @State private var date = Date.now
    @State private var odometerText = ""
    @State private var quantityText = ""
    @State private var costText = ""
    @State private var source = ReadingSource.manual
    @State private var photoData: Data?
    @FocusState private var focus: EntryField?

    private var unit: String { vehicle.powerType.quantityUnit }
    private var odometer: Double? { Double(odometerText) }
    private var quantity: Double? { Double(quantityText).flatMap { $0 > 0 ? $0 : nil } }
    private var canSave: Bool { odometer != nil && quantity != nil }

    private var odometerWarning: String? {
        guard let odometer, let current = vehicle.currentOdometer, odometer < current else { return nil }
        return "This is lower than the latest reading (\(Int(current)) mi)."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { LabeledContent("Vehicle", value: vehicle.name) }
                OdometerCaptureSection(odometerText: $odometerText, source: $source, photoData: $photoData,
                                       focus: $focus, placeholder: odometerPlaceholder(for: vehicle),
                                       autoScan: startWithCamera, onScanned: { focus = .quantity })
                if let odometerWarning {
                    Section { Label(odometerWarning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
                Section {
                    HStack {
                        TextField(vehicle.powerType == .ev ? "kWh added" : "Gallons added", text: $quantityText)
                            .keyboardType(.decimalPad)
                            .focused($focus, equals: .quantity)
                        Text(unit).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("$")
                        TextField("Total cost (optional)", text: $costText)
                            .keyboardType(.decimalPad)
                            .focused($focus, equals: .cost)
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
                    Button("Save") { save() }.disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    if focus == .cost {
                        Button("Save") { save() }.disabled(!canSave)
                    } else {
                        Button("Next") { advance() }
                    }
                }
            }
            .task {
                guard !startWithCamera else { return }
                try? await Task.sleep(for: .milliseconds(350))
                focus = .odometer
            }
        }
    }

    private func advance() {
        switch focus {
        case .odometer: focus = .quantity
        case .quantity: focus = .cost
        default: focus = nil
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
