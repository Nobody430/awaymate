import SwiftUI
import Charts

struct WealthView: View {
    @Environment(FinanceStore.self) private var store
    @State private var addingAsset = false
    @State private var addingWallet = false
    @State private var addingAccount = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nettovermögen").font(.caption).foregroundStyle(.secondary)
                        Text(Money.chf(store.netWorth, decimals: 0)).font(.system(size: 36, weight: .bold, design: .rounded))
                        if store.history.count >= 2 {
                            Chart(store.history) { s in
                                AreaMark(x: .value("Datum", s.date), y: .value("CHF", s.total))
                                    .foregroundStyle(Theme.accent.opacity(0.2))
                                LineMark(x: .value("Datum", s.date), y: .value("CHF", s.total))
                                    .foregroundStyle(Theme.accent)
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .frame(height: 140)
                        }
                    }
                    .padding(.vertical, 4)
                    pie
                }

                Section {
                    ForEach(store.accounts) { a in
                        NavigationLink { AccountEditor(account: a) } label: {
                            row(a.name, sub: "Stand \(a.updated.formatted(date: .abbreviated, time: .omitted))", value: a.balance)
                        }
                    }
                    .onDelete { store.deleteAccounts($0.map { store.accounts[$0].id }) }
                    Button { addingAccount = true } label: { Label("Konto hinzufügen", systemImage: "plus") }
                } header: {
                    HStack { Text("Bankkonten"); Spacer(); Text(Money.chf(store.bankTotal, decimals: 0)) }
                } footer: {
                    Text("Tipp: Kontoauszug (camt.053 oder CSV) aus dem E-Banking teilen → Saldo. Der Kontostand wird automatisch aktualisiert.")
                }

                Section {
                    if store.holdings.isEmpty {
                        Text(Kraken.isConfigured || !store.wallets.isEmpty ? "Zum Aktualisieren nach unten ziehen." : "Kraken-Key oder Wallet-Adresse hinzufügen.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.holdings) { h in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(h.symbol).font(.headline)
                                Text("\(h.amount.formatted(.number.precision(.significantDigits(1...6)))) · \(h.source)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(h.priceCHF == nil ? "–" : Money.chf(h.valueCHF)).monospacedDigit()
                                if let p = h.priceCHF, h.symbol != "CHF" {
                                    Text("@ \(Money.chf(p))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    ForEach(store.wallets) { w in
                        NavigationLink { WalletEditor(wallet: w) } label: {
                            Label("\(w.label) (\(w.chain.symbol))", systemImage: "key.horizontal")
                                .font(.subheadline)
                        }
                    }
                    .onDelete { store.deleteWallets($0.map { store.wallets[$0].id }) }
                    Button { addingWallet = true } label: { Label("Wallet-Adresse (Ledger) hinzufügen", systemImage: "plus") }
                    if let e = store.lastError { Text(e).font(.caption).foregroundStyle(.orange) }
                } header: {
                    HStack { Text("Krypto"); Spacer(); Text(Money.chf(store.cryptoTotal, decimals: 0)) }
                }

                ForEach(AssetKind.allCases.filter { ![.bank, .crypto, .wallet].contains($0) }) { kind in
                    let list = store.assets.filter { $0.kind == kind }
                    if !list.isEmpty {
                        Section {
                            ForEach(list) { a in
                                NavigationLink { AssetEditor(asset: a) } label: {
                                    row(a.name, sub: "Stand \(a.updated.formatted(date: .abbreviated, time: .omitted))", value: kind == .debt ? -a.value : a.value)
                                }
                            }
                            .onDelete { store.deleteAssets($0.map { list[$0].id }) }
                        } header: {
                            HStack { Text(kind.label); Spacer(); Text(Money.chf(store.manualTotal(kind), decimals: 0)) }
                        }
                    }
                }
                Section {
                    Button { addingAsset = true } label: { Label("Depot, 3a, Schulden … hinzufügen", systemImage: "plus") }
                }
            }
            .navigationTitle("Vermögen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if store.refreshing { ProgressView() } else {
                        Button { Task { await store.refreshCrypto() } } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
            .refreshable { await store.refreshCrypto() }
            .task { if !store.wallets.isEmpty || Kraken.isConfigured { await store.refreshCrypto() } }
            .sheet(isPresented: $addingAsset) { NavigationStack { AssetEditor(asset: nil) } }
            .sheet(isPresented: $addingWallet) { NavigationStack { WalletEditor(wallet: nil) } }
            .sheet(isPresented: $addingAccount) { NavigationStack { AccountEditor(account: nil) } }
        }
    }

    @ViewBuilder
    private var pie: some View {
        let parts: [(String, Double)] = [
            ("Bank", store.bankTotal), ("Krypto", store.cryptoTotal),
            ("Depot", store.manualTotal(.investment)), ("Vorsorge", store.manualTotal(.pension)), ("Sonstiges", store.manualTotal(.other)),
        ].filter { $0.1 > 0 }
        if parts.count > 1 {
            Chart(parts, id: \.0) { p in
                SectorMark(angle: .value("CHF", p.1), innerRadius: .ratio(0.55), angularInset: 1.5)
                    .foregroundStyle(by: .value("Art", p.0))
            }
            .frame(height: 170)
        }
    }

    private func row(_ title: String, sub: String, value: Double) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.chf(value)).monospacedDigit().foregroundStyle(value < 0 ? Theme.negative : .primary)
        }
    }
}

struct AccountEditor: View {
    @Environment(FinanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let account: BankAccount?
    @State private var name = "TKB Privatkonto"
    @State private var iban = ""
    @State private var balance: Double = 0

    var body: some View {
        Form {
            TextField("Name", text: $name)
            TextField("IBAN (optional)", text: $iban).textInputAutocapitalization(.characters)
            HStack {
                Text("Saldo CHF")
                TextField("0.00", value: $balance, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
        }
        .navigationTitle(account == nil ? "Neues Konto" : name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") {
                    var a = account ?? BankAccount(name: name, balance: balance)
                    a.name = name; a.iban = iban.replacingOccurrences(of: " ", with: ""); a.balance = balance; a.updated = Date()
                    store.upsert(a)
                    store.recordSnapshot()
                    dismiss()
                }
            }
        }
        .onAppear { if let a = account { name = a.name; iban = a.iban; balance = a.balance } }
    }
}

struct AssetEditor: View {
    @Environment(FinanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let asset: ManualAsset?
    @State private var name = ""
    @State private var kind: AssetKind = .investment
    @State private var value: Double = 0

    var body: some View {
        Form {
            TextField("Name (z.B. Säule 3a VIAC)", text: $name)
            Picker("Art", selection: $kind) {
                ForEach(AssetKind.allCases.filter { ![.bank, .crypto, .wallet].contains($0) }) { Text($0.label).tag($0) }
            }
            HStack {
                Text(kind == .debt ? "Schuld CHF" : "Wert CHF")
                TextField("0.00", value: $value, format: .number.precision(.fractionLength(2))).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
        }
        .navigationTitle(asset == nil ? "Neuer Posten" : name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") {
                    var a = asset ?? ManualAsset(name: name, kind: kind, value: value)
                    a.name = name; a.kind = kind; a.value = abs(value); a.updated = Date()
                    store.upsert(a)
                    store.recordSnapshot()
                    dismiss()
                }
                .disabled(name.isEmpty)
            }
        }
        .onAppear { if let a = asset { name = a.name; kind = a.kind; value = a.value } }
    }
}

struct WalletEditor: View {
    @Environment(FinanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let wallet: WalletAddress?
    @State private var label = "Ledger"
    @State private var chain: WalletAddress.Chain = .btc
    @State private var address = ""

    var body: some View {
        Form {
            Section {
                TextField("Bezeichnung", text: $label)
                Picker("Blockchain", selection: $chain) {
                    ForEach(WalletAddress.Chain.allCases) { Text($0.name).tag($0) }
                }
                TextField("Öffentliche Adresse", text: $address, axis: .vertical)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.footnote.monospaced())
                Button("Aus Zwischenablage einfügen") { address = UIPasteboard.general.string ?? address }
            } footer: {
                Text("Nur die öffentliche Empfangsadresse aus Ledger Live (Empfangen → Adresse kopieren). Niemals die 24 Wörter eingeben! Bei Bitcoin jede genutzte Adresse einzeln hinzufügen.")
            }
        }
        .navigationTitle(wallet == nil ? "Wallet hinzufügen" : label)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") {
                    var w = wallet ?? WalletAddress(label: label, chain: chain, address: address)
                    w.label = label; w.chain = chain; w.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.upsert(w)
                    Task { await store.refreshCrypto() }
                    dismiss()
                }
                .disabled(address.count < 20)
            }
        }
        .onAppear { if let w = wallet { label = w.label; chain = w.chain; address = w.address } }
    }
}
