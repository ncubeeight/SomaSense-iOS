import Foundation
import PDFKit
import Testing
import UIKit
@testable import SomaSense

/// Checks what a share sends: the subject, the message text, the PDF and the calendar picture.
@MainActor
struct ShareTests {
    static func report(_ id: String, _ date: String, _ time: String, _ cats: [String], _ severity: Int, label: String, meds: [String] = [], desc: String = "") -> Report {
        Report(id: id, date: date, time: time, cats: cats, severity: severity,
               points: [BodyPoint(id: id + "p", p: [0, 0, 0], n: [0, 0, 1], label: label, area: "arms")],
               desc: desc, sevNote: "", meds: meds, acts: [], senses: [], concern: "")
    }

    static func sampleLog() -> LogFile {
        var log = LogFile()
        log.reports = [
            report("a", "2026-11-03", "08:15", ["Pain"], 4, label: "Left forearm, palm side", meds: ["Ibuprofen"], desc: "Dull ache after typing"),
            report("b", "2026-11-03", "19:40", ["Pain", "Swelling"], 7, label: "Left wrist, back of hand side"),
            report("c", "2026-11-10", "13:05", ["Rash / skin"], 2, label: "Right shin")
        ]
        log.symptomFree = ["2026-11-05", "2026-10-30"]
        return log
    }

    static func pdfText(_ data: Data) throws -> (pages: Int, text: String) {
        let doc = try #require(PDFDocument(data: data))
        return (doc.pageCount, doc.string ?? "")
    }

    @Test func monthLogHasEveryEntryInTheTextPdfAndPicture() throws {
        let p = ShareExport.monthLog(Self.sampleLog(), month: "2026-11")
        #expect(p.subject == "SomaSense symptom log: November 2026")
        #expect(p.name == "SomaSense-2026-11")
        #expect(p.text.hasPrefix("SomaSense symptom log: November 2026\n3 reports on 2 days · 1 symptom-free day\n"))
        #expect(p.text.contains("Tue, Nov 3 at 8:15 AM\nPain\nWhere: Left forearm, palm side\nSeverity: 4 out of 10 · moderate\nDescription: Dull ache after typing\nMedicines taken: Ibuprofen"))
        #expect(p.text.contains("Thu, Nov 5: No symptoms"))
        // October's symptom-free day isn't part of November's log.
        #expect(!p.text.contains("Oct 30"))

        let pdf = try Self.pdfText(p.pdf)
        #expect(pdf.pages >= 1)
        #expect(p.previews.count == pdf.pages)
        for s in ["Symptom log · November 2026", "Entries", "Left wrist, back of hand side", "Dull ache after typing", "No symptoms", "Page 1 of \(pdf.pages)"] {
            #expect(pdf.text.contains(s), "PDF is missing \(s)")
        }
        let page = try #require(PDFDocument(data: p.pdf)?.page(at: 0))
        #expect(page.bounds(for: .mediaBox).size == CGSize(width: 612, height: 792))

        let png = try #require(p.calendar)
        let picture = try #require(UIImage(data: png))
        #expect(picture.size.width == 1224)
    }

    @Test func reportCoversThePeriodAndNeedsReports() throws {
        let log = Self.sampleLog()
        let p = try #require(ShareExport.report(log, range: 30, today: "2026-11-12"))
        #expect(p.subject == "SomaSense frequency report: last 30 days")
        #expect(p.calendar == nil)
        #expect(p.text.contains("3 reports on 2 days · 2 symptom-free days · average severity 4.3"))
        #expect(p.text.contains("Pain: 2 reports, average severity 5.5"))
        let pdf = try Self.pdfText(p.pdf)
        for s in ["Frequency report · Last 30 days", "How often, by type", "Swelling", "Where on the body", "Time of day"] {
            #expect(pdf.text.contains(s), "PDF is missing \(s)")
        }
        // Nothing to report in a week with no entries.
        #expect(ShareExport.report(log, range: 7, today: "2026-12-31") == nil)
    }

    @Test func longLogsRunOntoMorePages() throws {
        var log = LogFile()
        log.reports = (1...30).map { d in
            Self.report("r\(d)", String(format: "2026-11-%02d", d), "09:00", ["Pain"], d % 10, label: "Lower back", desc: String(repeating: "A long description of the symptom. ", count: 6))
        }
        let p = ShareExport.monthLog(log, month: "2026-11")
        let pdf = try Self.pdfText(p.pdf)
        #expect(pdf.pages > 2)
        #expect(pdf.text.contains("Page \(pdf.pages) of \(pdf.pages)"))
    }

    @Test func filesAreWrittenAndCleared() throws {
        let p = ShareExport.monthLog(Self.sampleLog(), month: "2026-11")
        let urls = try #require(ShareExport.write(p))
        #expect(urls.map(\.lastPathComponent) == ["SomaSense-2026-11-calendar.png", "SomaSense-2026-11.pdf"])
        #expect(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        ShareExport.clearFiles()
        #expect(urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }
}
