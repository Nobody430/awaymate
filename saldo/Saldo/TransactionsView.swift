import SwiftUI

struct TransactionsView: View {
    @Environment(FinanceStore.self) private var store
    var filterCategory: Category? = nil
    var filterMonth: Date? = nil
    @State private var search = ""
    @State private var adding = false
    @State private var editing: Transaction?

    private var items: [Transaction] {
        store.transactions.filter { t in
            (filterCategory == nil || t.category == filterCategory) &&
            (filterMonth == nil || Calendar.current.isDate(t.date, equalTo: filterMonth!, toGranularity: .month)) &&
            (search.isEmpty || t.merchant.localizedCaseInsensitiveContains(search) || t.note.localizedCaseInsensitiveContains(search))
        }
    }

    private var grouped: [(day: Date, txs: [Transaction])] {
        Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.date) }
            .map { ($0.key, $0.value) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        let content = List {
            if items.isEmpty {
                ContentUnavailableView("Keine Buchungen", systemImage: "tray",
                                       description: Text("Füge Ausgaben hinzu, richte Apple Pay ein oder importiere einen Kontoauszug."))
            }
            ForEach(grouped, id: \.day) { group in
                Section {
                    ForEach(group.txs) { t in
                        Button { editing = t } label: { TransactionRow(tx: t) }
                            .foregroundStyle(.primary)
                    }
                    .onDelete { idx in store.delete(idx.map { group.txs[$0].id }) }
                } header: {
                    HStack {
                        Text(group.day.formatted(date: .complete, time: .omitted))
                        Spacer()
                        Text(Money.chf(group.txs.filter { $0.category.isSpending }.reduce(0) { $0 + $1.amount }))
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Händler suchen")
        .navigationTitle(filterCategory?.label ?? "Ausgaben")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }
            }
        }
        .sheet(isPresented: $adding) { TransactionEditor(tx: nil) }
        .sheet(item: $editing) { t in TransactionEditor(tx: t) }

        if filterCategory == nil && filterMonth == nil {
            NavigationStack { content }
        } else {
            content
        }
    }
}

struct TransactionEditor: View {
    @Environment(FinanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tx: Transaction?

    @State private var amount: Double = 0
    @State private var isIncome = false
    @State private var merchant = ""
    @State private var category: Category = .sonstiges
    @State private var date = Date()
    @State private var note = ""
    @State private var remember = true
    @State private var categoryTouched = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Art", selection: $isIncome) {
                        Text("Ausgabe").tag(false)
                        Text("Einnahme").tag(true)
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text("CHF").foregroundStyle(.secondary)
                        TextField("0.00", value: $amount, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                    }
                    TextField("Händler / Beschreibung", text: $merchant)
                        .onChange(of: merchant) { _, m in
                            if !categoryTouched && tx == nil { category = store.categorize(m, amount: isIncome ? 1 : -1) }
                        }
                    Picker("Kategorie", selection: Binding(get: { category }, set: { category = $0; categoryTouched = true })) {
                        ForEach(Category.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                    }
                    if tx != nil && categoryTouched {
                        Toggle("Für diesen Händler merken", isOn: $remember)
                    }
                    DatePicker("Datum", selection: $date)
                    TextField("Notiz", text: $note, axis: .vertical)
                }
                if let tx {
                    Section {
                        LabeledContent("Quelle", value: tx.source.label)
                        if !tx.account.isEmpty { LabeledContent("Konto", value: tx.account) }
                        Button("Löschen", role: .destructive) {
                            store.delete([tx.id])
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(tx == nil ? "Neue Buchung" : "Buchung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { saveTx() }.disabled(amount <= 0 || merchant.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard let tx else { return }
                amount = abs(tx.amount)
                isIncome = tx.amount > 0
                merchant = tx.merchant
                category = tx.category
                date = tx.date
                note = tx.note
            }
        }
    }

    private func saveTx() {
        let signed = isIncome ? abs(amount) : -abs(amount)
        if var t = tx {
            let categoryChanged = t.category != category
            t.amount = signed
            t.merchant = merchant
            t.date = date
            t.note = note
            store.update(t)
            if categoryChanged { store.recategorize(t, to: category, remember: remember) }
        } else {
            store.add(Transaction(date: date, amount: signed, merchant: merchant, category: category, note: note))
        }
        dismiss()
    }
}
