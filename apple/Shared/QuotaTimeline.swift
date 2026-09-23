import Foundation
import WidgetKit

struct QuotaEntry: TimelineEntry {
    let date: Date
    let envelope: SnapshotEnvelope?
    let preferredBucket: String
    let unavailable: Bool
    let paired: Bool
}
struct QuotaProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry { QuotaEntry(date: .now, envelope: nil, preferredBucket: "", unavailable: false, paired: false) }
    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        let store = SharedStore()
        let connection = try? store.connection()
        completion(QuotaEntry(date: .now, envelope: connection.flatMap { store.cached(for: $0) }, preferredBucket: store.preferredBucket, unavailable: false, paired: connection != nil))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        Task {
            let store = SharedStore()
            var connection: Connection?
            var envelope: SnapshotEnvelope?
            var unavailable = false
            do {
                connection = try store.connection()
                if let connection {
                    envelope = store.cached(for: connection)
                    let fresh = try await APIClient().fetch(connection)
                    guard try store.connection() == connection else {
                        completion(Timeline(entries: [QuotaEntry(date: .now, envelope: nil, preferredBucket: "", unavailable: false, paired: false)], policy: .after(Date().addingTimeInterval(60))))
                        return
                    }
                    try store.save(fresh, for: connection)
                    envelope = store.cached(for: connection)
                }
            } catch { unavailable = true }
            if let expected = connection, (try? store.connection()) != expected {
                // A failed in-flight fetch must not re-publish a previous device's cache.
                connection = nil
                envelope = nil
            }
            let now = Date()
            // Future entries update state even when the next network refresh is delayed.
            let dates = [now] + (envelope?.snapshot.transitionDates(after: now) ?? [])
            let entries = dates.map { QuotaEntry(date: $0, envelope: envelope, preferredBucket: store.preferredBucket, unavailable: unavailable, paired: connection != nil) }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
        }
    }
}
