import WidgetKit
import SwiftUI
import ActivityKit

@main
struct SkylogWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextFlightWidget()
        FlightLiveActivity()
    }
}

private let accent = Color(red: 0.36, green: 0.62, blue: 1.0)

// MARK: - Home screen widget

struct NextFlightEntry: TimelineEntry {
    let date: Date
    let flight: WidgetFlight?
}

struct NextFlightProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextFlightEntry {
        NextFlightEntry(date: .now, flight: WidgetFlight(id: "x", number: "LX 1612", from: "ZRH", to: "LIS", fromCity: "Zürich",
                                                        toCity: "Lissabon", departure: .now.addingTimeInterval(7200),
                                                        arrival: .now.addingTimeInterval(18000), gate: "E42", terminal: "2",
                                                        status: "Planmässig", delayMinutes: 0))
    }

    func getSnapshot(in context: Context, completion: @escaping (NextFlightEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextFlightEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(30 * 60))))
    }

    private func entry() -> NextFlightEntry {
        let next = SharedStore.read().filter { $0.arrival > .now }.sorted { $0.departure < $1.departure }.first
        return NextFlightEntry(date: .now, flight: next)
    }
}

struct NextFlightView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextFlightEntry

    var body: some View {
        if let f = entry.flight {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(f.number).font(.caption.weight(.semibold))
                    Spacer()
                    Text(f.delayMinutes >= 15 ? "+\(f.delayMinutes) Min" : f.status)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(f.delayMinutes >= 15 ? .orange : accent)
                }
                HStack {
                    Text(f.from).font(.title2.bold())
                    Image(systemName: "airplane").font(.caption).foregroundStyle(.secondary)
                    Text(f.to).font(.title2.bold())
                }
                if f.departure > .now {
                    Text("Abflug in").font(.caption2).foregroundStyle(.secondary)
                    Text(f.departure, style: .relative).font(.headline.monospacedDigit())
                } else {
                    Text("Landung").font(.caption2).foregroundStyle(.secondary)
                    ProgressView(timerInterval: f.departure...max(f.departure.addingTimeInterval(60), f.arrival), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(accent)
                }
                if family != .systemSmall {
                    HStack {
                        Text("\(f.departure.formatted(date: .abbreviated, time: .shortened))")
                        Spacer()
                        if let t = f.terminal { Text("T\(t)") }
                        if let g = f.gate { Text("Gate \(g)").bold() }
                    }
                    .font(.caption)
                }
            }
            .containerBackground(for: .widget) { Color.black }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "airplane").font(.title)
                Text("Keine anstehenden Flüge").font(.caption).multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .containerBackground(for: .widget) { Color.black }
        }
    }
}

struct NextFlightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextFlight", provider: NextFlightProvider()) { entry in
            NextFlightView(entry: entry)
        }
        .configurationDisplayName("Nächster Flug")
        .description("Countdown, Gate und Status deines nächsten Flugs.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// MARK: - Live Activity

struct FlightLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightActivityAttributes.self) { context in
            LockScreenFlightView(context: context)
                .padding()
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        Text(context.attributes.from).font(.title2.bold())
                        Text(airportTime(context.state.departure, context.attributes.fromTZ)).font(.caption)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing) {
                        Text(context.attributes.to).font(.title2.bold())
                        Text(airportTime(context.state.arrival, context.attributes.toTZ)).font(.caption)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.flightNumber).font(.caption.bold())
                        Text(context.state.delayMinutes >= 5 ? "+\(context.state.delayMinutes) Min" : context.state.status)
                            .font(.caption2).foregroundStyle(context.state.delayMinutes >= 5 ? .orange : accent)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    FlightProgressRow(state: context.state)
                }
            } compactLeading: {
                HStack(spacing: 2) {
                    Image(systemName: "airplane").foregroundStyle(accent)
                    Text(context.attributes.to).font(.caption.bold())
                }
            } compactTrailing: {
                Countdown(target: context.state.inAir ? context.state.arrival : context.state.departure, overdue: "jetzt")
                    .monospacedDigit()
                    .frame(maxWidth: 52)
                    .font(.caption)
            } minimal: {
                Image(systemName: "airplane").foregroundStyle(accent)
            }
        }
    }
}

struct LockScreenFlightView: View {
    let context: ActivityViewContext<FlightActivityAttributes>

    var body: some View {
        let s = context.state
        VStack(spacing: 8) {
            HStack {
                Text(context.attributes.flightNumber).font(.subheadline.bold())
                Spacer()
                Text(s.delayMinutes >= 5 ? "Verspätet · +\(s.delayMinutes) Min" : s.status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(s.delayMinutes >= 15 ? .red : s.delayMinutes >= 5 ? .orange : accent)
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text(context.attributes.from).font(.title.bold())
                    Text(airportTime(s.departure, context.attributes.fromTZ)).font(.caption)
                }
                Spacer()
                VStack {
                    let target = s.inAir ? s.arrival : s.departure
                    if target > Date() {
                        Text(s.inAir ? "Landung in" : "Abflug in").font(.caption2).foregroundStyle(.secondary)
                        Countdown(target: target, overdue: "jetzt").font(.headline.monospacedDigit())
                    } else {
                        Text(s.inAir ? "Landung" : "Abflug").font(.caption2).foregroundStyle(.secondary)
                        Text(s.inAir ? "jeden Moment" : "steht an").font(.headline)
                    }
                }
                .multilineTextAlignment(.center)
                Spacer()
                VStack(alignment: .trailing) {
                    Text(context.attributes.to).font(.title.bold())
                    Text(airportTime(s.arrival, context.attributes.toTZ)).font(.caption)
                }
            }
            FlightProgressRow(state: s)
            if let line = s.inbound {
                HStack(spacing: 6) {
                    Image(systemName: "airplane.arrival")
                    Text(line).lineLimit(1)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(s.inboundWarn == true ? .orange : .secondary)
            }
        }
        .foregroundStyle(.white)
    }
}

struct FlightProgressRow: View {
    let state: FlightActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 4) {
            if state.inAir {
                ProgressView(timerInterval: state.departure...max(state.departure.addingTimeInterval(60), state.arrival), countsDown: false) {
                    EmptyView()
                } currentValueLabel: { EmptyView() }
                .tint(accent)
            }
            HStack {
                if let t = state.terminal { Text("Terminal \(t)") }
                if let g = state.gate { Text("Gate \(g)").bold() }
                Spacer()
                // airlines publish early guesses – show the belt only once airborne / landed
                if let b = state.belt, state.inAir || state.status == "Gelandet" { Label("Band \(b)", systemImage: "suitcase.rolling") }
            }
            .font(.caption)
        }
    }
}

/// Countdown that never builds an invalid time range (a past target crashed the Live Activity).
struct Countdown: View {
    let target: Date
    var overdue: String

    var body: some View {
        let now = Date()
        if target > now {
            Text(timerInterval: now...target, countsDown: true)
        } else {
            Text(overdue)
        }
    }
}
