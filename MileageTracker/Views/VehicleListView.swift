import SwiftUI
import SwiftData

/// Pushed from the dashboard; relies on the dashboard's NavigationStack for vehicle detail navigation.
struct VehicleListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @State private var showingAdd = false

    var body: some View {
        List {
            ForEach(vehicles) { vehicle in
                NavigationLink(value: vehicle) {
                    VehicleRow(vehicle: vehicle)
                }
            }
            .onDelete { offsets in
                for index in offsets { context.delete(vehicles[index]) }
            }
        }
        .overlay {
            if vehicles.isEmpty {
                ContentUnavailableView("No Vehicles", systemImage: "car",
                                       description: Text("Add a vehicle to start tracking mileage."))
            }
        }
        .navigationTitle("Vehicles")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Vehicle", systemImage: "plus") { showingAdd = true }
            }
        }
        .sheet(isPresented: $showingAdd) { AddVehicleView() }
    }
}

private struct VehicleRow: View {
    let vehicle: Vehicle

    var body: some View {
        HStack {
            Image(systemName: vehicle.powerType == .ev ? "bolt.car" : "fuelpump")
                .foregroundStyle(vehicle.powerType == .ev ? .green : .orange)
                .frame(width: 32)
            VStack(alignment: .leading) {
                Text(vehicle.name).font(.headline)
                if !vehicle.subtitle.isEmpty {
                    Text(vehicle.subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let odometer = vehicle.currentOdometer {
                Text("\(odometer, format: .number.precision(.fractionLength(0))) mi")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AddVehicleView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
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
                    TextField("Year", text: $year).keyboardType(.numberPad)
                }
            }
            .navigationTitle("New Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        context.insert(Vehicle(name: name.trimmingCharacters(in: .whitespaces),
                                               make: make, model: model, year: Int(year), powerType: powerType))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
