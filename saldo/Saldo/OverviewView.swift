import SwiftUI
import Charts

struct OverviewView: View {
    @Environment(FinanceStore.self) private var store
    @State private var month = Date()

    private var previousMonth: Date { Calendar.current.date(byAdding: .month, value: -1, to: month) ?? month }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    monthPicker
                    summary
                    categoryChart
                    budgets
                    subscriptions
                    topMerchants
                }
                .padding()
            }
            .navigationTitle("Übersicht")
        }
    }

    private var monthPicker: some View {
        HStack {
            Button { month = previousMonth } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
            Spacer()
            Button { month = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month } label: { Image(systemName: "chevron.right") }
                .disabled(Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month))
        }
    }

    private var summary: some View {
        let spent = store.totalSpending(in: month)
        let before = store.totalSpending(in: previousMonth)
        let income = store.income(in: month)
        return VStack(spacing: 10) {
            Card {
                Text("Ausgaben").font(.caption).foregroundStyle(.secondary)
                Text(Money.chf(spent)).font(.system(size: 36, weight: .bold, design: .rounded))
                if before > 0 {
                    let diff = (spent - before) / before * 100
                    Text("\(diff >= 0 ? "+" : "")\(Int(diff)) % zum Vormonat (\(Money.chf(before, decimals: 0)))")
                        .font(.caption).foregroundStyle(diff > 0 ? Theme.negative : Theme.accent)
                }
            }
            HStack(spacing: 10) {
                StatTile(title: "Einnahmen", value: Money.short(income), color: Theme.accent)
                StatTile(title: "Gespart", value: Money.short(income - spent), color: income - spent >= 0 ? Theme.accent : Theme.negative)
            }
        }
    }

    private var categoryChart: some View {
        let data = store.spending(in: month).sorted { $0.value > $1.value }
        return Card {
            Text("Nach Kategorie").font(.caption).foregroundStyle(.secondary)
            if data.isEmpty {
                Text("Noch keine Ausgaben in diesem Monat.").foregroundStyle(.secondary)
            } else {
                Chart(data, id: \.key) { item in
                    SectorMark(angle: .value("Betrag", item.value), innerRadius: .ratio(0.6), angularInset: 1.5)
                        .foregroundStyle(by: .value("Kategorie", item.key.label))
                        .cornerRadius(4)
                }
                .chartLegend(.hidden)
                .frame(height: 200)
                ForEach(data, id: \.key) { item in
                    NavigationLink {
                        TransactionsView(filterCategory: item.key, filterMonth: month)
                    } label: {
                        HStack {
                            Image(systemName: item.key.icon).frame(width: 24)
                            Text(item.key.label)
                            Spacer()
                            Text(Money.chf(item.value)).monospacedDigit()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var budgets: some View {
        let spending = store.spending(in: month)
        let items = store.budgets.sorted { $0.key.label < $1.key.label }
        if !items.isEmpty {
            Card {
                Text("Budgets").font(.caption).foregroundStyle(.secondary)
                ForEach(items, id: \.key) { cat, limit in
                    let used = spending[cat] ?? 0
                    let ratio = min(used / max(limit, 1), 1)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(cat.label, systemImage: cat.icon)
                            Spacer()
                            Text("\(Money.chf(used, decimals: 0)) / \(Money.chf(limit, decimals: 0))").monospacedDigit()
                        }
                        .font(.subheadline)
                        ProgressView(value: ratio)
                            .tint(used > limit ? Theme.negative : used > limit * 0.85 ? .orange : Theme.accent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var subscriptions: some View {
        let subs = store.recurring
        if !subs.isEmpty {
            Card {
                HStack {
                    Text("Abos & wiederkehrend").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Money.chf(subs.reduce(0) { $0 + $1.monthly })) / Monat").font(.caption.weight(.semibold))
                }
                ForEach(subs) { s in
                    HStack {
                        Image(systemName: s.category.icon).frame(width: 24)
                        VStack(alignment: .leading) {
                            Text(s.name).lineLimit(1)
                            Text("zuletzt \(s.lastDate.formatted(date: .abbreviated, time: .omitted)) · \(s.count)×")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Money.chf(s.monthly)).monospacedDigit()
                    }
                    .font(.subheadline)
                }
                Text("Pro Jahr: \(Money.chf(subs.reduce(0) { $0 + $1.monthly } * 12, decimals: 0))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var topMerchants: some View {
        let groups = Dictionary(grouping: store.transactions(in: month).filter { $0.amount < 0 && $0.category.isSpending }) { $0.merchant }
            .map { (name: $0.key, total: $0.value.reduce(0) { $0 - $1.amount }, count: $0.value.count) }
            .sorted { $0.total > $1.total }
            .prefix(5)
        if !groups.isEmpty {
            Card {
                Text("Top-Händler").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(groups), id: \.name) { g in
                    HStack {
                        Text(g.name).lineLimit(1)
                        Spacer()
                        Text("\(g.count)×").foregroundStyle(.secondary)
                        Text(Money.chf(g.total)).monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}
