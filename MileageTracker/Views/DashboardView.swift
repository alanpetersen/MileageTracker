import SwiftUI
import CoreData

struct DashboardView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(AppSettings.self) private var settings
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Household.createdAt, ascending: true)])
    private var households: FetchedResults<Household>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Vehicle.createdAt, ascending: true)])
    private var allVehicles: FetchedResults<Vehicle>
    @AppStorage("activeHouseholdID") private var activeHouseholdID = ""
    @AppStorage("selectedVehicleID") private var selectedID = ""
    @AppStorage("defaultVehicleID") private var defaultVehicleID = ""
    @State private var appliedDefault = false
    @State private var sheet: EntrySheet?
    @State private var showingSettings = false
    @State private var showingTransfer = false
    @State private var showingAddVehicle = false
    @State private var renaming = false
    @State private var newHouseholdName = ""
    @State private var shareRevision = 0
    @State private var shareError: String?

    private let persistence = PersistenceController.shared

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

    /// The explicitly chosen household, else one shared with you (you likely just accepted it), else your own.
    private var household: Household? {
        households.first { $0.uuid?.uuidString == activeHouseholdID }
            ?? households.first { persistence.isSharedWithMe($0) }
            ?? households.first
    }

    private var vehicles: [Vehicle] { allVehicles.filter { $0.household == household } }

    private var selected: Vehicle? {
        vehicles.first { $0.uuid?.uuidString == selectedID } ?? vehicles.first
    }

    /// On launch, selects the default vehicle (and its household). Retries while vehicles are still loading
    /// from iCloud, and stops once applied so it never overrides a choice made afterwards.
    private func applyDefaultVehicle() {
        guard !appliedDefault, !defaultVehicleID.isEmpty else { return }
        guard let vehicle = allVehicles.first(where: { $0.uuid?.uuidString == defaultVehicleID }) else { return }
        appliedDefault = true
        selectedID = defaultVehicleID
        if let id = vehicle.household?.uuid?.uuidString { activeHouseholdID = id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let vehicle = selected {
                    dashboard(for: vehicle)
                } else {
                    VStack {
                        if let household { householdHeader(household).padding() }
                        ContentUnavailableView {
                            Label("No Vehicles", systemImage: "car")
                        } description: {
                            Text("Add a vehicle to start tracking mileage. If someone invited you to their household, open the invitation link on this device.")
                        } actions: {
                            Button("Add Vehicle") { showingAddVehicle = true }.buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .navigationTitle("Mileage Tracker")
            .task { applyDefaultVehicle() }
            .onChange(of: allVehicles.count) { _, _ in applyDefaultVehicle() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu("More", systemImage: "ellipsis.circle") {
                        Button("Backup & Import…", systemImage: "arrow.up.arrow.down.square") { showingTransfer = true }
                        Button("Settings", systemImage: "gearshape") { showingSettings = true }
                    }
                }
            }
            .sheet(item: $sheet) { sheet in
                if let vehicle = selected {
                    switch sheet {
                    case .fuel(let scan): AddFuelEntryView(vehicle: vehicle, startWithCamera: scan, currentGasPrice: settings.gasPrice)
                    case .reading(let scan): AddReadingView(vehicle: vehicle, startWithCamera: scan)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingTransfer) { DataTransferView(household: household) }
            .sheet(isPresented: $showingAddVehicle) { AddVehicleView(household: household) }
            .alert("Rename Household", isPresented: $renaming) {
                TextField("Name", text: $newHouseholdName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    household?.name = newHouseholdName.trimmingCharacters(in: .whitespaces)
                    context.saveOrLog()
                }
            }
            .alert("Sharing Failed", isPresented: .constant(shareError != nil)) {
                Button("OK") { shareError = nil }
            } message: {
                Text(shareError ?? "")
            }
        }
    }

    private func dashboard(for vehicle: Vehicle) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                if let household { householdHeader(household) }
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
                        NavigationLink {
                            VehicleDetailView(vehicle: vehicle)
                        } label: {
                            ActionTile(title: "History", systemImage: "list.bullet.rectangle", tint: .purple)
                        }
                        NavigationLink {
                            VehicleListView(household: household)
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
                    Label(vehicle.displayName, systemImage: isEV ? "bolt.car" : "fuelpump")
                }

                gasPriceFootnote
            }
            .padding()
        }
    }

    private func householdHeader(_ household: Household) -> some View {
        let _ = shareRevision
        let share = persistence.share(for: household)
        let others = (share?.participants.count ?? 1) - 1
        let sharedWithMe = persistence.isSharedWithMe(household)

        return HStack {
            Menu {
                if households.count > 1 {
                    Picker("Household", selection: $activeHouseholdID) {
                        ForEach(households) { candidate in
                            Text(candidate.displayName).tag(candidate.uuid?.uuidString ?? "")
                        }
                    }
                }
                Button("Rename…", systemImage: "pencil") {
                    newHouseholdName = household.name ?? ""
                    renaming = true
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label(household.displayName, systemImage: "house.fill").font(.headline)
                    if sharedWithMe {
                        Text("Shared with you").font(.caption).foregroundStyle(.secondary)
                    } else if others > 0 {
                        Text("Shared with \(others) \(others == 1 ? "person" : "people")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                Task {
                    do {
                        try await persistence.presentSharing(for: household) { shareRevision += 1 }
                    } catch {
                        shareError = error.localizedDescription
                    }
                }
            } label: {
                Label(share == nil ? "Share" : "People", systemImage: share == nil ? "person.badge.plus" : "person.2.fill")
            }
            .buttonStyle(.bordered)
        }
    }

    private func vehiclePicker(selected vehicle: Vehicle) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(vehicles) { candidate in
                    let isSelected = candidate == vehicle
                    Button {
                        selectedID = candidate.uuid?.uuidString ?? ""
                    } label: {
                        Label(candidate.displayName, systemImage: candidate.powerType == .ev ? "bolt.car" : "fuelpump")
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(isSelected ? Color.accentColor : Color.secondaryFill, in: .capsule)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
                Button("Add Vehicle", systemImage: "plus") { showingAddVehicle = true }
                    .labelStyle(.iconOnly)
                    .padding(8)
                    .background(Color.secondaryFill, in: .circle)
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
