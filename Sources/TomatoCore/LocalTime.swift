import Foundation

public enum LocalTime {
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public struct Piece {
        public let start: Date
        public let end: Date
        public let day: String
        public let timeZoneID: String
        public let seconds: Double
    }

    public static func split(start: Date, end: Date, effectiveSeconds: Double,
                             calendar: Calendar = .current) -> [Piece] {
        guard end > start, effectiveSeconds > 0 else { return [] }
        var cursor = start
        var result: [Piece] = []
        let wallSeconds = end.timeIntervalSince(start)
        while cursor < end {
            guard let day = calendar.dateInterval(of: .day, for: cursor) else { break }
            let boundary = min(end, day.end)
            let fraction = boundary.timeIntervalSince(cursor) / wallSeconds
            result.append(Piece(start: cursor, end: boundary,
                                day: dayKey(cursor, calendar: calendar),
                                timeZoneID: calendar.timeZone.identifier,
                                seconds: effectiveSeconds * fraction))
            cursor = boundary
        }
        return result
    }
}
