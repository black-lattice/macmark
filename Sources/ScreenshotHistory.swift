import AppKit
import CryptoKit

final class ScreenshotHistory {
    struct Entry: Codable, Equatable {
        let id: UUID
        let date: Date
        let width: Int
        let height: Int
        let digest: String
    }
    static let limit = 20
    private let directory: URL
    private let defaults: UserDefaults
    private(set) var entries: [Entry] = []
    private(set) var loadError: String?
    var onChange: (() -> Void)?
    var isEnabled: Bool {
        get { defaults.object(forKey: "screenshotHistoryEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "screenshotHistoryEnabled"); onChange?() }
    }
    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacMark/History", isDirectory: true)
        let index = self.directory.appendingPathComponent("index.json")
        if FileManager.default.fileExists(atPath: index.path) {
            do {
                entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: index))
                    .filter { FileManager.default.fileExists(atPath: self.url(for: $0).path) }
                entries = Array(entries.prefix(Self.limit))
            } catch { loadError = "读取截图历史失败：\(error.localizedDescription)" }
        }
    }
    func url(for entry: Entry) -> URL { directory.appendingPathComponent(entry.id.uuidString + ".png") }
    func image(for entry: Entry) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url(for: entry) as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
    func thumbnail(for entry: Entry, maxSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url(for: entry) as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxSize
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
    }
    @discardableResult func add(_ image: CGImage, png existingPNG: Data? = nil) throws -> Entry? {
        guard isEnabled else { return nil }
        guard let png = existingPNG ?? Renderer.png(image) else { throw CocoaError(.fileWriteUnknown) }
        let digest = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        if entries.first?.digest == digest { return entries.first }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let entry = Entry(id: UUID(), date: Date(), width: image.width, height: image.height, digest: digest)
        try png.write(to: url(for: entry), options: .atomic)
        let updated = Array(([entry] + entries).prefix(Self.limit))
        do { try saveIndex(updated) }
        catch { try? FileManager.default.removeItem(at: url(for: entry)); throw error }
        let removed = entries.filter { !updated.contains($0) }
        entries = updated; loadError = nil
        for old in removed { try? FileManager.default.removeItem(at: url(for: old)) }
        onChange?()
        return entry
    }
    func clear() throws {
        // Only this app's dedicated history directory is removed; exported files are untouched.
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        entries = []; loadError = nil; onChange?()
    }
    private func saveIndex(_ value: [Entry]) throws {
        try JSONEncoder().encode(value).write(to: directory.appendingPathComponent("index.json"), options: .atomic)
    }
}
