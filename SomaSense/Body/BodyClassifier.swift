import Foundation

/// Names a point on the body from where it is, which way the skin faces, and the mesh's part tag.
/// A line-for-line port of classify() in the prototype; parity tests compare it with the JavaScript.
enum BodyClassifier {
    struct Place: Equatable { var label: String; var area: String }

    static func classify(p: [Double], n: [Double], tag: String) -> Place {
        let x = p[0], y = p[1], z = p[2], ax = abs(x)
        let S = x > 0 ? "Left" : "Right", s = S.lowercased()
        let f = n[2] > 0.55 ? "front" : n[2] < -0.55 ? "back" : "side"
        let outer = n[0] * x > 0
        func name(_ label: String, _ area: String) -> Place { Place(label: label, area: area) }
        let io = outer ? "Outer " : "Inner "
        let headTags = ["head", "ear", "nose", "eye", "mouth", "chin", "cheek", "forehead"]
        if headTags.contains(tag) {
            if ax > 16 && y > 29 && y < 51 && z > 4 && z < 22 { return name(S + " ear", "head") }
            if n[1] < -0.72 && y < 20 { return name("Top of head", "head") }
            if f == "back" || z < -1 { return name("Back of head", "head") }
            if f == "side" || (ax >= 13 && z < 30) {
                if y >= 33 && z < 8 { return name("Behind " + s + " ear", "head") }
                if y < 33 && z < 24 { return name("Above " + s + " ear", "head") }
                if y < 33 { return name(S + " temple", "head") }
                if y >= 48 { return name(S + " jaw", "head") }
                return name(S + " cheek", "head")
            }
            if y < 30 { return name("Forehead", "head") }
            if y < 38 && ax >= 4 { return name(S + " eye area", "head") }
            if ax < 5 && y < 48 { return name("Nose", "head") }
            if ax < 8 && y >= 48 && y < 57 { return name("Mouth", "head") }
            if ax < 11 && y >= 57 { return name("Chin", "head") }
            return name(S + (y >= 50 ? " jaw" : " cheek"), "head")
        }
        func neck() -> Place {
            name(f == "front" ? "Front of neck" : f == "back" ? "Back of neck" : S + " side of neck", "head")
        }
        func knee() -> Place {
            name(f == "back" ? "Back of " + s + " knee" : f == "side" ? io + s + " knee" : S + " kneecap", "legs")
        }
        func ankle() -> Place {
            name(f == "side" ? io + s + " ankle" : f == "back" ? S + " Achilles" : "Front of " + s + " ankle", "legs")
        }
        func hip() -> Place {
            if f == "back" { return name(S + " buttock", "torso") }
            if f == "front" { return name(ax < 14 ? "Groin" : S + " hip", "torso") }
            return name("Outer " + s + " hip", "torso")
        }
        switch tag {
        case "neck":
            return neck()
        case "shoulder":
            return name((f == "back" ? "Back of " + s : S) + " shoulder", "arms")
        case "upperarm":
            if y < 90 { return name((f == "back" ? "Back of " + s : S) + " shoulder", "arms") }
            return name(f == "front" ? "Front of " + s + " upper arm" : f == "back" ? "Back of " + s + " upper arm" : io + s + " upper arm", "arms")
        case "forearm":
            return name(f == "front" ? S + " forearm, palm side" : f == "back" ? S + " forearm, back" : io + s + " forearm", "arms")
        case "palm":
            if y < 212 { return name(S + " wrist", "arms") }
            return name(n[2] >= 0 ? S + " palm" : "Back of " + s + " hand", "arms")
        case "thumb": return name(S + " thumb", "arms")
        case "index": return name(S + " index finger", "arms")
        case "middle": return name(S + " middle finger", "arms")
        case "ring": return name(S + " ring finger", "arms")
        case "pinky": return name(S + " little finger", "arms")
        case "torso-upper":
            if y < 76 { return neck() }
            if f == "front" { return name(ax < 6 ? "Center of chest" : S + " chest", "torso") }
            if f == "back" { return name(ax < 6 ? "Upper spine" : S + " upper back", "torso") }
            return name(S + " ribs", "torso")
        case "torso-lower":
            if f == "front" { return name(ax < 6 && y > 165 && y < 190 ? "Around the navel" : S + " abdomen", "torso") }
            if f == "back" { return name(ax < 6 ? "Lower spine" : S + " lower back", "torso") }
            return name(S + " flank", "torso")
        case "hip":
            return hip()
        case "thigh":
            if y < 234 { return hip() }
            if f == "back" && y < 252 { return name(S + " buttock", "torso") }
            if y > 300 { return knee() }
            return name(f == "front" ? "Front of " + s + " thigh" : f == "back" ? "Back of " + s + " thigh" : io + s + " thigh", "legs")
        case "calf":
            if y < 325 { return knee() }
            if y > 405 { return ankle() }
            return name(f == "front" ? S + " shin" : f == "back" ? S + " calf" : io + s + " lower leg", "legs")
        case "foot":
            if n[1] > 0.6 { return name("Sole of " + s + " foot", "legs") }
            if z < 0 { return name(S + " heel", "legs") }
            if y < 412 { return ankle() }
            return name("Top of " + s + " foot", "legs")
        case "toe1": return name(S + " big toe", "legs")
        case "toe2": return name(S + " second toe", "legs")
        case "toe3": return name(S + " third toe", "legs")
        case "toe4": return name(S + " fourth toe", "legs")
        case "toe5": return name(S + " little toe", "legs")
        default:
            return name("Body", "torso")
        }
    }
}
