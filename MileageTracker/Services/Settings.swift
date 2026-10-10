import Foundation
import Observation

/// App-wide settings plus the current gas price used for effective-MPG calculations.
@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    /// Shown next to entries you log, so others in a shared household can tell who added them.
    var yourName: String { didSet { defaults.set(yourName, forKey: "yourName") } }
    var eiaAPIKey: String { didSet { defaults.set(eiaAPIKey, forKey: "eiaAPIKey") } }
    var stateCode: String { didSet { defaults.set(stateCode, forKey: "stateCode") } }
    var useManualGasPrice: Bool { didSet { defaults.set(useManualGasPrice, forKey: "useManualGasPrice") } }
    var manualGasPrice: Double { didSet { defaults.set(manualGasPrice, forKey: "manualGasPrice") } }
    /// Used for EV charges that have no cost entered, in dollars per kWh.
    var defaultElectricityRate: Double { didSet { defaults.set(defaultElectricityRate, forKey: "defaultElectricityRate") } }

    private(set) var fetchedPrice: GasPriceService.Price?
    private(set) var isFetching = false
    private(set) var fetchError: String?

    init() {
        yourName = defaults.string(forKey: "yourName") ?? ""
        eiaAPIKey = defaults.string(forKey: "eiaAPIKey") ?? ""
        stateCode = defaults.string(forKey: "stateCode") ?? "CA"
        useManualGasPrice = defaults.bool(forKey: "useManualGasPrice")
        manualGasPrice = defaults.double(forKey: "manualGasPrice")
        let rate = defaults.double(forKey: "defaultElectricityRate")
        defaultElectricityRate = rate > 0 ? rate : 0.17
        if defaults.object(forKey: "fetchedGasPrice") != nil {
            fetchedPrice = .init(dollarsPerGallon: defaults.double(forKey: "fetchedGasPrice"),
                                 areaName: defaults.string(forKey: "fetchedGasArea") ?? "",
                                 period: defaults.string(forKey: "fetchedGasPeriod") ?? "")
        }
    }

    var loggedByName: String? {
        let trimmed = yourName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The price effective-MPG calculations should use right now.
    var gasPrice: Double? {
        if useManualGasPrice { return manualGasPrice > 0 ? manualGasPrice : nil }
        return fetchedPrice?.dollarsPerGallon ?? (manualGasPrice > 0 ? manualGasPrice : nil)
    }

    var gasPriceDescription: String {
        if useManualGasPrice || fetchedPrice == nil { return gasPrice == nil ? "No gas price set" : "Manual price" }
        let price = fetchedPrice!
        return "\(price.areaName) weekly average, \(price.period)"
    }

    @MainActor
    func refreshGasPrice() async {
        guard !isFetching else { return }
        isFetching = true
        fetchError = nil
        defer { isFetching = false }
        do {
            let price = try await GasPriceService.fetch(state: stateCode, apiKey: eiaAPIKey)
            fetchedPrice = price
            defaults.set(price.dollarsPerGallon, forKey: "fetchedGasPrice")
            defaults.set(price.areaName, forKey: "fetchedGasArea")
            defaults.set(price.period, forKey: "fetchedGasPeriod")
        } catch {
            fetchError = error.localizedDescription
        }
    }
}
