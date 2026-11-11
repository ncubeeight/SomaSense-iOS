import Foundation

/// Keeps the log in one JSON file in the app's private storage, protected while the phone is locked
/// and left out of iCloud and computer backups, matching the Android app's privacy promises.
struct LogStore {
    enum LoadResult {
        case loaded(LogFile)
        case empty
        /// The file couldn't be read, so it was set aside instead of being overwritten.
        case setAside
    }

    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = support.appendingPathComponent("SomaSense", isDirectory: true)
        }
    }

    var fileURL: URL { directory.appendingPathComponent("somasense-log.json") }
    var shapeURL: URL { directory.appendingPathComponent("body-shape.json") }

    /// The chosen body shape, kept beside the log so it gets the same protection and is deleted with it.
    func loadShape() -> BodyShape {
        guard let data = try? Data(contentsOf: shapeURL), let shape = try? JSONDecoder().decode(BodyShape.self, from: data) else { return BodyShape() }
        return shape
    }

    @discardableResult
    func saveShape(_ shape: BodyShape) -> Bool {
        do {
            try prepareDirectory()
            try JSONEncoder().encode(shape).write(to: shapeURL, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            return false
        }
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var dir = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try dir.setResourceValues(values)
    }

    func load() -> LoadResult {
        guard let data = try? Data(contentsOf: fileURL) else { return .empty }
        if data.isEmpty { return .empty }
        do {
            return .loaded(try JSONDecoder().decode(LogFile.self, from: data))
        } catch {
            let stamp = Int(Date().timeIntervalSince1970 * 1000)
            let aside = directory.appendingPathComponent("somasense-log-unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            return .setAside
        }
    }

    /// Writes the whole log atomically. Returns false if it couldn't be saved.
    @discardableResult
    func save(_ log: LogFile) -> Bool {
        do {
            try prepareDirectory()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(log)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            return false
        }
    }

    /// Removes the log, any set-aside copies and the body shape. Returns false if anything was left behind.
    func clear() -> Bool {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return true }
        var gone = true
        for name in names where name.hasPrefix("somasense-log") || name == "body-shape.json" {
            do { try fm.removeItem(at: directory.appendingPathComponent(name)) } catch { gone = false }
        }
        return gone
    }
}
