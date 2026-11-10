import Foundation

/// Static travel facts per country (ISO code).
enum CountryInfo {
    struct Info { let currency: String; let plugs: String; let voltage: Int }

    static let data: [String: Info] = [
        "CH": Info(currency: "CHF", plugs: "J, C", voltage: 230), "DE": Info(currency: "EUR", plugs: "C, F", voltage: 230),
        "AT": Info(currency: "EUR", plugs: "C, F", voltage: 230), "FR": Info(currency: "EUR", plugs: "C, E", voltage: 230),
        "IT": Info(currency: "EUR", plugs: "C, F, L", voltage: 230), "ES": Info(currency: "EUR", plugs: "C, F", voltage: 230),
        "PT": Info(currency: "EUR", plugs: "C, F", voltage: 230), "NL": Info(currency: "EUR", plugs: "C, F", voltage: 230),
        "BE": Info(currency: "EUR", plugs: "C, E", voltage: 230), "GR": Info(currency: "EUR", plugs: "C, F", voltage: 230),
        "IE": Info(currency: "EUR", plugs: "G", voltage: 230), "GB": Info(currency: "GBP", plugs: "G", voltage: 230),
        "HR": Info(currency: "EUR", plugs: "C, F", voltage: 230), "CY": Info(currency: "EUR", plugs: "G", voltage: 230),
        "MT": Info(currency: "EUR", plugs: "G", voltage: 230), "DK": Info(currency: "DKK", plugs: "C, E, F, K", voltage: 230),
        "SE": Info(currency: "SEK", plugs: "C, F", voltage: 230), "NO": Info(currency: "NOK", plugs: "C, F", voltage: 230),
        "IS": Info(currency: "ISK", plugs: "C, F", voltage: 230), "PL": Info(currency: "PLN", plugs: "C, E", voltage: 230),
        "CZ": Info(currency: "CZK", plugs: "C, E", voltage: 230), "HU": Info(currency: "HUF", plugs: "C, F", voltage: 230),
        "TR": Info(currency: "TRY", plugs: "C, F", voltage: 230), "US": Info(currency: "USD", plugs: "A, B", voltage: 120),
        "CA": Info(currency: "CAD", plugs: "A, B", voltage: 120), "MX": Info(currency: "MXN", plugs: "A, B", voltage: 127),
        "AR": Info(currency: "ARS", plugs: "C, I", voltage: 220), "BR": Info(currency: "BRL", plugs: "C, N", voltage: 127),
        "CL": Info(currency: "CLP", plugs: "C, L", voltage: 220), "CO": Info(currency: "COP", plugs: "A, B", voltage: 110),
        "PE": Info(currency: "PEN", plugs: "A, C", voltage: 220), "UY": Info(currency: "UYU", plugs: "C, F, I, L", voltage: 220),
        "AE": Info(currency: "AED", plugs: "G", voltage: 230), "QA": Info(currency: "QAR", plugs: "G", voltage: 240),
        "EG": Info(currency: "EGP", plugs: "C, F", voltage: 220), "MA": Info(currency: "MAD", plugs: "C, E", voltage: 220),
        "ZA": Info(currency: "ZAR", plugs: "M, N", voltage: 230), "KE": Info(currency: "KES", plugs: "G", voltage: 240),
        "TH": Info(currency: "THB", plugs: "A, B, C, O", voltage: 220), "ID": Info(currency: "IDR", plugs: "C, F", voltage: 230),
        "SG": Info(currency: "SGD", plugs: "G", voltage: 230), "MY": Info(currency: "MYR", plugs: "G", voltage: 240),
        "VN": Info(currency: "VND", plugs: "A, C", voltage: 220), "PH": Info(currency: "PHP", plugs: "A, B, C", voltage: 220),
        "JP": Info(currency: "JPY", plugs: "A, B", voltage: 100), "KR": Info(currency: "KRW", plugs: "C, F", voltage: 220),
        "CN": Info(currency: "CNY", plugs: "A, C, I", voltage: 220), "HK": Info(currency: "HKD", plugs: "G", voltage: 220),
        "IN": Info(currency: "INR", plugs: "C, D, M", voltage: 230), "LK": Info(currency: "LKR", plugs: "D, G", voltage: 230),
        "MV": Info(currency: "MVR", plugs: "D, G", voltage: 230), "AU": Info(currency: "AUD", plugs: "I", voltage: 230),
        "NZ": Info(currency: "NZD", plugs: "I", voltage: 230), "IL": Info(currency: "ILS", plugs: "C, H", voltage: 230),
    ]

    static func info(_ code: String?) -> Info? { code.flatMap { data[$0.uppercased()] } }
}

enum Weather {
    struct Forecast {
        let temperature: Double
        let precipitationChance: Int?
        let code: Int
        var symbol: String {
            switch code {
            case 0: "sun.max.fill"
            case 1, 2: "cloud.sun.fill"
            case 3: "cloud.fill"
            case 45, 48: "cloud.fog.fill"
            case 51...67, 80...82: "cloud.rain.fill"
            case 71...77, 85, 86: "cloud.snow.fill"
            case 95...99: "cloud.bolt.rain.fill"
            default: "cloud"
            }
        }
    }

    /// Hourly forecast at a place and time (Open-Meteo, free, ~16 days ahead).
    static func forecast(lat: Double, lon: Double, at date: Date) async throws -> Forecast? {
        guard date.timeIntervalSinceNow < 15 * 86400, date.timeIntervalSinceNow > -3600 else { return nil }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "UTC")
        day.dateFormat = "yyyy-MM-dd"
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            URLQueryItem(name: "timezone", value: "UTC"),
            URLQueryItem(name: "start_date", value: day.string(from: date)),
            URLQueryItem(name: "end_date", value: day.string(from: date)),
        ]
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hourly = json["hourly"] as? [String: Any],
              let temps = hourly["temperature_2m"] as? [Double], !temps.isEmpty else { return nil }
        let hour = min(max(Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: date).hour ?? 12, 0), temps.count - 1)
        let rain = (hourly["precipitation_probability"] as? [Any])?[safe: hour] as? Int
        let code = (hourly["weather_code"] as? [Int])?[safe: hour] ?? 0
        return Forecast(temperature: temps[hour], precipitationChance: rain, code: code)
    }
}

enum FX {
    /// How many units of `currency` you get for 1 CHF (Coinbase public rates).
    static func perCHF(_ currency: String) async throws -> Double? {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "https://api.coinbase.com/v2/exchange-rates?currency=CHF")!)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rates = (json["data"] as? [String: Any])?["rates"] as? [String: Any] else { return nil }
        return rates[currency].flatMap { Double("\($0)") }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
