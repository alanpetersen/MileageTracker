import SwiftUI
import CoreData

private func odometerPlaceholder(for vehicle: Vehicle) -> String {
    guard let last = vehicle.currentOdometer else { return "Odometer (mi)" }
    return "Odometer (last: \(Int(last)))"
}

struct AddReadingView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @ObservedObject var vehicle: Vehicle
    var startWithCamera = false
    /// When set, the form edits this reading instead of creating a new one.
    var editing: OdometerReading?

    @State private var date: Date
    @State private var odometerText: String
    @State private var source: ReadingSource
    @State private var photoData: Data?
    @State private var confirmingDelete = false
    @FocusState private var focus: EntryField?

    init(vehicle: Vehicle, startWithCamera: Bool = false, editing: OdometerReading? = nil) {
        self.vehicle = vehicle
        self.startWithCamera = startWithCamera
        self.editing = editing
        _date = State(initialValue: editing?.date ?? .now)
        _odometerText = State(initialValue: editing.map { $0.miles.plainString } ?? "")
        _source = State(initialValue: editing?.source ?? .manual)
        _photoData = State(initialValue: editing?.photoData)
    }

    private var odometer: Double? { Double(odometerText) }

    var body: some View {
        NavigationStack {
            Form {
                Section { LabeledContent("Vehicle", value: vehicle.displayName) }
                OdometerCaptureSection(odometerText: $odometerText, source: $source, photoData: $photoData,
                                       focus: $focus, placeholder: odometerPlaceholder(for: vehicle),
                                       autoScan: startWithCamera, onScanned: { focus = nil })
                Section { DatePicker("Date", selection: $date) }
                if editing != nil {
                    DeleteSection(confirming: $confirmingDelete, what: "reading") { deleteEditing() }
                }
            }
            .navigationTitle(editing == nil ? "Odometer Reading" : "Edit Odometer Reading")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(odometer == nil)
                }
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Save") { save() }.disabled(odometer == nil)
                }
                #endif
            }
            .task {
                guard !startWithCamera, editing == nil else { return }
                try? await Task.sleep(for: .milliseconds(350))
                focus = .odometer
            }
        }
    }

    private func save() {
        guard let odometer else { return }
        let reading: OdometerReading
        if let editing {
            reading = editing
        } else {
            reading = OdometerReading(context: context)
            context.place(reading, alongside: vehicle)
            reading.loggedBy = settings.loggedByName
            reading.vehicle = vehicle
        }
        reading.date = date
        reading.miles = odometer
        reading.source = source
        reading.photoData = photoData
        context.saveOrLog()
        dismiss()
    }

    private func deleteEditing() {
        if let editing { context.delete(editing) }
        context.saveOrLog()
        dismiss()
    }
}

/// A destructive button with a confirmation, shown at the bottom of edit forms.
private struct DeleteSection: View {
    @Binding var confirming: Bool
    let what: String
    let onDelete: () -> Void

    var body: some View {
        Section {
            Button("Delete \(what)", role: .destructive) { confirming = true }
                .confirmationDialog("Delete this \(what)?", isPresented: $confirming, titleVisibility: .visible) {
                    Button("Delete", role: .destructive, action: onDelete)
                }
        }
    }
}

struct AddFuelEntryView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @ObservedObject var vehicle: Vehicle
    var startWithCamera = false
    /// When set, the form edits this entry instead of creating a new one.
    var editing: FuelEntry?

    @State private var date: Date
    @State private var odometerText: String
    @State private var quantityText: String
    @State private var costText: String
    @State private var gasPriceText: String
    @State private var source: ReadingSource
    @State private var photoData: Data?
    @State private var confirmingDelete = false
    @FocusState private var focus: EntryField?

    init(vehicle: Vehicle, startWithCamera: Bool = false, editing: FuelEntry? = nil, currentGasPrice: Double? = nil) {
        self.vehicle = vehicle
        self.startWithCamera = startWithCamera
        self.editing = editing
        _date = State(initialValue: editing?.date ?? .now)
        _odometerText = State(initialValue: editing.map { $0.odometer.plainString } ?? "")
        _quantityText = State(initialValue: editing.map { $0.quantity.plainString } ?? "")
        _costText = State(initialValue: editing?.cost.map { String(format: "%.2f", $0) } ?? "")
        // An entry keeps the gas price it was logged with; a new one starts from today's.
        _gasPriceText = State(initialValue: (editing?.gasPrice ?? currentGasPrice).map { String(format: "%.3f", $0) } ?? "")
        _source = State(initialValue: editing?.source ?? .manual)
        _photoData = State(initialValue: editing?.photoData)
    }

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
                Section { LabeledContent("Vehicle", value: vehicle.displayName) }
                OdometerCaptureSection(odometerText: $odometerText, source: $source, photoData: $photoData,
                                       focus: $focus, placeholder: odometerPlaceholder(for: vehicle),
                                       autoScan: startWithCamera, onScanned: { focus = .quantity })
                if let odometerWarning {
                    Section { Label(odometerWarning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
                Section {
                    HStack {
                        TextField(vehicle.powerType == .ev ? "kWh added" : "Gallons added", text: $quantityText)
                            .decimalKeyboard()
                            .focused($focus, equals: .quantity)
                        Text(unit).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("$")
                        TextField("Total cost (optional)", text: $costText)
                            .decimalKeyboard()
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
                if vehicle.powerType == .ev {
                    Section {
                        HStack {
                            Text("Gas price $/gal")
                            Spacer()
                            TextField("0.00", text: $gasPriceText)
                                .decimalKeyboard()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    } footer: {
                        Text("Saved with this charge, so effective MPG isn't changed later by gas price swings.")
                    }
                }
                if editing != nil {
                    DeleteSection(confirming: $confirmingDelete, what: vehicle.powerType.entryTitle.lowercased()) { deleteEditing() }
                }
            }
            .navigationTitle(editing == nil ? "Log \(vehicle.powerType.entryTitle)" : "Edit \(vehicle.powerType.entryTitle)")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    if focus == .cost {
                        Button("Save") { save() }.disabled(!canSave)
                    } else {
                        Button("Next") { advance() }
                    }
                }
                #endif
            }
            .task {
                guard !startWithCamera, editing == nil else { return }
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
        let entry: FuelEntry
        if let editing {
            entry = editing
        } else {
            entry = FuelEntry(context: context)
            context.place(entry, alongside: vehicle)
            entry.loggedBy = settings.loggedByName
            entry.vehicle = vehicle
        }
        let cost = Double(costText)
        entry.date = date
        entry.odometer = odometer
        entry.quantity = quantity
        entry.cost = cost
        entry.source = source
        entry.photoData = photoData
        stampPrices(on: entry, cost: cost, quantity: quantity)
        context.saveOrLog()
        dismiss()
    }

    /// Records the prices in effect, so history stays accurate when prices move later.
    private func stampPrices(on entry: FuelEntry, cost: Double?, quantity: Double) {
        let paid = cost.map { $0 / quantity }
        switch vehicle.powerType {
        case .gas:
            // What you actually paid per gallon beats the area average.
            entry.gasPrice = paid ?? entry.gasPrice ?? settings.gasPrice
        case .ev:
            entry.gasPrice = Double(gasPriceText).flatMap { $0 > 0 ? $0 : nil } ?? entry.gasPrice ?? settings.gasPrice
            entry.electricityRate = paid ?? entry.electricityRate ?? settings.defaultElectricityRate
        }
    }

    private func deleteEditing() {
        if let editing { context.delete(editing) }
        context.saveOrLog()
        dismiss()
    }
}
