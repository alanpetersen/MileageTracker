import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @AppStorage("selectedVehicleID") private var selectedID = ""
    @State private var sheet: EntrySheet?
    @State private var showingSettings = false
    @State private var showingAddVehicle = false

    enum EntrySheet: Identifiable {
        case fuel(scan: Bool)
        case reading(scan: Bool)

        var id: String {
            switch self {
            case .fuel(let scan): "fuel-\(scan)"
            case .reading(let scan): "reading-\(scan)"
            }
        }
    }

    private var selected: Vehicle? {
        vehicles.first { $0.uuid.uuidString == selectedID } ?? vehicles.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if let vehicle = selected {
                    dashboard(for: vehicle)
                } else {
                    ContentUnavailableView {
                        Label("No Vehicles", systemImage: "car")
                    } description: {
                        Text("Add a vehicle to start tracking mileage.")
                    } actions: {
                        Button("Add Vehicle") { showingAddVehicle = true }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Mileage Tracker")
            .navigationDestination(for: Vehicle.self) { VehicleDetailView(vehicle: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
            }
            .sheet(item: $sheet) { sheet in
                if let vehicle = selected {
                    switch sheet {
                    case .fuel(let scan): AddFuelEntryView(vehicle: vehicle, startWithCamera: scan)
                    case .reading(let scan): AddReadingView(vehicle: vehicle, startWithCamera: scan)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingAddVehicle) { AddVehicleView() }
        }
    }

    private func dashboard(for vehicle: Vehicle) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                if vehicles.count > 1 { vehiclePicker(selected: vehicle) }

                let isEV = vehicle.powerType == .ev
                let entryTitle = vehicle.powerType.entryTitle
                let entryIcon = isEV ? "bolt.car.fill" : "fuelpump.fill"

                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        Button { sheet = .fuel(scan: false) } label: {
                            ActionTile(title: "Log \(entryTitle)", systemImage: entryIcon,
                                       tint: isEV ? .green : .orange, prominent: true)
                        }
                        Button { sheet = .fuel(scan: true) } label: {
                            ActionTile(title: "Scan & Log \(entryTitle)", systemImage: "camera.viewfinder",
                                       tint: isEV ? .green : .orange)
                        }
                    }
                    GridRow {
                        Button { sheet = .reading(scan: false) } label: {
                            ActionTile(title: "Log Odometer", systemImage: "gauge.with.needle", tint: .blue)
                        }
                        Button { sheet = .reading(scan: true) } label: {
                            ActionTile(title: "Scan Odometer", systemImage: "camera.viewfinder", tint: .blue)
                        }
                    }
                    GridRow {
                        NavigationLink(value: vehicle) {
                            ActionTile(title: "History", systemImage: "list.bullet.rectangle", tint: .purple)
                        }
                        NavigationLink {
                            VehicleListView()
                        } label: {
                            ActionTile(title: "Vehicles", systemImage: "car.2.fill", tint: .teal)
                        }
                    }
                }
                .buttonStyle(.plain)

                GroupBox {
                    VStack(spacing: 8) {
                        VehicleOverviewRows(vehicle: vehicle)
                    }
                } label: {
                    Label(vehicle.name, systemImage: isEV ? "bolt.car" : "fuelpump")
                }

                gasPriceFootnote
            }
            .padding()
        }
    }

    private func vehiclePicker(selected vehicle: Vehicle) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(vehicles) { candidate in
                    let isSelected = candidate.persistentModelID == vehicle.persistentModelID
                    Button {
                        selectedID = candidate.uuid.uuidString
                    } label: {
                        Label(candidate.name, systemImage: candidate.powerType == .ev ? "bolt.car" : "fuelpump")
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground), in: .capsule)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
                Button("Add Vehicle", systemImage: "plus") { showingAddVehicle = true }
                    .labelStyle(.iconOnly)
                    .padding(8)
                    .background(Color(.secondarySystemBackground), in: .circle)
            }
        }
    }

    @ViewBuilder
    private var gasPriceFootnote: some View {
        if let price = settings.gasPrice {
            Text("Gas \(price, format: .currency(code: "USD"))/gal · \(settings.gasPriceDescription)")
                .font(.footnote).foregroundStyle(.secondary)
        } else {
            Text("Set a gas price in Settings to compare EV costs.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

private struct ActionTile: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    var prominent = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.title)
            Text(title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
        }
        .foregroundStyle(prominent ? Color.white : tint)
        .frame(maxWidth: .infinity, minHeight: 96)
        .padding(8)
        .background(prominent ? tint : tint.opacity(0.15), in: .rect(cornerRadius: 16))
    }
}
