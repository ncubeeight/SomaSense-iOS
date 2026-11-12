import Foundation
import Metal
import UIKit
import Observation

/// The app's state and actions, ported from the prototype's Component so the two behave the same.
@MainActor @Observable
final class AppModel {
    enum Tab: Hashable { case home, calendar, reports, settings }

    static let cats = ["Pain", "Rash / skin", "Swelling"]
    static let acts = ["Exercise", "Sitting", "Resting"]
    static let areas = [("all", "All areas"), ("head", "Head & neck"), ("arms", "Arms & hands"), ("torso", "Torso & hips"), ("legs", "Legs & feet")]

    struct Editing {
        var id: String
        var tab: Tab
        var homeDay: String
        var draft: ReportForm
    }

    // Stored log
    var log = LogFile()
    // Screen state
    var tab: Tab = .home
    var today = Day.today()
    var homeDay = Day.today()
    var selected: [BodyPoint] = []
    var form = ReportForm(time: Words.nowTime())
    var composing = false
    var editing: Editing?
    var detailId: String?
    var calMonth = Day.month(Day.today())
    var calDay = Day.today()
    var area = "all"
    var range = 30
    var drillCat: String?
    var toast: String?
    /// The log or report being shared, shown in a preview first.
    var share: SharePackage?

    let camera = BodyCamera()
    @ObservationIgnored let mesh = BodyMesh.loadBundled()
    @ObservationIgnored private var offsets: ShapeOffsets?
    /// The chosen body shape, and a count that goes up whenever the drawn body changes shape.
    var shape = BodyShape()
    var shapeVersion = 0
    /// False when the shape data couldn't be read, so Settings can say the options aren't available.
    var shapesAvailable: Bool { mesh != nil && offsets != nil }
    @ObservationIgnored private let store: LogStore
    @ObservationIgnored private var formDefault = ""
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init(store: LogStore = LogStore()) {
        self.store = store
        formDefault = form.time
        offsets = ShapeOffsets.loadBundled()
        let saved = store.loadShape()
        if !saved.isDefault { setShape(saved, save: false) }
        switch store.load() {
        case .loaded(let file): log = file
        case .empty: break
        case .setAside:
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                self.flash("Your saved log could not be read, so it was set aside.")
            }
        }
    }

    var reports: [Report] { log.reports }

    // MARK: Days

    /// Moves "today" on when the app comes back after midnight.
    func rollDate() {
        let now = Day.today()
        guard now != today else { return }
        if homeDay == today { homeDay = now }
        if calDay == today { calDay = now; calMonth = Day.month(now) }
        today = now
    }

    func dayPrev() { if editing == nil { homeDay = Day.adding(homeDay, days: -1) } }
    func dayNext() { if editing == nil && homeDay < today { homeDay = Day.adding(homeDay, days: 1) } }

    // MARK: Body map

    /// The angle the body is drawn and tapped at: the nearest 5°, as the prototype's frames are.
    var shownYaw: Double {
        let y = camera.yaw
        return (y < 0 ? -1 : 1) * (abs(y) / 5).rounded() * 5
    }

    func tap(sx: Double, sy: Double) {
        guard let mesh else { flash("Body data could not load."); return }
        guard let hit = mesh.cast(sx: sx, sy: sy, yaw: shownYaw) else { return }
        let place = BodyClassifier.classify(p: hit.p, n: hit.n, tag: hit.tag)
        let id = "p" + String(UUID().uuidString.prefix(7)).lowercased()
        // Named on the body as drawn, stored on the default body, as the prototype does.
        let stored = mesh.toBase(hit.p)
        selected.append(BodyPoint(id: id, p: stored.p, n: hit.n, label: place.label, area: place.area, v: stored.v))
    }

    /// Painting an area: press and hold, then drag. The brush stays the same size on screen at any zoom.
    @ObservationIgnored private(set) lazy var paint: BodyPaint? = mesh.map { BodyPaint(mesh: $0) }

    func paintBegin(sx: Double, sy: Double) {
        guard let paint else { return }
        paint.begin(yaw: shownYaw, r: BodyPaint.brush / Double(camera.zoom))
        paint.strokeTo(sx: sx, sy: sy)
    }

    func paintMove(sx: Double, sy: Double) { paint?.strokeTo(sx: sx, sy: sy) }

    func paintEnd(keep: Bool) {
        if let pt = paint?.end(keep: keep) { selected.append(pt) }
    }

    /// The finished areas among the marked points, and the stroke being drawn.
    func paintScene() -> (areas: [BodyPaint.Decal], live: BodyPaint.Live?) {
        guard let paint else { return ([], nil) }
        return (paint.decals(for: selected), paint.live)
    }

    func removePin(_ id: String) { selected.removeAll { $0.id == id } }

    func clearPins() {
        if let e = editing { endEdit(); detailId = e.id } else { selected = [] }
    }

    var selectedSummary: String {
        let nAreas = selected.filter(\.isArea).count, nPoints = selected.count - nAreas
        let counts = [nAreas > 0 ? Words.plural(nAreas, "area") : "", nPoints > 0 ? Words.plural(nPoints, "point") : ""].filter { !$0.isEmpty }
        return counts.joined(separator: " and ") + " marked · " + selected.map(\.label).joined(separator: ", ")
    }

    func startCompose() {
        if editing == nil && form.time == formDefault {
            formDefault = Words.nowTime()
            form.time = formDefault
        }
        composing = true
        camera.reset()
    }

    // MARK: Report form

    /// Choices for a form list: the starting set, then the person's own entries, most used first.
    func choices(_ kind: ChoiceKind, all: Bool = false) -> [String] {
        let start: [String] = kind == .acts ? AppModel.acts : kind == .cats ? AppModel.cats : []
        let hidden = all ? [] : hiddenList(kind)
        var count: [String: Int] = [:]
        var order: [String] = []
        for r in log.reports {
            for m in field(r, kind) {
                if count[m] == nil { order.append(m) }
                count[m, default: 0] += 1
            }
        }
        let own = order.filter { !start.contains($0) }.enumerated()
            .sorted { a, b in count[a.element]! != count[b.element]! ? count[a.element]! > count[b.element]! : a.offset < b.offset }
            .map(\.element)
        return (start + own).filter { !hidden.contains($0) }
    }

    /// The bubbles on the form: the list, then anything chosen that isn't on it.
    func formChips(_ kind: ChoiceKind) -> [String] {
        let list = choices(kind)
        return list + form.chosen(kind).filter { !list.contains($0) }
    }

    func toggle(_ kind: ChoiceKind, _ v: String) {
        var list = form.chosen(kind)
        if let i = list.firstIndex(of: v) { list.remove(at: i) } else { list.append(v) }
        form.setChosen(kind, list)
    }

    /// A typed entry becomes a chosen bubble when it's finished.
    func commitTyped(_ kind: ChoiceKind) {
        let typed = form.typed(kind).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !typed.isEmpty else { return }
        var list = form.chosen(kind)
        for v in typed where !list.contains(v) { list.append(v) }
        form.setChosen(kind, list)
        form.setTyped(kind, "")
    }

    /// Takes a choice off the list; past reports keep it.
    func hideChoice(_ kind: ChoiceKind, _ m: String) {
        let inReport = editing != nil && form.chosen(kind).contains(m)
        setHidden(kind, hiddenList(kind) + [m])
        form.setChosen(kind, form.chosen(kind).filter { $0 != m })
        save()
        flash(inReport ? "Removed from the list and from this report. Other reports keep it." : "Removed from the list. Past reports keep it.")
    }

    var saveHint: String? {
        if selected.isEmpty { return "Add at least one point on the body to save." }
        if form.cats.isEmpty && form.catOther.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Choose at least one symptom or sensation type to save."
        }
        return nil
    }

    func formBack() {
        if let e = editing { endEdit(); detailId = e.id } else { composing = false }
    }

    func saveReport() {
        guard saveHint == nil else { return }
        let f = form
        func extra(_ list: [String], _ other: String) -> [String] {
            let t = other.trimmingCharacters(in: .whitespaces)
            return t.isEmpty || list.contains(t) ? list : list + [t]
        }
        showAgain(f)
        if let e = editing {
            if let i = log.reports.firstIndex(where: { $0.id == e.id }) {
                var r = log.reports[i]
                r.time = f.time; r.cats = extra(f.cats, f.catOther); r.severity = f.severity; r.points = selected
                r.desc = f.desc; r.sevNote = f.sevNote; r.meds = extra(f.meds, f.medOther); r.acts = extra(f.acts, f.actOther)
                r.senses = extra(f.senses, f.senseOther); r.concern = f.concern
                log.reports[i] = r
            }
            save()
            endEdit()
            detailId = e.id
            flash("Report updated")
            return
        }
        let rep = Report(
            id: "n" + String(Int(Date().timeIntervalSince1970 * 1000)), date: homeDay, time: f.time, cats: extra(f.cats, f.catOther),
            severity: f.severity, points: selected, desc: f.desc, sevNote: f.sevNote, meds: extra(f.meds, f.medOther),
            acts: extra(f.acts, f.actOther), senses: extra(f.senses, f.senseOther), concern: f.concern)
        log.reports.insert(rep, at: 0)
        log.symptomFree.removeAll { $0 == rep.date }
        save()
        let nAreas = selected.filter(\.isArea).count, n = selected.count
        selected = []
        form = blankForm()
        composing = false
        tab = .home
        camera.reset()
        calDay = homeDay
        calMonth = Day.month(homeDay)
        let counts = [nAreas > 0 ? Words.plural(nAreas, "area") : "", n - nAreas > 0 ? Words.plural(n - nAreas, "point") : ""].filter { !$0.isEmpty }
        flash("Report saved with " + counts.joined(separator: " and "))
    }

    private func blankForm() -> ReportForm {
        formDefault = Words.nowTime()
        return ReportForm(time: formDefault)
    }

    func startEdit(_ r: Report) {
        editing = Editing(id: r.id, tab: tab, homeDay: homeDay, draft: form)
        detailId = nil
        composing = true
        tab = .home
        homeDay = r.date
        selected = r.points
        camera.reset()
        form = ReportForm(time: r.time, cats: r.cats, desc: r.desc, severity: max(1, r.severity), sevNote: r.sevNote,
                          meds: r.meds, acts: r.acts, senses: r.senses, concern: r.concern)
    }

    /// Leaving an edit puts back the screen it started from and any draft that was in progress.
    func endEdit() {
        guard let e = editing else { return }
        editing = nil
        selected = []
        form = e.draft
        composing = false
        tab = e.tab
        homeDay = e.homeDay
        camera.reset()
    }

    // MARK: Hidden choices

    private func field(_ r: Report, _ kind: ChoiceKind) -> [String] {
        switch kind {
        case .cats: r.cats
        case .meds: r.meds
        case .acts: r.acts
        case .senses: r.senses
        }
    }

    func hiddenList(_ kind: ChoiceKind) -> [String] {
        switch kind {
        case .cats: log.hiddenCats
        case .meds: log.hiddenMeds
        case .acts: log.hiddenActs
        case .senses: log.hiddenSenses
        }
    }

    private func setHidden(_ kind: ChoiceKind, _ list: [String]) {
        switch kind {
        case .cats: log.hiddenCats = list
        case .meds: log.hiddenMeds = list
        case .acts: log.hiddenActs = list
        case .senses: log.hiddenSenses = list
        }
    }

    /// Typing or choosing a removed choice again puts it back on the list.
    private func showAgain(_ f: ReportForm) {
        for kind in ChoiceKind.allCases {
            let typed = f.typed(kind).trimmingCharacters(in: .whitespaces), chosen = f.chosen(kind)
            setHidden(kind, hiddenList(kind).filter { $0 != typed && !chosen.contains($0) })
        }
    }

    // MARK: Calendar

    func toggleFree() {
        if log.symptomFree.contains(calDay) { log.symptomFree.removeAll { $0 == calDay } } else { log.symptomFree.append(calDay) }
        save()
    }

    var canMarkFree: Bool { calDay <= today && !log.reports.contains { $0.date == calDay } }

    // MARK: Detail

    var detailReport: Report? { log.reports.first { $0.id == detailId } }

    func deleteReport(_ id: String) {
        log.reports.removeAll { $0.id == id }
        save()
        detailId = nil
        flash("Report deleted")
    }

    // MARK: Settings

    // MARK: Body shape

    /// Reshapes the body. Values within 5 of the middle snap to the default, as the prototype's sliders do.
    func setShape(_ next: BodyShape, save: Bool = true) {
        var next = next
        if abs(next.g) < 6 { next.g = 0 }
        if abs(next.b) < 6 { next.b = 0 }
        guard let mesh, let offsets else { return }
        if next != shape || shapeVersion == 0 {
            mesh.apply(next, offsets: offsets)
            shape = next
            shapeVersion = mesh.shapeVersion
        }
        if save { store.saveShape(next) }
    }

    /// The calendar's small front and back figures, redrawn for a custom shape. Nil means use the bundled pictures.
    @ObservationIgnored private var thumbCache: (version: Int, front: UIImage, back: UIImage)?
    @ObservationIgnored private lazy var offscreen: BodyRenderer? = {
        guard let mesh, let device = MTLCreateSystemDefaultDevice() else { return nil }
        return BodyRenderer(device: device, mesh: mesh)
    }()

    func thumbnails() -> (front: UIImage, back: UIImage)? {
        if shape.isDefault { return nil }
        if let t = thumbCache, t.version == shapeVersion { return (t.front, t.back) }
        guard let r = offscreen, let f = r.image(width: 258, height: 474, yaw: 0), let b = r.image(width: 258, height: 474, yaw: 180) else { return nil }
        thumbCache = (shapeVersion, UIImage(cgImage: f), UIImage(cgImage: b))
        return (thumbCache!.front, thumbCache!.back)
    }

    /// A stored point placed on the body as currently shaped.
    func shown(_ p: BodyPoint) -> BodyPoint {
        guard let mesh else { return p }
        var q = p
        q.p = mesh.fromBase(p.p, v: p.v)
        return q
    }

    func deleteAll() {
        let gone = store.clear()
        log = LogFile()
        if !shape.isDefault { setShape(BodyShape(), save: false) }
        selected = []
        form = blankForm()
        composing = false
        detailId = nil
        editing = nil
        share = nil
        ShareExport.clearFiles()
        flash(gone ? "All stored data was deleted" : "Some stored data could not be deleted")
    }

    // MARK: Tabs

    func pick(_ t: Tab) {
        if editing != nil { endEdit() }
        tab = t
        camera.reset()
    }

    // MARK: Saving and messages

    private func save() {
        if !store.save(log) { flash("Your log could not be saved. Check your phone’s free space.") }
    }

    // MARK: Sharing

    /// Everything logged in the Calendar's month: a calendar picture, a PDF and a text list.
    func openShare() {
        share = ShareExport.monthLog(log, month: calMonth)
    }

    /// The Reports tab's period as a PDF and a text summary.
    func openReportShare() {
        guard let p = ShareExport.report(log, range: range, today: today) else {
            flash("There are no reports in this period to share.")
            return
        }
        share = p
    }

    func flash(_ msg: String) {
        toast = msg
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { self.toast = nil }
        }
    }
}
