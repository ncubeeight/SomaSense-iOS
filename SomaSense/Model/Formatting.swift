import Foundation

/// Day keys ("yyyy-MM-dd") and the app's wording for dates, times and severity, as in the Android app.
/// Dates are shown in US English for now, matching Android.
enum Day {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()
    private static let locale = Locale(identifier: "en_US")

    static func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func date(_ key: String) -> Date {
        let p = key.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p.count > 2 ? p[2] : 1))!
    }

    static func adding(_ key: String, days: Int) -> String {
        Day.key(calendar.date(byAdding: .day, value: days, to: date(key))!)
    }

    static func today() -> String { key(Date()) }

    private static func format(_ key: String, _ template: String) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.calendar = calendar
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: date(key))
    }

    /// "Tue, Oct 27"
    static func long(_ key: String) -> String { format(key, "EEE MMM d") }
    /// "Oct 27"
    static func short(_ key: String) -> String { format(key, "MMM d") }
    /// "October 2026", from a "yyyy-MM" month key.
    static func monthTitle(_ month: String) -> String { format(month + "-01", "MMMM yyyy") }

    static func month(_ key: String) -> String { String(key.prefix(7)) }

    static func addingMonths(_ month: String, _ n: Int) -> String {
        Day.month(Day.key(calendar.date(byAdding: .month, value: n, to: date(month + "-01"))!))
    }

    static func daysIn(_ month: String) -> Int {
        calendar.range(of: .day, in: .month, for: date(month + "-01"))!.count
    }

    /// 0 for Sunday, as JavaScript's getDay.
    static func weekday(_ key: String) -> Int { calendar.component(.weekday, from: date(key)) - 1 }
}

enum Words {
    static func time(_ t: String) -> String {
        let p = t.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return t }
        let h = p[0] % 12 == 0 ? 12 : p[0] % 12
        return "\(h):" + String(format: "%02d", p[1]) + (p[0] < 12 ? " AM" : " PM")
    }

    static func partOfDay(_ t: String) -> String {
        let h = Int(t.split(separator: ":").first ?? "12") ?? 12
        if h >= 5 && h < 12 { return "Morning" }
        if h >= 12 && h < 17 { return "Afternoon" }
        if h >= 17 && h < 21 { return "Evening" }
        return "Night"
    }

    static func severity(_ n: Int) -> String {
        switch n {
        case 0: "none"
        case ...3: "mild"
        case ...6: "moderate"
        case ...9: "severe"
        default: "worst imaginable"
        }
    }

    static func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)" + (n == 1 ? "" : "s") }

    static func nowTime() -> String {
        let c = Day.calendar.dateComponents([.hour, .minute], from: Date())
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }

    /// The rows of a report's detail view, also used in shared logs.
    static func rows(_ r: Report) -> [(key: String, value: String)] {
        var rows: [(String, String)] = [
            ("Where", r.points.map(\.label).joined(separator: ", ")),
            ("Severity", "\(r.severity) out of 10 · \(severity(r.severity))" + (r.sevNote.isEmpty ? "" : ". " + r.sevNote))
        ]
        func add(_ k: String, _ v: String) { if !v.isEmpty { rows.append((k, v)) } }
        add("Description", r.desc)
        add("Medicines taken", r.meds.joined(separator: ", "))
        add("Physical activity", r.acts.joined(separator: ", "))
        add("Other sensations", r.senses.joined(separator: ", "))
        add("Concerns", r.concern)
        return rows
    }
}
