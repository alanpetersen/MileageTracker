import SwiftUI
import CoreData

/// Pushed from the dashboard's NavigationStack. Rows link straight to the detail view rather than by value,
/// so they don't depend on a navigationDestination being registered further up the stack.
struct VehicleListView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Vehicle.createdAt, ascending: true)])
    private var allVehicles: FetchedResults<Vehicle>
    let household: Household?
    @State private var showingAdd = false
    @AppStorage("defaultVehicleID") private var defaultVehicleID = ""

    private var vehicles: [Vehicle] { allVehicles.filter { $0.household == household } }

    var body: some View {
        let vehicles = vehicles
        List {
            ForEach(vehicles) { vehicle in
                NavigationLink {
                    VehicleDetailView(vehicle: vehicle)
                } label: {
                    VehicleRow(vehicle: vehicle, isDefault: vehicle.uuid?.uuidString == defaultVehicleID)
                }
                .swipeActions(edge: .leading) {
                    Button("Default", systemImage: "star") { defaultVehicleID = vehicle.uuid?.uuidString ?? "" }
                        .tint(.yellow)
                }
            }
            .onDelete { offsets in
                for index in offsets { context.delete(vehicles[index]) }
                context.saveOrLog()
            }
        }
        .overlay {
            if vehicles.isEmpty {
                ContentUnavailableView("No Vehicles", systemImage: "car",
                                       description: Text("Add a vehicle to start tracking mileage."))
            }
        }
        .navigationTitle(household?.displayName ?? "Vehicles")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Vehicle", systemImage: "plus") { showingAdd = true }
            }
        }
        .sheet(isPresented: $showingAdd) { AddVehicleView(household: household) }
    }
}

private struct VehicleRow: View {
    @ObservedObject var vehicle: Vehicle
    var isDefault = false

    var body: some View {
        HStack {
            Image(systemName: vehicle.powerType == .ev ? "bolt.car" : "fuelpump")
                .foregroundStyle(vehicle.powerType == .ev ? .green : .orange)
                .frame(width: 32)
            VStack(alignment: .leading) {
                Text(vehicle.displayName).font(.headline)
                if !vehicle.subtitle.isEmpty {
                    Text(vehicle.subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isDefault { Image(systemName: "star.fill").foregroundStyle(.yellow) }
            if let odometer = vehicle.currentOdometer {
                Text("\(odometer, format: .number.precision(.fractionLength(0))) mi")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AddVehicleView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// Nil when you have no household yet; one is created on save.
    let household: Household?

    @State private var name = ""
    @State private var make = ""
    @State private var model = ""
    @State private var year = ""
    @State private var powerType = PowerType.gas

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Daily Driver)", text: $name)
                    Picker("Type", selection: $powerType) {
                        ForEach(PowerType.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("Details (optional)") {
                    TextField("Make", text: $make)
                    TextField("Model", text: $model)
                    TextField("Year", text: $year).numberKeyboard()
                }
            }
            .navigationTitle("New Vehicle")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let owner = household ?? PersistenceController.shared.makeHousehold()
        let vehicle = Vehicle(context: context)
        context.place(vehicle, alongside: owner)
        vehicle.name = name.trimmingCharacters(in: .whitespaces)
        vehicle.make = make
        vehicle.model = model
        vehicle.year = Int(year).map { NSNumber(value: $0) }
        vehicle.powerType = powerType
        vehicle.household = owner
        context.saveOrLog()
        dismiss()
    }
}
