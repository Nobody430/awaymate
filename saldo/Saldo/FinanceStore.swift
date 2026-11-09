import Foundation
import Observation

@MainActor
@Observable
final class FinanceStore {
    static let shared = FinanceStore()

    private struct Snapshot: Codable {
        var transactions: [Transaction]
        var rules: [CategoryRule]
        var budgets: [String: Double]
        var accounts: [BankAccount]
        var assets: [ManualAsset]
        var wallets: [WalletAddress]
        var holdings: [CryptoHolding]
        var history: [NetWorthSnapshot]
    }

    private(set) var transactions: [Transaction] = []
    private(set) var rules: [CategoryRule] = []
    private(set) var budgets: [Category: Double] = [:]
    private(set) var accounts: [BankAccount] = []
    private(set) var assets: [ManualAsset] = []
    private(set) var wallets: [WalletAddress] = []
    private(set) var holdings: [CryptoHolding] = []
    private(set) var history: [NetWorthSnapshot] = []
    var refreshing = false
    var lastError: String?

    private let file = "finance.json"

    init() {
        guard let s = Disk.load(Snapshot.self, file) else { return }
        transactions = s.transactions
        rules = s.rules
        budgets = Dictionary(uniqueKeysWithValues: s.budgets.compactMap { k, v in Category(rawValue: k).map { ($0, v) } })
        accounts = s.accounts
        assets = s.assets
        wallets = s.wallets
        holdings = s.holdings
        history = s.history
    }

    private func save() {
        Disk.save(Snapshot(transactions: transactions, rules: rules,
                           budgets: Dictionary(uniqueKeysWithValues: budgets.map { ($0.key.rawValue, $0.value) }),
                           accounts: accounts, assets: assets, wallets: wallets, holdings: holdings, history: history), file)
    }

    // MARK: Transactions

    func add(_ tx: Transaction) {
        let before = spending(in: tx.date)[tx.category] ?? 0
        transactions.append(tx)
        transactions.sort { $0.date > $1.date }
        save()
        checkBudget(tx.category, before: before, month: tx.date)
    }

    /// Notifies when a category crosses 80 % or 100 % of its monthly budget.
    private func checkBudget(_ c: Category, before: Double, month: Date) {
        guard let limit = budgets[c], limit > 0, Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month) else { return }
        let now = spending(in: month)[c] ?? 0
        for threshold in [1.0, 0.8] where before < limit * threshold && now >= limit * threshold {
            Reminders.post(title: threshold >= 1 ? "Budget überschritten: \(c.label)" : "80 % vom Budget: \(c.label)",
                           body: "\(Money.chf(now, decimals: 0)) von \(Money.chf(limit, decimals: 0)) diesen Monat ausgegeben.")
            break
        }
    }

    /// Adds many transactions, skipping duplicates. Returns how many were new.
    @discardableResult
    func addMany(_ list: [Transaction]) -> Int {
        var added = 0
        for tx in list where !isDuplicate(tx) {
            transactions.append(tx)
            added += 1
        }
        transactions.sort { $0.date > $1.date }
        save()
        return added
    }

    private func isDuplicate(_ tx: Transaction) -> Bool {
        transactions.contains { t in
            if let r = tx.reference, let r2 = t.reference, !r.isEmpty { return r == r2 }
            // Same day, same amount: an Apple Pay entry that later shows up in the bank export
            return abs(t.amount - tx.amount) < 0.005 && Calendar.current.isDate(t.date, inSameDayAs: tx.date)
                && (t.source == .applePay || tx.source == .applePay || t.merchant == tx.merchant)
        }
    }

    func update(_ tx: Transaction) {
        guard let i = transactions.firstIndex(where: { $0.id == tx.id }) else { return }
        transactions[i] = tx
        save()
    }

    func delete(_ ids: [UUID]) {
        transactions.removeAll { ids.contains($0.id) }
        save()
    }

    // MARK: Categorisation

    static let builtInRules: [(String, Category)] = [
        ("migros", .lebensmittel), ("coop", .lebensmittel), ("denner", .lebensmittel), ("lidl", .lebensmittel),
        ("aldi", .lebensmittel), ("volg", .lebensmittel), ("spar", .lebensmittel), ("manor food", .lebensmittel),
        ("bäckerei", .lebensmittel), ("baeckerei", .lebensmittel), ("k kiosk", .lebensmittel), ("avec", .lebensmittel),
        ("mcdonald", .auswaerts), ("burger king", .auswaerts), ("starbucks", .auswaerts), ("restaurant", .auswaerts),
        ("pizzeria", .auswaerts), ("cafe", .auswaerts), ("café", .auswaerts), ("bar ", .auswaerts), ("uber eats", .auswaerts),
        ("just eat", .auswaerts), ("smood", .auswaerts), ("kebab", .auswaerts), ("sushi", .auswaerts),
        ("sbb", .mobilitaet), ("zvv", .mobilitaet), ("bls", .mobilitaet), ("postauto", .mobilitaet), ("uber", .mobilitaet),
        ("free now", .mobilitaet), ("freenow", .mobilitaet), ("taxi", .mobilitaet), ("bolt", .mobilitaet),
        ("shell", .auto), ("bp ", .auto), ("avia", .auto), ("agrola", .auto), ("socar", .auto), ("tamoil", .auto),
        ("parking", .auto), ("parkhaus", .auto), ("tcs", .auto),
        ("netflix", .abos), ("spotify", .abos), ("apple.com/bill", .abos), ("itunes", .abos), ("disney", .abos),
        ("youtube", .abos), ("google", .abos), ("microsoft", .abos), ("openai", .abos), ("chatgpt", .abos),
        ("anthropic", .abos), ("claude.ai", .abos), ("telegram", .abos), ("grindr", .abos), ("tinder", .abos),
        ("adobe", .abos), ("mubi", .abos), ("amazon prime", .abos), ("fitness", .abos), ("gym", .abos),
        ("galaxus", .shopping), ("digitec", .shopping), ("zalando", .shopping), ("amazon", .shopping), ("ikea", .shopping),
        ("h&m", .shopping), ("zara", .shopping), ("manor", .shopping), ("interdiscount", .shopping), ("temu", .shopping),
        ("apotheke", .gesundheit), ("pharmacie", .gesundheit), ("arzt", .gesundheit), ("zahnarzt", .gesundheit),
        ("spital", .gesundheit), ("amavita", .gesundheit), ("sunstore", .gesundheit), ("drogerie", .gesundheit),
        ("css", .versicherung), ("helsana", .versicherung), ("sanitas", .versicherung), ("swica", .versicherung),
        ("visana", .versicherung), ("axa", .versicherung), ("mobiliar", .versicherung), ("zurich", .versicherung),
        ("allianz", .versicherung), ("generali", .versicherung), ("baloise", .versicherung), ("helvetia", .versicherung),
        ("swisscom", .telefon), ("sunrise", .telefon), ("salt", .telefon), ("wingo", .telefon), ("yallo", .telefon),
        ("miete", .wohnen), ("verwaltung", .wohnen), ("immobilien", .wohnen), ("ewz", .wohnen), ("strom", .wohnen),
        ("serafe", .steuern), ("steuer", .steuern), ("gebühr", .steuern), ("steueramt", .steuern),
        ("swiss", .reisen), ("easyjet", .reisen), ("edelweiss", .reisen), ("booking.com", .reisen), ("airbnb", .reisen),
        ("hotel", .reisen), ("lufthansa", .reisen),
        ("kino", .freizeit), ("pathé", .freizeit), ("ticketcorner", .freizeit), ("steam", .freizeit), ("playstation", .freizeit),
        ("bancomat", .bargeld), ("geldautomat", .bargeld), ("atm", .bargeld), ("bargeldbezug", .bargeld),
        ("lohn", .einkommen), ("salär", .einkommen), ("salaire", .einkommen), ("gehalt", .einkommen),
        ("twint an", .transfer), ("übertrag", .transfer), ("kontoübertrag", .transfer), ("kraken", .transfer),
    ]

    func categorize(_ merchant: String, amount: Double) -> Category {
        let m = merchant.lowercased()
        if let r = rules.first(where: { m.contains($0.keyword.lowercased()) }) { return r.category }
        if let r = Self.builtInRules.first(where: { m.contains($0.0) }) { return r.1 }
        return amount > 0 ? .einkommen : .sonstiges
    }

    /// Changes a transaction's category and optionally remembers it for this merchant.
    func recategorize(_ tx: Transaction, to category: Category, remember: Bool) {
        var t = tx
        t.category = category
        update(t)
        guard remember else { return }
        let key = Self.normalize(tx.merchant)
        guard !key.isEmpty else { return }
        rules.removeAll { $0.keyword.lowercased() == key }
        rules.append(CategoryRule(keyword: key, category: category))
        for i in transactions.indices where Self.normalize(transactions[i].merchant) == key {
            transactions[i].category = category
        }
        save()
    }

    func deleteRules(_ ids: [UUID]) {
        rules.removeAll { ids.contains($0.id) }
        save()
    }

    /// Lower-cased merchant without numbers / card suffixes, used for grouping.
    static func normalize(_ merchant: String) -> String {
        let lower = merchant.lowercased()
        let cleaned = lower.replacingOccurrences(of: "[0-9*#/\\-]+", with: " ", options: .regularExpression)
        return cleaned.split(separator: " ").prefix(3).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    // MARK: Budgets & analysis

    func setBudget(_ value: Double?, for c: Category) {
        budgets[c] = (value ?? 0) > 0 ? value : nil
        save()
    }

    func transactions(in month: Date) -> [Transaction] {
        let cal = Calendar.current
        return transactions.filter { cal.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    func spending(in month: Date) -> [Category: Double] {
        var result: [Category: Double] = [:]
        for t in transactions(in: month) where t.amount < 0 && t.category.isSpending {
            result[t.category, default: 0] += -t.amount
        }
        return result
    }

    func totalSpending(in month: Date) -> Double { spending(in: month).values.reduce(0, +) }

    func income(in month: Date) -> Double {
        transactions(in: month).filter { $0.amount > 0 && $0.category == .einkommen }.reduce(0) { $0 + $1.amount }
    }

    struct Recurring: Identifiable {
        var id: String { key }
        let key: String
        let name: String
        let monthly: Double
        let lastDate: Date
        let count: Int
        let category: Category
        let intervalDays: Double
        let lastAmount: Double
        var nextDate: Date { lastDate.addingTimeInterval(intervalDays * 86400) }
    }

    /// Detects subscriptions: same merchant, similar amount, roughly monthly (or yearly) interval.
    var recurring: [Recurring] {
        let groups = Dictionary(grouping: transactions.filter { $0.amount < 0 }) { Self.normalize($0.merchant) }
        var result: [Recurring] = []
        for (key, txs) in groups where txs.count >= 2 && !key.isEmpty {
            let sorted = txs.sorted { $0.date < $1.date }
            let gaps = zip(sorted, sorted.dropFirst()).map { $1.date.timeIntervalSince($0.date) / 86400 }
            let avgGap = gaps.reduce(0, +) / Double(gaps.count)
            let amounts = sorted.map { -$0.amount }
            let avg = amounts.reduce(0, +) / Double(amounts.count)
            let similar = amounts.allSatisfy { abs($0 - avg) <= max(2, avg * 0.15) }
            guard similar, let last = sorted.last else { continue }
            let monthly: Double
            if (25...35).contains(avgGap) { monthly = avg }
            else if (6...8).contains(avgGap) { monthly = avg * 52 / 12 }
            else if (350...380).contains(avgGap) { monthly = avg / 12 }
            else { continue }
            // still active? last charge not too long ago
            guard Date().timeIntervalSince(last.date) / 86400 < avgGap * 1.6 + 5 else { continue }
            result.append(Recurring(key: key, name: last.merchant, monthly: monthly, lastDate: last.date,
                                    count: sorted.count, category: last.category, intervalDays: avgGap, lastAmount: -last.amount))
        }
        return result.sorted { $0.monthly > $1.monthly }
    }

    // MARK: Wealth

    func upsert(_ a: BankAccount) {
        if let i = accounts.firstIndex(where: { $0.id == a.id || (!a.iban.isEmpty && $0.iban == a.iban) }) {
            var updated = a
            updated.id = accounts[i].id
            accounts[i] = updated
        } else { accounts.append(a) }
        save()
    }

    func deleteAccounts(_ ids: [UUID]) { accounts.removeAll { ids.contains($0.id) }; save() }

    func upsert(_ a: ManualAsset) {
        if let i = assets.firstIndex(where: { $0.id == a.id }) { assets[i] = a } else { assets.append(a) }
        save()
    }

    func deleteAssets(_ ids: [UUID]) { assets.removeAll { ids.contains($0.id) }; save() }

    func upsert(_ w: WalletAddress) {
        if let i = wallets.firstIndex(where: { $0.id == w.id }) { wallets[i] = w } else { wallets.append(w) }
        save()
    }

    func deleteWallets(_ ids: [UUID]) { wallets.removeAll { ids.contains($0.id) }; save() }

    var bankTotal: Double { accounts.reduce(0) { $0 + $1.balance } }
    var cryptoTotal: Double { holdings.reduce(0) { $0 + $1.valueCHF } }
    func manualTotal(_ kind: AssetKind) -> Double { assets.filter { $0.kind == kind }.reduce(0) { $0 + $1.value } }

    var netWorth: Double {
        bankTotal + cryptoTotal + AssetKind.allCases.filter { $0 != .debt }.reduce(0) { $0 + manualTotal($1) } - manualTotal(.debt)
    }

    /// Fetches exchange balances, wallet balances and CHF prices.
    func refreshCrypto() async {
        refreshing = true
        lastError = nil
        defer { refreshing = false }
        var list: [CryptoHolding] = []
        var errors: [String] = []

        if Kraken.isConfigured {
            do { list += try await Kraken.balances().map { CryptoHolding(source: "Kraken", symbol: $0.key, amount: $0.value) } }
            catch { errors.append("Kraken: \(error.localizedDescription)") }
        }
        for w in wallets {
            do {
                let amount = try await Chains.balance(w)
                list.append(CryptoHolding(source: w.label, symbol: w.chain.symbol, amount: amount))
            } catch { errors.append("\(w.label): \(error.localizedDescription)") }
        }
        list = list.filter { $0.amount > 0.0000001 }

        if !list.isEmpty {
            do {
                let prices = try await Prices.chf()
                list = list.map { h in
                    var h = h
                    h.priceCHF = h.symbol == "CHF" ? 1 : prices[h.symbol]
                    return h
                }
            } catch { errors.append("Kurse: \(error.localizedDescription)") }
        }
        holdings = list.sorted { $0.valueCHF > $1.valueCHF }
        recordSnapshot()
        if !errors.isEmpty { lastError = errors.joined(separator: "\n") }
    }

    func recordSnapshot() {
        let today = Calendar.current.startOfDay(for: Date())
        history.removeAll { Calendar.current.isDate($0.date, inSameDayAs: today) }
        history.append(NetWorthSnapshot(date: today, total: netWorth))
        history.sort { $0.date < $1.date }
        save()
    }

    // MARK: Export

    func exportCSV() -> URL? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        var csv = "Datum;Betrag;Händler;Kategorie;Konto;Quelle;Notiz\n"
        for t in transactions {
            let fields = [f.string(from: t.date), String(format: "%.2f", t.amount), t.merchant, t.category.label, t.account, t.source.label, t.note]
            csv += fields.map { $0.replacingOccurrences(of: ";", with: ",") }.joined(separator: ";") + "\n"
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "Saldo-Export.csv")
        return (try? csv.write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }

    func wipe() {
        transactions = []; rules = []; budgets = [:]; accounts = []; assets = []; wallets = []; holdings = []; history = []
        save()
    }
}
