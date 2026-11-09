import Foundation

enum Category: String, Codable, CaseIterable, Identifiable {
    case lebensmittel, auswaerts, wohnen, mobilitaet, auto, abos, shopping, gesundheit, versicherung,
         freizeit, reisen, telefon, steuern, bargeld, einkommen, transfer, sonstiges
    var id: String { rawValue }

    var label: String {
        switch self {
        case .lebensmittel: "Lebensmittel"
        case .auswaerts: "Essen auswärts"
        case .wohnen: "Wohnen"
        case .mobilitaet: "ÖV & Taxi"
        case .auto: "Auto"
        case .abos: "Abos"
        case .shopping: "Shopping"
        case .gesundheit: "Gesundheit"
        case .versicherung: "Versicherungen"
        case .freizeit: "Freizeit"
        case .reisen: "Reisen"
        case .telefon: "Handy & Internet"
        case .steuern: "Steuern & Gebühren"
        case .bargeld: "Bargeld"
        case .einkommen: "Einkommen"
        case .transfer: "Umbuchung"
        case .sonstiges: "Sonstiges"
        }
    }

    var icon: String {
        switch self {
        case .lebensmittel: "cart"
        case .auswaerts: "fork.knife"
        case .wohnen: "house"
        case .mobilitaet: "tram"
        case .auto: "car"
        case .abos: "repeat"
        case .shopping: "bag"
        case .gesundheit: "cross.case"
        case .versicherung: "shield"
        case .freizeit: "gamecontroller"
        case .reisen: "airplane"
        case .telefon: "iphone"
        case .steuern: "building.columns"
        case .bargeld: "banknote"
        case .einkommen: "arrow.down.circle"
        case .transfer: "arrow.left.arrow.right"
        case .sonstiges: "questionmark.circle"
        }
    }

    /// Spending categories (excludes income and transfers)
    var isSpending: Bool { self != .einkommen && self != .transfer }
}

enum TxSource: String, Codable {
    case manual, applePay, bank, imported
    var label: String {
        switch self {
        case .manual: "Manuell"
        case .applePay: "Apple Pay"
        case .bank: "Bank-Import"
        case .imported: "Import"
        }
    }
}

struct Transaction: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    /// Negative = expense, positive = income
    var amount: Double
    var merchant: String
    var category: Category
    var account: String = ""
    var source: TxSource = .manual
    var note: String = ""
    /// Bank reference for de-duplication
    var reference: String? = nil
    /// Original amount and currency for foreign-currency payments (amount is then in CHF)
    var originalAmount: Double? = nil
    var originalCurrency: String? = nil
}

struct CategoryRule: Codable, Hashable, Identifiable {
    var id = UUID()
    var keyword: String
    var category: Category
}

struct BankAccount: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var iban: String = ""
    var balance: Double
    var updated: Date = Date()
}

enum AssetKind: String, Codable, CaseIterable, Identifiable {
    case bank, crypto, wallet, investment, pension, other, debt
    var id: String { rawValue }
    var label: String {
        switch self {
        case .bank: "Bankkonten"
        case .crypto: "Börsen"
        case .wallet: "Wallets (Ledger)"
        case .investment: "Depot / Wertschriften"
        case .pension: "Säule 3a / Vorsorge"
        case .other: "Sonstiges"
        case .debt: "Schulden"
        }
    }
}

struct ManualAsset: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var kind: AssetKind
    var value: Double
    var updated: Date = Date()
}

struct WalletAddress: Codable, Hashable, Identifiable {
    var id = UUID()
    var label: String
    var chain: Chain
    var address: String

    enum Chain: String, Codable, CaseIterable, Identifiable {
        case btc, eth, sol
        var id: String { rawValue }
        var symbol: String { rawValue.uppercased() }
        var name: String { ["btc": "Bitcoin", "eth": "Ethereum", "sol": "Solana"][rawValue] ?? rawValue }
    }
}

struct CryptoHolding: Codable, Hashable, Identifiable {
    var id: String { source + symbol }
    let source: String
    let symbol: String
    let amount: Double
    var priceCHF: Double?
    var valueCHF: Double { (priceCHF ?? 0) * amount }
}

struct NetWorthSnapshot: Codable, Hashable, Identifiable {
    var id: Date { date }
    let date: Date
    let total: Double
}
