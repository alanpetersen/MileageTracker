import Foundation

/// Fetches the latest weekly retail regular-gasoline price from the U.S. EIA open data API.
/// Requires a free API key (https://www.eia.gov/opendata/register.php).
enum GasPriceService {
    struct Price: Equatable {
        let dollarsPerGallon: Double
        let areaName: String
        let period: String
    }

    enum GasPriceError: LocalizedError {
        case missingKey
        case noData
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .missingKey: "Add an EIA API key in Settings to fetch local gas prices."
            case .noData: "EIA returned no price data for your area."
            case .http(let code): "EIA request failed (HTTP \(code)). Check your API key."
            }
        }
    }

    /// Most specific series first, then the regional (PADD) series, then national.
    static func candidateAreas(forState state: String) -> [(code: String, name: String)] {
        var areas: [(String, String)] = []
        if stateSeries.contains(state) { areas.append(("S\(state)", state)) }
        if let padd = paddRegions[state] { areas.append(padd) }
        areas.append(("NUS", "U.S. average"))
        return areas
    }

    static func fetch(state: String, apiKey: String, session: URLSession = .shared) async throws -> Price {
        guard !apiKey.isEmpty else { throw GasPriceError.missingKey }
        for area in candidateAreas(forState: state) {
            if let price = try await latest(area: area, apiKey: apiKey, session: session) { return price }
        }
        throw GasPriceError.noData
    }

    private static func latest(area: (code: String, name: String), apiKey: String,
                               session: URLSession) async throws -> Price? {
        var components = URLComponents(string: "https://api.eia.gov/v2/petroleum/pri/gnd/data/")!
        components.queryItems = [
            .init(name: "api_key", value: apiKey),
            .init(name: "frequency", value: "weekly"),
            .init(name: "data[0]", value: "value"),
            .init(name: "facets[product][]", value: "EPMR"),
            .init(name: "facets[duoarea][]", value: area.code),
            .init(name: "sort[0][column]", value: "period"),
            .init(name: "sort[0][direction]", value: "desc"),
            .init(name: "length", value: "1"),
        ]
        let (data, response) = try await session.data(from: components.url!)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // A bad series code returns 400; try the next candidate. Auth failures are fatal.
            if http.statusCode == 400 { return nil }
            throw GasPriceError.http(http.statusCode)
        }
        let decoded = try JSONDecoder().decode(EIAResponse.self, from: data)
        guard let row = decoded.response.data.first, let value = row.value else { return nil }
        return Price(dollarsPerGallon: value, areaName: area.name, period: row.period)
    }

    private struct EIAResponse: Decodable {
        struct Body: Decodable { let data: [Row] }
        struct Row: Decodable {
            let period: String
            let value: Double?

            enum CodingKeys: String, CodingKey { case period, value }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                period = try container.decode(String.self, forKey: .period)
                // EIA sends values as either strings or numbers.
                if let number = try? container.decode(Double.self, forKey: .value) {
                    value = number
                } else if let string = try? container.decode(String.self, forKey: .value) {
                    value = Double(string)
                } else {
                    value = nil
                }
            }
        }
        let response: Body
    }

    // States with their own EIA weekly series.
    private static let stateSeries: Set<String> = ["CA", "CO", "FL", "MA", "MN", "NY", "OH", "TX", "WA"]

    private static let paddRegions: [String: (code: String, name: String)] = {
        let groups: [(String, String, [String])] = [
            ("R1X", "New England", ["CT", "ME", "MA", "NH", "RI", "VT"]),
            ("R1Y", "Central Atlantic", ["DE", "DC", "MD", "NJ", "NY", "PA"]),
            ("R1Z", "Lower Atlantic", ["FL", "GA", "NC", "SC", "VA", "WV"]),
            ("R20", "Midwest", ["IL", "IN", "IA", "KS", "KY", "MI", "MN", "MO", "NE", "ND", "OH", "OK", "SD", "TN", "WI"]),
            ("R30", "Gulf Coast", ["AL", "AR", "LA", "MS", "NM", "TX"]),
            ("R40", "Rocky Mountain", ["CO", "ID", "MT", "UT", "WY"]),
            ("R50", "West Coast", ["AK", "AZ", "CA", "HI", "NV", "OR", "WA"]),
        ]
        var map: [String: (String, String)] = [:]
        for (code, name, states) in groups { for state in states { map[state] = (code, name) } }
        return map
    }()

    static let allStates: [String] = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA", "HI", "ID", "IL", "IN", "IA", "KS",
        "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY", "NC",
        "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY",
    ]
}
