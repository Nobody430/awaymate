import Foundation
import ActivityKit
import WidgetKit

/// Live Activities (lock screen + Dynamic Island) and widget data.
@MainActor
enum LiveFlight {
    static var autoStart: Bool { UserDefaults.standard.object(forKey: "liveActivities") as? Bool ?? true }

    static func state(for f: Flight) -> FlightActivityAttributes.ContentState? {
        guard let dep = f.departure.best, let arr = f.arrival.best else { return nil }
        let status = f.normalizedStatus
        return FlightActivityAttributes.ContentState(
            status: status.label,
            departure: dep,
            arrival: arr,
            gate: f.isInAir || status == .arrived ? f.arrival.gate : f.departure.gate,
            terminal: f.isInAir || status == .arrived ? f.arrival.terminal : f.departure.terminal,
            delayMinutes: max(0, f.departure.delayMinutes ?? 0),
            belt: f.arrival.baggageBelt,
            inAir: f.isInAir
        )
    }

    static func activity(for f: Flight) -> Activity<FlightActivityAttributes>? {
        Activity<FlightActivityAttributes>.activities.first { $0.attributes.flightID == f.id.uuidString }
    }

    static func isRunning(_ f: Flight) -> Bool { activity(for: f) != nil }

    static func start(_ f: Flight) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, activity(for: f) == nil, let s = state(for: f) else { return }
        let attributes = FlightActivityAttributes(flightID: f.id.uuidString, flightNumber: f.number,
                                                  from: f.departure.code, to: f.arrival.code,
                                                  fromCity: f.departure.displayCity, toCity: f.arrival.displayCity)
        let content = ActivityContent(state: s, staleDate: s.arrival.addingTimeInterval(3600))
        // With a push server, the Live Activity is updated remotely in real time
        if PushClient.isConfigured, let activity = try? Activity.request(attributes: attributes, content: content, pushType: .token) {
            observe(activity)
        } else {
            _ = try? Activity.request(attributes: attributes, content: content)
        }
    }

    private static func observe(_ activity: Activity<FlightActivityAttributes>) {
        Task {
            for await token in activity.pushTokenUpdates {
                PushClient.setLiveToken(flightID: activity.attributes.flightID, token: token)
            }
        }
    }

    /// After an app restart: keep listening for token changes of running activities.
    static func observeExistingTokens() {
        for a in Activity<FlightActivityAttributes>.activities { observe(a) }
    }

    static func stop(_ f: Flight) async {
        guard let a = activity(for: f) else { return }
        await a.end(nil, dismissalPolicy: .immediate)
    }

    static func update(_ f: Flight) async {
        guard let a = activity(for: f), let s = state(for: f) else { return }
        let content = ActivityContent(state: s, staleDate: s.arrival.addingTimeInterval(3600))
        if f.normalizedStatus == .canceled || (f.normalizedStatus == .arrived && Date() > s.arrival.addingTimeInterval(45 * 60)) {
            await a.end(content, dismissalPolicy: .after(Date().addingTimeInterval(15 * 60)))
        } else {
            await a.update(content)
        }
    }

    /// Starts activities for flights departing within the next 4 hours.
    static func autoStartIfNeeded(_ flights: [Flight]) {
        guard autoStart else { return }
        let now = Date()
        for f in flights where !f.isPast && !f.normalizedStatus.isFinal {
            guard let dep = f.departure.best, dep.timeIntervalSince(now) < 4 * 3600,
                  (f.arrival.best ?? dep) > now else { continue }
            start(f)
        }
    }

    /// Publishes upcoming flights for the home screen widget.
    static func publish(_ flights: [Flight]) {
        let list = flights.filter { !$0.isPast }.prefix(5).compactMap { f -> WidgetFlight? in
            guard let dep = f.departure.best, let arr = f.arrival.best else { return nil }
            return WidgetFlight(id: f.id.uuidString, number: f.number, from: f.departure.code, to: f.arrival.code,
                                fromCity: f.departure.displayCity, toCity: f.arrival.displayCity,
                                departure: dep, arrival: arr, gate: f.departure.gate, terminal: f.departure.terminal,
                                status: f.normalizedStatus.label, delayMinutes: max(0, f.departure.delayMinutes ?? 0))
        }
        SharedStore.write(Array(list))
        WidgetCenter.shared.reloadAllTimelines()
    }
}
