import Foundation

/// The Reports tab's figures, ported from reportData and typeDetail in the prototype.
struct ReportSummary {
    struct Group {
        var cat: String
        var list: [Report]
    }

    var from: String
    var inRange: [Report]
    var days: Int
    var freeDays: Int
    var groups: [Group]

    init(reports: [Report], symptomFree: [String], range: Int, today: String) {
        from = Day.adding(today, days: -(range - 1))
        let from = from
        inRange = reports.filter { $0.date >= from && $0.date <= today }
        let inRange = inRange
        days = Set(inRange.map(\.date)).count
        freeDays = symptomFree.filter { d in d >= from && d <= today && !inRange.contains { $0.date == d } }.count
        var seen: [String] = []
        for r in inRange { for c in r.cats where !seen.contains(c) { seen.append(c) } }
        // A stable sort keeps first-seen order among equal counts, as JavaScript's sort does.
        groups = seen.map { c in Group(cat: c, list: inRange.filter { $0.cats.contains(c) }) }
            .enumerated()
            .sorted { a, b in a.element.list.count != b.element.list.count ? a.element.list.count > b.element.list.count : a.offset < b.offset }
            .map(\.element)
    }

    static func mean(_ list: [Report]) -> String {
        guard !list.isEmpty else { return "0" }
        let avg = Double(list.reduce(0) { $0 + $1.severity }) / Double(list.count)
        return String(format: "%.1f", avg)
    }
}

/// One symptom type's detail: reports over time, where on the body, time of day, and what was logged alongside.
struct TypeDetail {
    struct Bucket { var start: String; var end: String; var n: Int }
    struct Tally { var label: String; var count: Int }

    var size: Int
    var buckets: [Bucket]
    var parts: [Tally]
    var where_: [Tally]
    var context: [Tally]

    var maxBucket: Int { max(1, buckets.map(\.n).max() ?? 0) }
    var maxPart: Int { max(1, parts.map(\.count).max() ?? 0) }

    init(list: [Report], range: Int, from: String, today: String) {
        size = range == 7 ? 1 : 7
        let size = size
        let n = Int((Double(range) / Double(size)).rounded(.up))
        buckets = (0..<n).map { i in
            let end = Day.adding(today, days: -(n - 1 - i) * size)
            let startRaw = Day.adding(end, days: -(size - 1))
            let start = startRaw < from ? from : startRaw
            return Bucket(start: start, end: end, n: list.filter { $0.date >= start && $0.date <= end }.count)
        }
        parts = ["Morning", "Afternoon", "Evening", "Night"].map { p in
            Tally(label: p, count: list.filter { Words.partOfDay($0.time) == p }.count)
        }
        where_ = Array(TypeDetail.tally(list.flatMap { $0.points.map(\.label) }).prefix(5))
        context = Array(TypeDetail.tally(list.flatMap { $0.meds + $0.acts + $0.senses }).prefix(8))
    }

    /// Counts, most first; ties keep the order each label first appeared.
    static func tally(_ items: [String]) -> [Tally] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for v in items {
            if counts[v] == nil { order.append(v) }
            counts[v, default: 0] += 1
        }
        return order.enumerated()
            .sorted { a, b in counts[a.element]! != counts[b.element]! ? counts[a.element]! > counts[b.element]! : a.offset < b.offset }
            .map { Tally(label: $0.element, count: counts[$0.element]!) }
    }
}
