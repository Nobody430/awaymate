import Foundation

/// Imports bank statements: ISO 20022 camt.052/053/054 (XML) – the Swiss standard export – or CSV.
@MainActor
enum BankImport {
    struct Result {
        var transactions: [Transaction] = []
        var account: BankAccount?
    }

    enum ImportError: LocalizedError {
        case unreadable, columns, empty
        var errorDescription: String? {
            switch self {
            case .unreadable: "Datei konnte nicht gelesen werden."
            case .columns: "Spalten nicht erkannt (Datum, Betrag/Belastung/Gutschrift, Text). Schick mir eine Beispieldatei (ohne echte Daten), dann passe ich den Import an."
            case .empty: "Keine Buchungen gefunden."
            }
        }
    }

    static func load(_ url: URL, store: FinanceStore) throws -> Result {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable }
        let head = String(decoding: data.prefix(600), as: UTF8.self)
        if head.contains("<?xml") || head.contains("<Document") {
            return try CamtParser(store: store).parse(data)
        }
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? String(data: data, encoding: .windowsCP1252) ?? ""
        return try parseCSV(text, store: store)
    }

    // MARK: CSV

    static func parseCSV(_ text: String, store: FinanceStore) throws -> Result {
        let lines = text.replacingOccurrences(of: "\r", with: "").split(separator: "\n").map(String.init)
        // Swiss bank exports often have a few info lines before the actual header
        guard let headerIndex = lines.firstIndex(where: { l in
            let low = l.lowercased()
            return (low.contains("datum") || low.contains("date")) &&
                (low.contains("betrag") || low.contains("belastung") || low.contains("amount") || low.contains("gutschrift"))
        }) else { throw ImportError.columns }
        let headerLine = lines[headerIndex]
        let sep: Character = [";", ",", "\t"].max { a, b in headerLine.filter { $0 == a }.count < headerLine.filter { $0 == b }.count } ?? ";"

        func split(_ line: String) -> [String] {
            var out: [String] = [], cur = "", quoted = false
            for ch in line {
                if ch == "\"" { quoted.toggle() }
                else if ch == sep && !quoted { out.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" }
                else { cur.append(ch) }
            }
            out.append(cur.trimmingCharacters(in: .whitespaces))
            return out
        }

        let header = split(headerLine).map { $0.lowercased() }
        func col(_ keys: [String], not: [String] = []) -> Int? {
            header.firstIndex { h in keys.contains { h.contains($0) } && !not.contains { h.contains($0) } }
        }
        guard let dateCol = col(["buchungsdatum", "datum", "date"], not: ["valuta", "value"]) ?? col(["valuta"]) else { throw ImportError.columns }
        let amountCol = col(["betrag", "amount"], not: ["saldo", "balance"])
        let debitCol = col(["belastung", "debit", "lastschrift"])
        let creditCol = col(["gutschrift", "credit"])
        let textCol = col(["buchungstext", "text", "beschreibung", "description", "details", "mitteilung", "empfänger", "zahlungsempfänger"])
        let balanceCol = col(["saldo", "balance", "kontostand"])
        guard amountCol != nil || debitCol != nil || creditCol != nil else { throw ImportError.columns }

        var result = Result()
        var lastBalance: Double?
        for line in lines.dropFirst(headerIndex + 1) {
            let row = split(line)
            guard row.count > dateCol, let date = parseDate(row[dateCol]) else { continue }
            var amount: Double?
            if let c = amountCol, row.count > c { amount = number(row[c]) }
            if amount == nil {
                let debit = debitCol.flatMap { row.count > $0 ? number(row[$0]) : nil } ?? 0
                let credit = creditCol.flatMap { row.count > $0 ? number(row[$0]) : nil } ?? 0
                amount = credit - abs(debit)
            }
            guard let a = amount, a != 0 else { continue }
            let text = textCol.flatMap { row.count > $0 ? row[$0] : nil } ?? ""
            let merchant = cleanMerchant(text)
            result.transactions.append(Transaction(date: date, amount: a, merchant: merchant,
                                                   category: store.categorize(text, amount: a),
                                                   account: "Bank", source: .bank,
                                                   reference: "\(dateString(date))|\(a)|\(text.prefix(40))"))
            if lastBalance == nil, let b = balanceCol, row.count > b { lastBalance = number(row[b]) }
        }
        if result.transactions.isEmpty { throw ImportError.empty }
        if let lastBalance { result.account = BankAccount(name: "Bankkonto", balance: lastBalance) }
        return result
    }

    static func cleanMerchant(_ text: String) -> String {
        var t = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        for prefix in ["Einkauf ", "Zahlung ", "Debitkarte ", "Kartenzahlung ", "TWINT ", "Gutschrift ", "Belastung ", "E-Banking "] {
            if t.hasPrefix(prefix) { t = String(t.dropFirst(prefix.count)) }
        }
        return String(t.prefix(80)).trimmingCharacters(in: .whitespaces)
    }

    static func number(_ s: String) -> Double? {
        var t = s.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "CHF", with: "")
        if t.contains(",") && t.contains(".") { t = t.replacingOccurrences(of: ",", with: "") }
        else { t = t.replacingOccurrences(of: ",", with: ".") }
        return Double(t)
    }

    private static let dateFormatters: [DateFormatter] = ["dd.MM.yyyy", "dd.MM.yy", "yyyy-MM-dd", "dd/MM/yyyy", "yyyy-MM-dd'T'HH:mm:ss", "dd.MM.yyyy HH:mm"].map {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_CH")
        f.dateFormat = $0
        return f
    }

    static func parseDate(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        for f in dateFormatters { if let d = f.date(from: t) { return d } }
        return nil
    }

    static func dateString(_ d: Date) -> String { dateFormatters[2].string(from: d) }
}

/// Minimal ISO 20022 camt parser (Ntry = booking, Bal = balance).
@MainActor
final class CamtParser: NSObject, XMLParserDelegate {
    private let store: FinanceStore
    private var path: [String] = []
    private var text = ""
    private var result = BankImport.Result()

    // current entry
    private var amount: Double?
    private var isDebit = false
    private var date: Date?
    private var info: [String] = []
    private var party: String?
    private var ref: String?
    // balance
    private var balType = ""
    private var balAmount: Double?
    private var balDebit = false
    private var closingBalance: Double?
    private var iban = ""

    init(store: FinanceStore) { self.store = store }

    func parse(_ data: Data) throws -> BankImport.Result {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { throw BankImport.ImportError.unreadable }
        if result.transactions.isEmpty && closingBalance == nil { throw BankImport.ImportError.empty }
        if let closingBalance {
            result.account = BankAccount(name: iban.isEmpty ? "Bankkonto" : "Konto …\(iban.suffix(4))", iban: iban, balance: closingBalance)
        }
        return result
    }

    nonisolated func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                            qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        MainActor.assumeIsolated {
            path.append(elementName)
            text = ""
            if elementName == "Ntry" { amount = nil; isDebit = false; date = nil; info = []; party = nil; ref = nil }
            if elementName == "Bal" { balType = ""; balAmount = nil; balDebit = false }
        }
    }

    nonisolated func parser(_ parser: XMLParser, foundCharacters string: String) {
        MainActor.assumeIsolated { text += string }
    }

    nonisolated func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        MainActor.assumeIsolated {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let inEntry = path.contains("Ntry")
            let inBalance = path.contains("Bal")
            let inDetails = path.contains("NtryDtls")

            switch elementName {
            case "IBAN" where path.contains("Acct") && !inEntry: iban = value
            case "Amt" where inEntry && !inDetails: amount = Double(value)
            case "Amt" where inBalance: balAmount = Double(value)
            case "CdtDbtInd" where inEntry && !inDetails: isDebit = value == "DBIT"
            case "CdtDbtInd" where inBalance: balDebit = value == "DBIT"
            case "Cd" where inBalance && path.contains("Tp"): balType = value
            case "Dt" where inEntry && (path.contains("BookgDt") || path.contains("ValDt")):
                if date == nil || path.contains("BookgDt") { date = BankImport.parseDate(String(value.prefix(10))) }
            case "DtTm" where inEntry && path.contains("BookgDt"):
                date = BankImport.parseDate(String(value.prefix(10)))
            case "AddtlNtryInf", "AddtlTxInf", "Ustrd": if !value.isEmpty { info.append(value) }
            case "Nm" where inEntry && (path.contains("Cdtr") || path.contains("Dbtr")):
                // The counterparty: creditor for payments, debtor for incoming money
                if party == nil { party = value }
            case "AcctSvcrRef" where inEntry: if ref == nil { ref = value }
            case "Ntry": finishEntry()
            case "Bal": if ["CLBD", "CLAV"].contains(balType), let b = balAmount, closingBalance == nil || balType == "CLBD" {
                closingBalance = balDebit ? -b : b
            }
            default: break
            }
            path.removeLast()
            text = ""
        }
    }

    private func finishEntry() {
        guard let a = amount, let d = date else { return }
        let signed = isDebit ? -a : a
        let rawText = ([party].compactMap { $0 } + info).joined(separator: " ")
        let merchant = BankImport.cleanMerchant(party ?? info.first ?? "Buchung")
        result.transactions.append(Transaction(
            date: d, amount: signed, merchant: merchant,
            category: store.categorize(rawText, amount: signed),
            account: iban.isEmpty ? "Bank" : "…\(iban.suffix(4))", source: .bank,
            note: info.joined(separator: " · ").prefix(200).description,
            reference: ref ?? "\(BankImport.dateString(d))|\(signed)|\(rawText.prefix(40))"))
    }
}
