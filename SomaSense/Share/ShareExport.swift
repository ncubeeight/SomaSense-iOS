import UIKit

/// What one share sends: a subject, a plain-text body, a PDF and, for a month's log, a calendar picture.
struct SharePackage: Identifiable {
    let id = UUID()
    var heading: String
    var note: String
    var subject: String
    var text: String
    /// File names without an extension, e.g. "SomaSense-2026-11".
    var name: String
    var pdf: Data
    var calendar: Data?
    var previews: [UIImage]

    var pdfName: String { name + ".pdf" }
    var calendarName: String { name + "-calendar.png" }
}

/// Builds shared logs and reports, ported from sharePages, reportPages, shareText and reportText in the prototype.
/// Pages are laid out on a 1224 × 1584 canvas, as the prototype does, and drawn at half size onto US Letter pages,
/// so the PDF keeps real text instead of pictures of it.
@MainActor
enum ShareExport {
    static let W: CGFloat = 1224, H: CGFloat = 1584, M: CGFloat = 84
    static let bottom: CGFloat = H - 110
    static let ink = rgb(0x14282C), soft = rgb(0x4F6368), line = rgb(0xD3DCDC)
    static let fill = rgb(0x0B6169), track = rgb(0xE4EAEA)

    static func rgb(_ hex: Int) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    static func font(_ weight: Int, _ px: CGFloat) -> UIFont {
        .systemFont(ofSize: px, weight: weight >= 700 ? .bold : .regular)
    }

    // MARK: Drawing helpers

    enum Align { case left, center, right }

    static func width(_ s: String, _ f: UIFont) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: f]).width
    }

    /// Draws text with its baseline at y, as canvas fillText does.
    static func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ f: UIFont, _ color: UIColor, _ align: Align = .left) {
        let w = width(s, f)
        let left = align == .left ? x : align == .center ? x - w / 2 : x - w
        (s as NSString).draw(at: CGPoint(x: left, y: y - f.ascender), withAttributes: [.font: f, .foregroundColor: color])
    }

    static func wrap(_ s: String, _ f: UIFont, _ maxWidth: CGFloat) -> [String] {
        var out: [String] = []
        for para in s.components(separatedBy: .newlines) {
            var line = ""
            for word in para.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
                let tryLine = line.isEmpty ? word : line + " " + word
                if width(tryLine, f) <= maxWidth { line = tryLine; continue }
                if !line.isEmpty { out.append(line) }
                line = word
                // A single word wider than the page is broken across lines.
                while width(line, f) > maxWidth {
                    var n = line.count - 1
                    while n > 1 && width(String(line.prefix(n)), f) > maxWidth { n -= 1 }
                    out.append(String(line.prefix(n)))
                    line = String(line.dropFirst(n))
                }
            }
            out.append(line)
        }
        return out
    }

    static func roundRect(_ r: CGRect, _ radius: CGFloat, fill: UIColor?, stroke: UIColor? = nil, lineWidth: CGFloat = 2) {
        let p = UIBezierPath(roundedRect: r, cornerRadius: radius)
        if let fill { fill.setFill(); p.fill() }
        if let stroke { stroke.setStroke(); p.lineWidth = lineWidth; p.stroke() }
    }

    static func rect(_ r: CGRect, _ color: UIColor) {
        color.setFill()
        UIRectFill(r)
    }

    // MARK: Pages

    struct Block {
        var h: CGFloat
        var keep = false
        var draw: (CGFloat) -> Void
    }

    /// Lays blocks out on pages; a block marked keep stays on the same page as what follows it.
    static func layout(_ blocks: [Block]) -> [[(Block, CGFloat)]] {
        var pages: [[(Block, CGFloat)]] = [[]]
        var y = M
        for (i, b) in blocks.enumerated() {
            var need = b.h
            var k = i
            while k + 1 < blocks.count && blocks[k].keep { need += blocks[k + 1].h; k += 1 }
            if y + need > bottom && !pages[pages.count - 1].isEmpty { pages.append([]); y = M }
            pages[pages.count - 1].append((b, y))
            y += b.h
        }
        return pages
    }

    static func drawPage(_ items: [(Block, CGFloat)], _ n: Int, of count: Int) {
        rect(CGRect(x: 0, y: 0, width: W, height: H), .white)
        for (b, y) in items { b.draw(y) }
        text("Self-reported log created with SomaSense. Not a medical record or diagnosis.", M, H - 56, font(400, 20), soft)
        text("Page \(n + 1) of \(count)", W - M, H - 56, font(400, 20), soft, .right)
    }

    /// The PDF, at US Letter size, and a picture of each page for the preview.
    static func render(_ blocks: [Block], title: String) -> (pdf: Data, previews: [UIImage]) {
        let pages = layout(blocks)
        let size = CGSize(width: W / 2, height: H / 2)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "SomaSense"]
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size), format: format).pdfData { ctx in
            for (n, items) in pages.enumerated() {
                ctx.beginPage()
                ctx.cgContext.scaleBy(x: 0.5, y: 0.5)
                drawPage(items, n, of: pages.count)
            }
        }
        let imageFormat = UIGraphicsImageRendererFormat()
        imageFormat.scale = 1.5
        imageFormat.opaque = true
        let previews = pages.enumerated().map { n, items in
            UIGraphicsImageRenderer(size: size, format: imageFormat).image { ctx in
                ctx.cgContext.scaleBy(x: 0.5, y: 0.5)
                drawPage(items, n, of: pages.count)
            }
        }
        return (pdf, previews)
    }

    // MARK: Calendar cells

    static func calGridHeight(_ month: String, _ cellH: CGFloat) -> CGFloat {
        let lead = Day.weekday(month + "-01"), daysIn = Day.daysIn(month)
        return 50 + CGFloat((lead + daysIn + 6) / 7) * cellH
    }

    /// One day as it looks in the Calendar tab. A day outside the period is greyed out.
    static func drawDayCell(_ log: LogFile, _ x: CGFloat, _ top: CGFloat, _ cellW: CGFloat, _ cellH: CGFloat, _ key: String, _ label: String, out: Bool) {
        let dayList = out ? [] : log.reports.filter { $0.date == key }
        let mx = dayList.map(\.severity).max() ?? 0
        let free = !out && dayList.isEmpty && log.symptomFree.contains(key)
        let bg = free ? rgb(0x8EDB8F) : dayList.isEmpty ? .white : mx <= 3 ? rgb(0xD6ECEC) : mx <= 6 ? rgb(0x86C6C4) : fill
        roundRect(CGRect(x: x + 4, y: top + 4, width: cellW - 8, height: cellH - 8), 14, fill: bg, stroke: out ? rgb(0xE9EEEE) : line)
        let fg = out ? rgb(0xA5B4B5) : !dayList.isEmpty && mx > 6 ? .white : ink
        text(label, x + cellW / 2, top + cellH * 0.46, font(700, label.count > 2 ? 26 : 30), fg, .center)
        if !dayList.isEmpty { text(Words.plural(dayList.count, "report"), x + cellW / 2, top + cellH * 0.76, font(400, 21), fg, .center) }
        if free {
            let cx = x + cellW / 2, cy = top + cellH * 0.7
            let p = UIBezierPath()
            p.move(to: CGPoint(x: cx - 13, y: cy))
            p.addLine(to: CGPoint(x: cx - 4, y: cy + 9))
            p.addLine(to: CGPoint(x: cx + 13, y: cy - 9))
            p.lineWidth = 4
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            ink.setStroke()
            p.stroke()
        }
    }

    static func drawWeekdays(_ y: CGFloat) {
        let cellW = (W - 2 * M) / 7
        for (i, d) in ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].enumerated() {
            text(d, M + cellW * (CGFloat(i) + 0.5), y + 34, font(700, 24), soft, .center)
        }
    }

    /// A month as it looks in the Calendar tab.
    static func drawCalGrid(_ log: LogFile, _ y: CGFloat, _ month: String, _ cellH: CGFloat) {
        let lead = Day.weekday(month + "-01"), cellW = (W - 2 * M) / 7
        drawWeekdays(y)
        for d in 1...Day.daysIn(month) {
            let at = lead + d - 1
            drawDayCell(log, M + CGFloat(at % 7) * cellW, y + 50 + CGFloat(at / 7) * cellH, cellW, cellH,
                        month + "-" + String(format: "%02d", d), String(d), out: false)
        }
    }

    /// Whole weeks from the Sunday on or before `from`; the first of a month and the first cell name the month.
    static func weekStart(_ from: String) -> String { Day.adding(from, days: -Day.weekday(from)) }

    static func drawWeekGrid(_ log: LogFile, _ y: CGFloat, _ start: String, _ weeks: Int, _ cellH: CGFloat, from: String, to: String) {
        let cellW = (W - 2 * M) / 7
        drawWeekdays(y)
        for i in 0..<(weeks * 7) {
            let key = Day.adding(start, days: i), d = Int(key.suffix(2)) ?? 0
            let label = d == 1 || i == 0 ? Day.short(key) : String(d)
            drawDayCell(log, M + CGFloat(i % 7) * cellW, y + 50 + CGFloat(i / 7) * cellH, cellW, cellH, key, label, out: key < from || key > to)
        }
    }

    static func drawCalKey(_ y: CGFloat) {
        var x = M
        let f = font(400, 23)
        for (color, label) in [(UIColor.white, "No entry"), (rgb(0x8EDB8F), "No symptoms"), (rgb(0xD6ECEC), "Mild (1–3)"),
                               (rgb(0x86C6C4), "Moderate (4–6)"), (fill, "Severe (7–10)")] {
            roundRect(CGRect(x: x, y: y, width: 28, height: 28), 6, fill: color, stroke: line)
            text(label, x + 36, y + 22, f, soft)
            x += 36 + width(label, f) + 30
        }
    }

    // MARK: A month's log

    struct Entry { var date: String; var time: String; var report: Report? }

    static func entries(_ log: LogFile, month: String) -> [Entry] {
        var list = log.reports.filter { Day.month($0.date) == month }.map { Entry(date: $0.date, time: $0.time, report: $0) }
        for d in log.symptomFree where Day.month(d) == month && !log.reports.contains(where: { $0.date == d }) {
            list.append(Entry(date: d, time: "", report: nil))
        }
        // A stable sort, as JavaScript's sort is.
        return list.enumerated().sorted { a, b in
            let ka = a.element.date + a.element.time, kb = b.element.date + b.element.time
            return ka != kb ? ka < kb : a.offset < b.offset
        }.map(\.element)
    }

    static func summary(_ list: [Entry]) -> String {
        let reports = list.filter { $0.report != nil }
        let days = Set(reports.map(\.date)).count
        return Words.plural(reports.count, "report") + " on " + Words.plural(days, "day") + " · " + Words.plural(list.count - reports.count, "symptom-free day")
    }

    static func monthLog(_ log: LogFile, month: String) -> SharePackage {
        let title = Day.monthTitle(month)
        let list = entries(log, month: month)
        var blocks: [Block] = []
        func block(_ h: CGFloat, keep: Bool = false, _ draw: @escaping (CGFloat) -> Void) { blocks.append(Block(h: h, keep: keep, draw: draw)) }

        block(150) { y in
            text("SomaSense", M, y + 52, font(700, 52), ink)
            text("Symptom log · " + title, M, y + 100, font(400, 32), ink)
            text(summary(list), M, y + 140, font(400, 26), soft)
        }
        let cellH: CGFloat = 118, gridH = calGridHeight(month, cellH)
        block(gridH + 90) { y in
            drawCalGrid(log, y, month, cellH)
            drawCalKey(y + gridH + 22)
        }
        block(70, keep: true) { y in text("Entries", M, y + 50, font(700, 36), ink) }
        if list.isEmpty { block(50) { y in text("Nothing was logged this month.", M, y + 34, font(400, 28), soft) } }
        for x in list {
            let when = Day.long(x.date) + (x.report != nil ? " at " + Words.time(x.time) : "")
            block(12, keep: true) { y in rect(CGRect(x: M, y: y + 4, width: W - 2 * M, height: 2), line) }
            guard let r = x.report else {
                block(58) { y in
                    text(when, M, y + 36, font(700, 28), ink)
                    text("No symptoms", W - M, y + 36, font(700, 28), rgb(0x1F6B33), .right)
                }
                continue
            }
            block(48, keep: true) { y in text(when, M, y + 36, font(700, 28), ink) }
            for l in wrap(r.cats.joined(separator: ", "), font(700, 26), W - 2 * M) {
                block(36, keep: true) { y in text(l, M, y + 26, font(700, 26), fill) }
            }
            for row in Words.rows(r) {
                block(38, keep: true) { y in text(row.key, M, y + 30, font(700, 22), soft) }
                let lines = wrap(row.value, font(400, 26), W - 2 * M)
                for (n, l) in lines.enumerated() {
                    block(n == lines.count - 1 ? 44 : 34) { y in text(l, M, y + 26, font(400, 26), ink) }
                }
            }
        }

        // The heading and calendar on their own, as a picture.
        let head = blocks[0], grid = blocks[1]
        let pictureFormat = UIGraphicsImageRendererFormat()
        pictureFormat.scale = 1
        pictureFormat.opaque = true
        let picture = UIGraphicsImageRenderer(size: CGSize(width: W, height: M + head.h + grid.h), format: pictureFormat).image { _ in
            rect(CGRect(x: 0, y: 0, width: W, height: M + head.h + grid.h), .white)
            head.draw(M)
            grid.draw(M + head.h)
        }
        let out = render(blocks, title: "SomaSense symptom log: " + title)
        return SharePackage(
            heading: "Share this month’s log",
            note: "This sends everything logged this month. You choose the app and the recipient next.",
            subject: "SomaSense symptom log: " + title,
            text: monthText(list, title: title),
            name: "SomaSense-" + month,
            pdf: out.pdf, calendar: picture.pngData(), previews: out.previews)
    }

    static func monthText(_ list: [Entry], title: String) -> String {
        var lines = ["SomaSense symptom log: " + title, summary(list), "The calendar picture and a PDF of this log are attached.", ""]
        for x in list {
            guard let r = x.report else { lines += [Day.long(x.date) + ": No symptoms", ""]; continue }
            lines += [Day.long(x.date) + " at " + Words.time(x.time), r.cats.joined(separator: ", ")]
            lines += Words.rows(r).map { $0.key + ": " + $0.value }
            lines.append("")
        }
        let body = lines.joined(separator: "\n")
        return body.count > 20000 ? String(body.prefix(20000)) + "\n\nThe full log continues in the attached PDF." : body
    }

    // MARK: A frequency report

    static func report(_ log: LogFile, range: Int, today: String) -> SharePackage? {
        let data = ReportSummary(reports: log.reports, symptomFree: log.symptomFree, range: range, today: today)
        guard let top = data.groups.first?.list.count else { return nil }
        let width = W - 2 * M
        let period = Day.short(data.from) + " to " + Day.short(today) + ", " + String(today.prefix(4))
        var blocks: [Block] = []
        func block(_ h: CGFloat, keep: Bool = false, _ draw: @escaping (CGFloat) -> Void) { blocks.append(Block(h: h, keep: keep, draw: draw)) }
        func bar(_ y: CGFloat, _ pct: Double) {
            roundRect(CGRect(x: M, y: y, width: width, height: 12), 4, fill: track)
            if pct > 0 { roundRect(CGRect(x: M, y: y, width: max(8, width * pct), height: 12), 4, fill: fill) }
        }
        func row(_ y: CGFloat, _ left: String, _ right: String, _ pct: Double, _ f: UIFont) {
            text(left, M, y + 26, f, ink)
            text(right, W - M, y + 26, font(400, 24), ink, .right)
            bar(y + 38, pct)
        }

        block(150) { y in
            text("SomaSense", M, y + 52, font(700, 52), ink)
            text("Frequency report · Last \(range) days", M, y + 100, font(400, 32), ink)
            text(period, M, y + 140, font(400, 26), soft)
        }
        let tiles = [("\(data.inRange.count)", "Reports"), ("\(data.days)", "Days with symptoms"), ("\(data.freeDays)", "Symptom-free days"), (ReportSummary.mean(data.inRange), "Avg severity")]
        block(140) { y in
            let gap: CGFloat = 16, w = (width - 3 * gap) / 4
            for (i, t) in tiles.enumerated() {
                let x = M + CGFloat(i) * (w + gap)
                roundRect(CGRect(x: x, y: y + 8, width: w, height: 108), 12, fill: nil, stroke: line)
                text(t.0, x + 16, y + 62, font(700, 42), ink)
                text(t.1, x + 16, y + 98, font(400, 20), soft)
            }
        }
        // The period as a calendar, week by week; days around it are greyed out.
        let start = weekStart(data.from)
        let span = (Day.calendar.dateComponents([.day], from: Day.date(start), to: Day.date(today)).day ?? 0) + 1
        let weeks = (span + 6) / 7
        let calH: CGFloat = 104
        block(70, keep: true) { y in text("Calendar", M, y + 50, font(700, 36), ink) }
        // Up to nine weeks fit under the summary on the first page, and twelve on a page after that.
        var w = 0
        while w < weeks {
            let n = min(w > 0 ? 12 : 9, weeks - w), at = w
            block(50 + CGFloat(n) * calH + 12, keep: at + n >= weeks) { y in
                drawWeekGrid(log, y, Day.adding(start, days: at * 7), n, calH, from: data.from, to: today)
            }
            w += n
        }
        block(80) { y in drawCalKey(y + 12) }
        block(92, keep: true) { y in
            text("How often, by type", M, y + 40, font(700, 36), ink)
            text("A report with two types counts once in each.", M, y + 76, font(400, 23), soft)
        }
        for g in data.groups {
            block(66) { y in
                row(y, g.cat, Words.plural(g.list.count, "report") + " · avg severity " + ReportSummary.mean(g.list), Double(g.list.count) / Double(top), font(700, 26))
            }
        }
        for g in data.groups {
            let d = TypeDetail(list: g.list, range: range, from: data.from, today: today)
            block(26, keep: true) { _ in }
            block(12, keep: true) { y in rect(CGRect(x: M, y: y + 4, width: width, height: 2), line) }
            block(92, keep: true) { y in
                text(g.cat, M, y + 46, font(700, 36), ink)
                text(Words.plural(g.list.count, "report") + " in the last \(range) days", M, y + 82, font(400, 24), soft)
            }
            block(44, keep: true) { y in text("Over time (reports per " + (d.size == 1 ? "day" : "week") + ")", M, y + 32, font(700, 25), ink) }
            block(170) { y in
                let base = y + 124, gap: CGFloat = 8
                let bw = (width - CGFloat(d.buckets.count - 1) * gap) / CGFloat(d.buckets.count)
                for (i, b) in d.buckets.enumerated() where b.n > 0 {
                    let x = M + CGFloat(i) * (bw + gap), h = max(8, CGFloat(b.n) / CGFloat(d.maxBucket) * 90)
                    fill.setFill()
                    UIBezierPath(roundedRect: CGRect(x: x, y: base - h, width: bw, height: h), byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 4, height: 4)).fill()
                    text("\(b.n)", x + bw / 2, base - h - 6, font(400, 22), ink, .center)
                }
                rect(CGRect(x: M, y: base, width: width, height: 2), rgb(0xC4D0D0))
                text(Day.short(d.buckets[0].start), M, base + 30, font(400, 21), soft)
                text(Day.short(d.buckets[d.buckets.count - 1].end), W - M, base + 30, font(400, 21), soft, .right)
            }
            block(44, keep: true) { y in text("Where on the body", M, y + 32, font(700, 25), ink) }
            let most = Double(d.where_.first?.count ?? 1)
            for t in d.where_ { block(60) { y in row(y, t.label, "\(t.count)", Double(t.count) / most, font(400, 24)) } }
            block(44, keep: true) { y in text("Time of day", M, y + 32, font(700, 25), ink) }
            for p in d.parts { block(60) { y in row(y, p.label, "\(p.count)", Double(p.count) / Double(d.maxPart), font(400, 24)) } }
            if !d.context.isEmpty {
                block(44, keep: true) { y in text("Logged alongside", M, y + 32, font(700, 25), ink) }
                for l in wrap(d.context.map { $0.label + " (\($0.count))" }.joined(separator: ", "), font(400, 25), width) {
                    block(36) { y in text(l, M, y + 26, font(400, 25), ink) }
                }
            }
        }

        var lines = ["SomaSense frequency report: last \(range) days", period,
                     Words.plural(data.inRange.count, "report") + " on " + Words.plural(data.days, "day") + " · " + Words.plural(data.freeDays, "symptom-free day") + " · average severity " + ReportSummary.mean(data.inRange),
                     "The full report is in the attached PDF.", ""]
        lines += data.groups.map { $0.cat + ": " + Words.plural($0.list.count, "report") + ", average severity " + ReportSummary.mean($0.list) }

        let out = render(blocks, title: "SomaSense frequency report: last \(range) days")
        return SharePackage(
            heading: "Share this report",
            note: "This shares the summary for the last \(range) days. You choose the app and the recipient next.",
            subject: "SomaSense frequency report: last \(range) days",
            text: lines.joined(separator: "\n"),
            name: "SomaSense-report-\(range)-days-" + today,
            pdf: out.pdf, calendar: nil, previews: out.previews)
    }

    // MARK: Files

    /// Shared files wait here until the next share or until the data is deleted.
    static var directory: URL { FileManager.default.temporaryDirectory.appendingPathComponent("Share", isDirectory: true) }

    static func clearFiles() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Writes the package's files and returns them, calendar picture first. Nil if they couldn't be written.
    static func write(_ p: SharePackage) -> [URL]? {
        clearFiles()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var urls: [URL] = []
            if let png = p.calendar {
                let u = directory.appendingPathComponent(p.calendarName)
                try png.write(to: u, options: [.atomic, .completeFileProtection])
                urls.append(u)
            }
            let u = directory.appendingPathComponent(p.pdfName)
            try p.pdf.write(to: u, options: [.atomic, .completeFileProtection])
            urls.append(u)
            return urls
        } catch {
            return nil
        }
    }
}
