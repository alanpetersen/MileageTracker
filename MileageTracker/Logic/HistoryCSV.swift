import Foundation

/// Minimal RFC 4180 reader/writer: quoted fields, doubled quotes, commas and newlines inside quotes.
enum CSV {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var wasQuoted = false
        var chars = Substring(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text).makeIterator()
        var pending = chars.next()

        func endField() {
            row.append(wasQuoted ? field : field.trimmingCharacters(in: .whitespaces))
            field = ""
            wasQuoted = false
        }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }  // skip blank lines
            row = []
        }

        while let c = pending {
            pending = chars.next()
            if inQuotes {
                if c == "\"" {
                    if pending == "\"" { field.append("\""); pending = chars.next() } else { inQuotes = false }
                } else {
                    field.append(c)
                }
                continue
            }
            switch c {
            case "\"": inQuotes = true; wasQuoted = true
            case ",": endField()
            case "\n", "\r\n", "\r": endRow()  // "\r\n" is a single Character in Swift
            default: field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty || wasQuoted { endRow() }
        return rows
    }

    static func escape(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func encode(_ rows: [[String]]) -> String {
        rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }
}

/// One line of the history file: either a fuel/charge entry or a plain odometer reading.
struct HistoryRecord: Equatable {
    enum Kind: String { case fuel, odometer }

    var kind: Kind
    var vehicle: String
    var powerType: PowerType
    var date: Date
    var odometer: Double
    /// Gallons or kWh. Zero for odometer readings.
    var quantity: Double = 0
    var totalCost: Double?
    var gasPrice: Double?
    var electricityRate: Double?
    var source: ReadingSource = .manual
    var loggedBy: String?
    var id: UUID?
}

enum HistoryCSV {
    static let columns = ["type", "vehicle", "vehicle_type", "date", "odometer", "quantity", "total_cost",
                          "gas_price", "electricity_rate", "source", "logged_by", "id"]

    struct ImportResult {
        var records: [HistoryRecord] = []
        /// Human-readable problems, one per skipped line ("Line 4: ...").
        var problems: [String] = []
    }

    // MARK: Export

    static func encode(_ records: [HistoryRecord]) -> String {
        let rows = records.map { r -> [String] in
            [r.kind.rawValue, r.vehicle, r.powerType.rawValue, formatDate(r.date), r.odometer.plainString,
             r.kind == .fuel ? r.quantity.plainString : "",
             r.totalCost.map { String(format: "%.2f", $0) } ?? "",
             r.gasPrice.map { String(format: "%.3f", $0) } ?? "",
             r.electricityRate.map { String(format: "%.4f", $0) } ?? "",
             r.source.rawValue, r.loggedBy ?? "", r.id?.uuidString ?? ""]
        }
        return CSV.encode([columns] + rows)
    }

    // MARK: Import

    /// Header names are matched case-insensitively and may appear in any order. Only `vehicle`, `date`
    /// and `odometer` are required, so a hand-built spreadsheet works for bulk entry. A row with a
    /// quantity is a fill-up/charge; without one it is an odometer reading.
    static func decode(_ text: String) -> ImportResult {
        var result = ImportResult()
        let rows = CSV.parse(text)
        guard let header = rows.first else {
            result.problems.append("The file is empty.")
            return result
        }
        let names = header.map { $0.lowercased().replacingOccurrences(of: " ", with: "_") }
        func index(_ name: String, aliases: [String] = []) -> Int? {
            ([name] + aliases).lazy.compactMap { names.firstIndex(of: $0) }.first
        }
        guard let vehicleIdx = index("vehicle"), let dateIdx = index("date"), let odoIdx = index("odometer", aliases: ["miles"]) else {
            result.problems.append("Missing required columns. The first row must include: vehicle, date, odometer.")
            return result
        }
        let typeIdx = index("type"), powerIdx = index("vehicle_type"), qtyIdx = index("quantity", aliases: ["gallons", "kwh"])
        let costIdx = index("total_cost", aliases: ["cost"]), gasIdx = index("gas_price")
        let rateIdx = index("electricity_rate"), sourceIdx = index("source"), byIdx = index("logged_by"), idIdx = index("id")

        for (offset, row) in rows.dropFirst().enumerated() {
            let line = offset + 2
            func cell(_ i: Int?) -> String {
                guard let i, i < row.count else { return "" }
                return row[i]
            }
            func number(_ i: Int?) -> Double? {
                Double(cell(i).replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ""))
            }

            let vehicle = cell(vehicleIdx)
            guard !vehicle.isEmpty else { result.problems.append("Line \(line): no vehicle."); continue }
            guard let date = parseDate(cell(dateIdx)) else {
                result.problems.append("Line \(line): couldn't read the date \"\(cell(dateIdx))\"."); continue
            }
            guard let odometer = number(odoIdx), odometer >= 0 else {
                result.problems.append("Line \(line): couldn't read the odometer \"\(cell(odoIdx))\"."); continue
            }

            let quantity = number(qtyIdx)
            let typeText = cell(typeIdx).lowercased()
            let isFuel: Bool
            switch typeText {
            case "fuel", "fill-up", "charge", "fillup": isFuel = true
            case "odometer", "reading": isFuel = false
            default: isFuel = (quantity ?? 0) > 0
            }
            // A quantity that is present but unusable is an error, not a reason to quietly treat the row as a reading.
            if (isFuel || !cell(qtyIdx).isEmpty), (quantity ?? 0) <= 0 {
                result.problems.append("Line \(line): a fill-up or charge needs a quantity above zero."); continue
            }

            let kwhColumn = qtyIdx != nil && names[qtyIdx!] == "kwh"
            let power = PowerType(rawValue: cell(powerIdx).lowercased()) ?? (typeText == "charge" || kwhColumn ? .ev : .gas)

            result.records.append(HistoryRecord(
                kind: isFuel ? .fuel : .odometer, vehicle: vehicle, powerType: power, date: date, odometer: odometer,
                quantity: isFuel ? quantity ?? 0 : 0, totalCost: isFuel ? number(costIdx) : nil,
                gasPrice: isFuel ? number(gasIdx) : nil, electricityRate: isFuel ? number(rateIdx) : nil,
                source: ReadingSource(rawValue: cell(sourceIdx).lowercased()) ?? .manual,
                loggedBy: cell(byIdx).isEmpty ? nil : cell(byIdx), id: UUID(uuidString: cell(idIdx))))
        }
        return result
    }

    // MARK: Dates

    /// UTC ISO 8601 ("2026-10-10T19:30:00Z"), so a backup restores to the same instant on any device.
    private static func formatDate(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    static func parseDate(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: .iso8601) { return date }
        if let date = try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)) {
            return date
        }
        for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd", "M/d/yyyy H:mm", "M/d/yyyy", "M/d/yy"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                // A bare date has no time; noon keeps it on the right calendar day in any time zone.
                return format.contains("H") ? date : Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date)
            }
        }
        return nil
    }
}
