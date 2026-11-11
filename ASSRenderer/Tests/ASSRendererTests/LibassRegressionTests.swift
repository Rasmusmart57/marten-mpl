import XCTest
import CoreGraphics
import ImageIO
@testable import ASSRenderer

/// libass's own regression and crash tests (github.com/libass/libass-tests), run through Marten's path: the script split as a player
/// hands it over (the header, then each event in Matroska's shape), drawn by `ASSTrackRenderer` and put together by its own
/// `compose`, then measured against libass's pictures the way libass's `compare` tool measures them (compare/compare.c: the
/// pieces over black, the error per pixel against the picture's own edges, under 4 passing, as its default pass level 2 allows).
///
/// Fetched, not kept in the repo: `Scripts/fetch-libass-tests.sh`. Skipped when it is not there.
final class LibassRegressionTests: XCTestCase {
    private var suite: URL {
        get throws {
            let path = ProcessInfo.processInfo.environment["LIBASS_TESTS"]
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/MartenASS/libass-tests").path
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.appendingPathComponent("regression").path) else {
                throw XCTSkip("libass-tests not fetched: Vendor/ASSRenderer/Scripts/fetch-libass-tests.sh")
            }
            return url
        }
    }

    func testEveryRegressionPictureIsDrawnAsLibassDrawsIt() throws {
        let root = try suite.appendingPathComponent("regression")
        let fonts = try Self.fonts(in: root.appendingPathComponent(".fonts"))
        var results: [String] = []
        var failures: [String] = []
        for group in try Self.children(of: root) where !group.lastPathComponent.hasPrefix(".") && group.hasDirectoryPath {
            let scale = Self.scale(in: group)
            let groupFonts = fonts + (try Self.fonts(in: group))
            for script in try Self.children(of: group) where script.pathExtension == "ass" {
                let name = script.deletingPathExtension().lastPathComponent
                guard let split = try Self.split(script) else { results.append("\(name): not in Matroska's shape, skipped"); continue }
                for picture in try Self.children(of: group) where picture.pathExtension == "png" {
                    let stem = picture.deletingPathExtension().lastPathComponent
                    guard stem.hasPrefix(name + "-"), let ms = Int(stem.dropFirst(name.count + 1)) else { continue }
                    if Self.leftOut.contains(group.lastPathComponent + "/" + name) { continue }
                    let error = try Self.error(split: split, fonts: groupFonts, reference: picture, ms: ms, scale: scale)
                    results.append(String(format: "%@ %d: %.3f", name, ms, error))
                    if error >= 4 { failures.append(String(format: "%@ at %d ms: %.3f", group.lastPathComponent + "/" + name, ms, error)) }
                }
            }
        }
        print(results.joined(separator: "\n"))
        XCTAssertGreaterThan(results.count, 50, "the suite's pictures were found")
        XCTAssertEqual(failures, [], "drawn unlike libass's own pictures")
    }

    /// A symbol font whose first character is 0x0000 draws nothing here: libass-tests' README says its non-Unicode font tests rely
    /// on the platform's iconv and its conversions (its `ART_REG_SKIP`), and Apple's iconv is not the one its pictures were made with.
    /// The suite's other non-Unicode fonts (Shift JIS, Big5, the Arabic ones, 0xF000) pass.
    static let leftOut: Set<String> = ["font_nonunicode/symbol-first-char-0x0000"]

    /// The scripts that once crashed libass, drawn at each event's start and middle, as libass's fuzz harness does: none may crash
    /// Marten's own code around it (the picture's bounds, a mask outside the frame).
    func testTheCrashScriptsDrawWithoutFailing() throws {
        let root = try suite.appendingPathComponent("crash")
        for script in try Self.children(of: root) where script.pathExtension == "ass" {
            guard let split = try Self.split(script) else { continue }
            let track = try XCTUnwrap(ASSTrackRenderer(header: split.header))
            track.setFrame(pixels: CGSize(width: 854, height: 480), video: CGSize(width: 854, height: 480), fontScale: 1)
            for event in split.events { track.add(rawEventText: event.line, start: event.start, end: event.end) }
            for event in split.events {
                _ = track.render(at: event.start)
                _ = track.render(at: (event.start + event.end) / 2)
            }
        }
    }

    // MARK: - A script as a player hands it over

    struct Split {
        var header: String
        var events: [(line: String, start: Double, end: Double)]
    }

    /// Every line but the events is the header (Matroska's CodecPrivate carries the [Fonts] and [Graphics] sections too); an event
    /// becomes `ReadOrder,Layer,<the fields after End>`, as libavcodec hands it to AetherEngine. nil for a format whose first three
    /// fields are not Layer (or Marked), Start, End.
    static func split(_ url: URL) throws -> Split? {
        let text = try String(contentsOf: url, encoding: .utf8)
        var header: [String] = []
        var events: [(String, Double, Double)] = []
        var inEvents = false
        var fieldCount = 0
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.hasPrefix("\u{FEFF}") ? String(raw.dropFirst()) : raw
            if line.hasPrefix("[") { inEvents = line.lowercased().hasPrefix("[events]") }
            if inEvents, line.lowercased().hasPrefix("format:") {
                let fields = line.dropFirst(7).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                guard fields.count >= 4, ["layer", "marked"].contains(fields[0]), fields[1] == "start", fields[2] == "end" else { return nil }
                fieldCount = fields.count
            }
            if inEvents, line.hasPrefix("Dialogue:") {
                let parts = line.dropFirst(9).split(separator: ",", maxSplits: max(fieldCount - 1, 1), omittingEmptySubsequences: false)
                    .map(String.init)
                guard parts.count == fieldCount, let start = time(parts[1]), let end = time(parts[2]) else { continue }
                let layer = parts[0].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "Marked=", with: "")
                events.append(("\(events.count),\(layer),\(parts[3...].joined(separator: ","))", start, end))
                continue
            }
            if inEvents, line.hasPrefix("Comment:") { continue }
            header.append(line)
        }
        return Split(header: header.joined(separator: "\n"), events: events)
    }

    static func time(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }

    // MARK: - Measuring as compare.c measures

    static func error(split: Split, fonts: [(name: String, data: Data)], reference: URL, ms: Int, scale: (x: Int, y: Int)) throws -> Double {
        let target = try XCTUnwrap(Self.raw(png: reference), "\(reference.lastPathComponent) could not be read")
        let track = try XCTUnwrap(ASSTrackRenderer(header: split.header, fonts: fonts, systemFonts: false))
        let width = target.width * scale.x, height = target.height * scale.y
        track.setFrame(pixels: CGSize(width: width, height: height), video: CGSize(width: target.width, height: target.height), fontScale: 1)
        for event in split.events { track.add(rawEventText: event.line, start: event.start, end: event.end) }

        // The picture over black, alpha counting down from 255 with coverage, as compare.c's `blend_all` leaves it; 16 bits.
        var frame = [UInt16](repeating: 0, count: width * height * 4)
        for index in stride(from: 3, to: frame.count, by: 4) { frame[index] = 255 * 257 }
        if let picture = track.render(at: Double(ms) / 1000).picture, let data = picture.image.dataProvider?.data as Data? {
            let rowBytes = picture.image.bytesPerRow
            for y in 0..<Int(picture.frame.height) {
                for x in 0..<Int(picture.frame.width) {
                    let fx = Int(picture.frame.minX) + x, fy = Int(picture.frame.minY) + y
                    guard fx < width, fy < height else { continue }
                    let source = y * rowBytes + x * 4, target = (fy * width + fx) * 4
                    for channel in 0..<3 { frame[target + channel] = UInt16(data[source + channel]) * 257 }
                    frame[target + 3] = UInt16(255 - data[source + 3]) * 257
                }
            }
        }
        // Down to the picture's size by averaging, as compare.c does for a scaled test.
        var drawn = [UInt32](repeating: 0, count: target.width * target.height * 4)
        for y in 0..<height { for x in 0..<width { for c in 0..<4 {
            drawn[((y / scale.y) * target.width + x / scale.x) * 4 + c] += UInt32(frame[(y * width + x) * 4 + c])
        } } }
        let area = UInt32(scale.x * scale.y)

        // The error: each pixel's largest channel difference over what the picture's own edges there allow (compare.c's `calc_grad`).
        func at(_ x: Int, _ y: Int, _ c: Int) -> Int { Int(target.pixels[(y * target.width + x) * 4 + c]) }
        func diff4(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int) -> Int { (0..<4).map { abs(at(x1, y1, $0) - at(x2, y2, $0)) }.max()! }
        var worst = 0.0
        for y in 0..<target.height {
            for x in 0..<target.width {
                var grad = 257 + 65535 / 4
                if x > 0, y > 0, x < target.width - 1, y < target.height - 1 {
                    let sides = [diff4(x, y, x - 1, y), diff4(x, y, x + 1, y), diff4(x, y, x, y - 1), diff4(x, y, x, y + 1)].map { $0 / 4 }
                    let corners = [diff4(x, y, x - 1, y - 1), diff4(x, y, x + 1, y - 1), diff4(x, y, x - 1, y + 1), diff4(x, y, x + 1, y + 1)]
                        .map { $0 / 8 }
                    grad = 257 + (sides + corners).max()!
                }
                let ours = (0..<4).map { Int((drawn[(y * target.width + x) * 4 + $0] + area / 2) / area) }
                let difference = (0..<4).map { abs(ours[$0] - at(x, y, $0)) }.max()!
                worst = max(worst, Double(difference) / Double(grad))
            }
        }
        return worst
    }

    /// A PNG's RGBA in 16 bits, turned as compare/image.c's `read_png` turns it: the colours multiplied by the alpha, the alpha
    /// inverted (a count-down from opaque black, as the drawn frame keeps it). Read from the file's own bytes: Core Graphics would
    /// premultiply on its own terms.
    static func raw(png url: URL) -> (width: Int, height: Int, pixels: [UInt16])? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary),
              image.bitsPerPixel == 4 * image.bitsPerComponent, let data = image.dataProvider?.data as Data? else { return nil }
        let width = image.width, height = image.height, row = image.bytesPerRow
        var pixels = [UInt16](repeating: 0, count: width * height * 4)
        let big = image.bitmapInfo.contains(.byteOrder16Big) || image.bitmapInfo.intersection(.byteOrderMask).isEmpty
        for y in 0..<height {
            for x in 0..<width {
                let out = (y * width + x) * 4
                if image.bitsPerComponent == 8 {
                    let at = y * row + x * 4
                    let a = UInt32(data[at + 3])
                    for c in 0..<3 {
                        let product = UInt32(data[at + c]) * a
                        pixels[out + c] = UInt16((product + (product >> 8) + 128) >> 8) * 257
                    }
                    pixels[out + 3] = UInt16(255 - a) * 257
                } else {
                    func value(_ c: Int) -> UInt64 {
                        let at = y * row + x * 8 + c * 2
                        return UInt64(big ? UInt16(data[at]) << 8 | UInt16(data[at + 1]) : UInt16(data[at + 1]) << 8 | UInt16(data[at]))
                    }
                    let a = value(3)
                    for c in 0..<3 { pixels[out + c] = UInt16((value(c) * a + 32767) / 65535) }
                    pixels[out + 3] = UInt16(65535 - a)
                }
            }
        }
        return (width, height, pixels)
    }

    // MARK: - Files

    static func children(of url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func fonts(in url: URL) throws -> [(name: String, data: Data)] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try children(of: url).filter { ["ttf", "otf", "ttc"].contains($0.pathExtension.lowercased()) }
            .map { ($0.lastPathComponent, try Data(contentsOf: $0)) }
    }

    static func scale(in group: URL) -> (x: Int, y: Int) {
        guard let text = try? String(contentsOf: group.appendingPathComponent("scale"), encoding: .utf8) else { return (1, 1) }
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "x").compactMap { Int($0) }
        return parts.count == 2 ? (parts[0], parts[1]) : (parts.first ?? 1, parts.first ?? 1)
    }
}
