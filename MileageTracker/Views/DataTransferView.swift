import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String

    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Backup and bulk entry: export every vehicle's history in the household to CSV, or import a CSV.
struct DataTransferView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Vehicle.createdAt, ascending: true)])
    private var allVehicles: FetchedResults<Vehicle>
    let household: Household?

    @State private var exporting = false
    @State private var exportDocument = CSVDocument(text: "")
    @State private var importing = false
    @State private var pending: HistoryCSV.ImportResult?
    @State private var message: String?

    private var vehicles: [Vehicle] { allVehicles.filter { $0.household == household } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Export History…", systemImage: "square.and.arrow.up") {
                        exportDocument = CSVDocument(text: HistoryCSV.encode(HistoryTransfer.records(for: vehicles)))
                        exporting = true
                    }
                    .disabled(vehicles.isEmpty)
                } footer: {
                    Text("Saves every vehicle in \(household?.displayName ?? "this household") — fill-ups, charges, odometer readings and the prices recorded with them — as a CSV file you can keep as a backup or open in a spreadsheet.")
                }
                Section {
                    Button("Import History…", systemImage: "square.and.arrow.down") { importing = true }
                        .disabled(household == nil)
                } footer: {
                    Text("Columns: \(HistoryCSV.columns.joined(separator: ", ")). Only vehicle, date and odometer are required; a row with a quantity is a fill-up or charge. Vehicles that don't exist yet are created. Rows already in the app are skipped, so re-importing a backup is safe.")
                }
                if let message { Section { Text(message) } }
            }
            .navigationTitle("Backup & Import")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .commaSeparatedText,
                          defaultFilename: "MileageTracker-\(Date.now.formatted(.iso8601.year().month().day()))") { result in
                switch result {
                case .success: message = "Exported."
                case .failure(let error): message = "Export failed: \(error.localizedDescription)"
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                read(result)
            }
            .confirmationDialog(confirmTitle, isPresented: confirmBinding, titleVisibility: .visible) {
                Button("Import") { commitImport() }
                Button("Cancel", role: .cancel) { pending = nil }
            } message: {
                Text(confirmMessage)
            }
        }
        .macSheetSize()
    }

    private var confirmBinding: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }
    private var confirmTitle: String { "Import \(pending?.records.count ?? 0) rows?" }
    private var confirmMessage: String {
        let problems = pending?.problems ?? []
        guard !problems.isEmpty else { return "They'll be added to \(household?.displayName ?? "your household")." }
        return "\(problems.count) rows will be skipped:\n" + problems.prefix(5).joined(separator: "\n")
            + (problems.count > 5 ? "\n…" : "")
    }

    private func read(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let parsed = HistoryCSV.decode(String(decoding: try Data(contentsOf: url), as: UTF8.self))
            if parsed.records.isEmpty {
                message = (parsed.problems.isEmpty ? ["Nothing to import."] : Array(parsed.problems.prefix(5))).joined(separator: "\n")
            } else {
                pending = parsed
            }
        } catch {
            message = "Couldn't read the file: \(error.localizedDescription)"
        }
    }

    private func commitImport() {
        guard let household, let pending else { return }
        let summary = HistoryTransfer.importRecords(pending.records, into: household, context: context)
        context.saveOrLog()
        self.pending = nil
        var text = "Imported \(summary.added) rows"
        if summary.vehiclesCreated > 0 { text += ", created \(summary.vehiclesCreated) vehicles" }
        if summary.duplicates > 0 { text += ", skipped \(summary.duplicates) already present" }
        if !pending.problems.isEmpty { text += ", skipped \(pending.problems.count) invalid" }
        message = text + "."
    }
}
