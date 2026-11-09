import AppIntents
import Foundation

/// Used by the Shortcuts "Transaction" automation (Wallet/Apple Pay) to log a payment automatically.
struct LogPaymentIntent: AppIntent {
    static var title: LocalizedStringResource = "Zahlung in Saldo erfassen"
    static var description = IntentDescription("Erfasst eine Kartenzahlung aus der Wallet als Ausgabe in Saldo.")
    static var openAppWhenRun = false

    @Parameter(title: "Betrag")
    var amount: String

    @Parameter(title: "Händler")
    var merchant: String

    @Parameter(title: "Karte", default: "")
    var card: String

    static var parameterSummary: some ParameterSummary {
        Summary("Zahlung von \(\.$amount) bei \(\.$merchant)") { \.$card }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let value = Self.parseAmount(amount), value != 0 else {
            return .result(dialog: "Betrag „\(amount)“ nicht erkannt.")
        }
        let store = FinanceStore.shared
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let currency = Self.currency(in: amount)
        var chf = abs(value)
        var note = ""
        if currency != "CHF" {
            if let prices = try? await Prices.chf(), let rate = prices[currency] {
                chf = (abs(value) * rate * 100).rounded() / 100
            } else {
                note = "Kurs nicht verfügbar – Betrag in \(currency) übernommen."
            }
        }
        var tx = Transaction(date: Date(), amount: -chf, merchant: name.isEmpty ? "Kartenzahlung" : name,
                             category: store.categorize(name, amount: -chf),
                             account: card, source: .applePay, note: note)
        if currency != "CHF" {
            tx.originalAmount = -abs(value)
            tx.originalCurrency = currency
        }
        store.add(tx)
        let spent = store.totalSpending(in: Date())
        let foreign = currency != "CHF" ? " (\(currency) \(String(format: "%.2f", abs(value))))" : ""
        return .result(dialog: "\(Money.chf(chf))\(foreign) bei \(tx.merchant) erfasst (\(tx.category.label)). Diesen Monat: \(Money.chf(spent)).")
    }

    /// Detects the currency in strings like "€12.50", "12,50 EUR", "US$ 9.99", "CHF 4.20".
    static func currency(in raw: String) -> String {
        let s = raw.uppercased()
        let codes = ["CHF", "EUR", "USD", "GBP", "ARS", "BRL", "CLP", "MXN", "JPY", "THB", "AED", "TRY", "SEK", "NOK", "DKK", "PLN", "CZK", "HUF", "CAD", "AUD"]
        if let c = codes.first(where: { s.contains($0) }) { return c }
        if s.contains("€") { return "EUR" }
        if s.contains("£") { return "GBP" }
        if s.contains("¥") { return "JPY" }
        if s.contains("$") { return "USD" }
        return "CHF"
    }

    /// Accepts "CHF 12.50", "12,50 CHF", "Fr. 1'234.00", "€ 9.99", …
    static func parseAmount(_ raw: String) -> Double? {
        let cleaned = raw.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
        guard let match = cleaned.range(of: "[0-9]+([.,][0-9]{1,2})?", options: .regularExpression) else { return nil }
        return Double(cleaned[match].replacingOccurrences(of: ",", with: "."))
    }
}

struct SaldoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogPaymentIntent(), phrases: ["Zahlung in \(.applicationName) erfassen"],
                    shortTitle: "Zahlung erfassen", systemImageName: "creditcard")
    }
}
