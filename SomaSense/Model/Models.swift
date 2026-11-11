import Foundation

/// One brush touch along a painted area, on the default body.
struct PathTouch: Codable, Hashable {
    var p: [Double]
    var n: [Double]
}

/// A marked point or painted area on the body. Positions are stored on the default body shape,
/// in the mesh's units: x is the person's left, y runs down from the top of the head, z faces forward.
struct BodyPoint: Codable, Hashable, Identifiable {
    var id: String
    var p: [Double]
    var n: [Double]
    var label: String
    var area: String
    /// Only areas have these: the touches laid along the stroke, the brush radius, and the side it was drawn from.
    var path: [PathTouch]?
    var r: Double?
    var yaw: Double?
    /// The vertex (index times three) the point moves with when the body is reshaped. Not saved;
    /// worked out again from the default body when missing, as the prototype does.
    var v: Int?

    var isArea: Bool { path != nil }

    enum CodingKeys: String, CodingKey { case id, p, n, label, area, path, r, yaw }
}

/// A saved report. Dates are "yyyy-MM-dd" and times "HH:mm" in local time, kept as text
/// so they never shift with time zones, as in the Android app.
struct Report: Codable, Hashable, Identifiable {
    var id: String
    var date: String
    var time: String
    var cats: [String]
    var severity: Int
    var points: [BodyPoint]
    var desc: String
    var sevNote: String
    var meds: [String]
    var acts: [String]
    var senses: [String]
    var concern: String
}

/// The whole log file. The format matches the Android app's somasense-log.json (version 1).
struct LogFile: Codable {
    var v: Int = 1
    var reports: [Report] = []
    var symptomFree: [String] = []
    var hiddenCats: [String] = []
    var hiddenMeds: [String] = []
    var hiddenActs: [String] = []
    var hiddenSenses: [String] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v) ?? 1
        reports = try c.decodeIfPresent([Report].self, forKey: .reports) ?? []
        symptomFree = try c.decodeIfPresent([String].self, forKey: .symptomFree) ?? []
        hiddenCats = try c.decodeIfPresent([String].self, forKey: .hiddenCats) ?? []
        hiddenMeds = try c.decodeIfPresent([String].self, forKey: .hiddenMeds) ?? []
        hiddenActs = try c.decodeIfPresent([String].self, forKey: .hiddenActs) ?? []
        hiddenSenses = try c.decodeIfPresent([String].self, forKey: .hiddenSenses) ?? []
    }
}

/// The lists on the report form whose choices can be hidden.
enum ChoiceKind: CaseIterable {
    case cats, meds, acts, senses
}

/// The report being written or edited.
struct ReportForm: Equatable {
    var time: String
    var cats: [String] = []
    var catOther = ""
    var desc = ""
    var severity = 1
    var sevNote = ""
    var meds: [String] = []
    var medOther = ""
    var acts: [String] = []
    var actOther = ""
    var senses: [String] = []
    var senseOther = ""
    var concern = ""

    func chosen(_ kind: ChoiceKind) -> [String] {
        switch kind {
        case .cats: cats
        case .meds: meds
        case .acts: acts
        case .senses: senses
        }
    }

    mutating func setChosen(_ kind: ChoiceKind, _ list: [String]) {
        switch kind {
        case .cats: cats = list
        case .meds: meds = list
        case .acts: acts = list
        case .senses: senses = list
        }
    }

    func typed(_ kind: ChoiceKind) -> String {
        switch kind {
        case .cats: catOther
        case .meds: medOther
        case .acts: actOther
        case .senses: senseOther
        }
    }

    mutating func setTyped(_ kind: ChoiceKind, _ text: String) {
        switch kind {
        case .cats: catOther = text
        case .meds: medOther = text
        case .acts: actOther = text
        case .senses: senseOther = text
        }
    }
}
