import SwiftUI

@main
struct SaldoApp: App {
    @State private var store = FinanceStore.shared

    var body: some Scene {
        WindowGroup {
            LockGate { RootView() }
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task {
                    await Reminders.requestAuthorization()
                    await Reminders.scheduleSubscriptionReminders(store)
                }
        }
    }
}

struct ImportFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct RootView: View {
    @Environment(FinanceStore.self) private var store
    @State private var importFile: ImportFile?

    var body: some View {
        TabView {
            OverviewView().tabItem { Label("Übersicht", systemImage: "chart.pie") }
            TransactionsView().tabItem { Label("Ausgaben", systemImage: "list.bullet") }
            WealthView().tabItem { Label("Vermögen", systemImage: "building.columns") }
            SettingsView().tabItem { Label("Einstellungen", systemImage: "gearshape") }
        }
        .onOpenURL { url in if url.isFileURL { importFile = ImportFile(url: url) } }
        .sheet(item: $importFile) { file in BankImportView(url: file.url) }
    }
}

/// Shows the result of a bank statement import before saving it.
struct BankImportView: View {
    @Environment(FinanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var result: BankImport.Result?
    @State private var error: String?
    @State private var accountName = "TKB Privatkonto"
    @State private var done: String?

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.orange) }
                if let done { Label(done, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                if let r = result {
                    if let acc = r.account {
                        Section("Kontostand") {
                            TextField("Kontoname", text: $accountName)
                            LabeledContent("Saldo", value: Money.chf(acc.balance))
                        }
                    }
                    Section("\(r.transactions.count) Buchungen") {
                        ForEach(r.transactions.prefix(100)) { t in TransactionRow(tx: t) }
                    }
                }
            }
            .navigationTitle("Kontoauszug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schliessen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importieren") {
                        guard let r = result else { return }
                        let tagged = r.transactions.map { t -> Transaction in
                            var t = t
                            t.account = accountName
                            return t
                        }
                        let n = store.addMany(tagged)
                        if var acc = r.account {
                            acc.name = accountName
                            acc.updated = Date()
                            store.upsert(acc)
                            store.recordSnapshot()
                        }
                        done = "\(n) neue Buchungen übernommen (\(r.transactions.count - n) Duplikate übersprungen)."
                        result = nil
                    }
                    .disabled(result == nil)
                }
            }
            .task {
                do {
                    result = try BankImport.load(url, store: store)
                    if let acc = result?.account, !acc.iban.isEmpty,
                       let existing = store.accounts.first(where: { $0.iban == acc.iban }) {
                        accountName = existing.name
                    }
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }
}

struct TransactionRow: View {
    let tx: Transaction
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tx.category.icon)
                .frame(width: 34, height: 34)
                .background(Theme.card, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.merchant).lineLimit(1)
                Text("\(tx.category.label) · \(tx.date.formatted(date: .abbreviated, time: .omitted))\(tx.source == .applePay ? " · Apple Pay" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(Money.chf(tx.amount))
                    .monospacedDigit()
                    .foregroundStyle(tx.amount < 0 ? Color.primary : Theme.accent)
                if let o = tx.originalAmount, let c = tx.originalCurrency {
                    Text("\(c) \(String(format: "%.2f", o))").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
