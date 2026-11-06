import Foundation

protocol ClockProvider { var now: Date { get } }
struct SystemClock: ClockProvider { var now: Date { Date() } }

enum StudyTime {
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.era, .year, .month, .day], from: date)
        return "\(c.era ?? 1)-\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
    static func endOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!.addingTimeInterval(-1)
    }
    static func atMinute(_ minute: Int, on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day)!
    }
    static func duration(_ seconds: Double) -> String {
        if seconds > 0 && seconds < 60 { return "\(Int(seconds))s" }
        let m = max(0, Int(seconds / 60))
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
    static func timer(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
    }
    static func resourceKey(_ string: String) -> String {
        guard var c = URLComponents(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) else { return string }
        c.scheme = c.scheme?.lowercased(); c.host = c.host?.lowercased()
        if c.path.isEmpty { c.path = "/" }
        if (c.scheme == "https" && c.port == 443) || (c.scheme == "http" && c.port == 80) { c.port = nil }
        return c.string ?? string
    }
    static func resource(title: String, url: String) throws -> ResourceLink {
        let clean = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = validURL(clean) else { throw StudyError.invalid("Enter a valid http or https link.") }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return ResourceLink(title: name.isEmpty ? (parsed.host ?? clean) : name, url: clean)
    }
    static func validURL(_ string: String) -> URL? {
        guard let url = URL(string: string), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}

enum SessionClock {
    static func elapsed(accumulated: Double, intervalStart: Date?, now: Date) -> Double {
        max(0, accumulated) + max(0, intervalStart.map { now.timeIntervalSince($0) } ?? 0)
    }
}
