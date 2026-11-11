//
//  ASSTrackRenderer.swift
//  ASSRenderer
//
//  One ASS or SSA subtitle track drawn by libass: the track's header and its events as the player hands them over, and a
//  picture of what shows at a given time. Plain Swift over libass's C interface, nothing of the player: the app's overlay
//  (`ASSSubtitleLayer` in the shared tree) times it and puts the picture on screen (docs/ass-subtitles.md).
//
//  Not thread-safe: one queue owns an instance from start to end.
//

import Foundation
import CoreGraphics
import Libass

public final class ASSTrackRenderer {
    /// A picture of the subtitles at one moment: `image` placed at `frame` in the frame `setFrame` was given, in its pixels.
    public struct Picture {
        public let image: CGImage
        public let frame: CGRect
    }

    private let library: OpaquePointer
    private let renderer: OpaquePointer
    private let track: UnsafeMutablePointer<ASS_Track>
    /// The events already handed to libass, by start, end and line: the player hands the same event over again after a seek, and
    /// libass's own check reads the ReadOrder field, which many files set to 0 on every line (AetherEngine's `ASSScriptBuilder`,
    /// "field repro: anime MKV collapsed to one event"), so it is turned off and this set does the work.
    private var seen: Set<String> = []
    private var frameSize: (width: Int32, height: Int32) = (0, 0)
    private var last: Picture?

    /// `header` is the track's script header (`[Script Info]`, the styles, often the `[Events]` format line); `fonts` the
    /// files the video carries for it (a Matroska file's attachments), by file name. `systemFonts` false leaves the system's fonts
    /// out, as libass's own regression tests draw (`LibassRegressionTests`).
    public init?(header: String, fonts: [(name: String, data: Data)] = [], systemFonts: Bool = true) {
        guard let library = ass_library_init() else { return nil }
        guard let renderer = ass_renderer_init(library) else { ass_library_done(library); return nil }
        guard let track = ass_new_track(library) else {
            ass_renderer_done(renderer)
            ass_library_done(library)
            return nil
        }
        self.library = library
        self.renderer = renderer
        self.track = track

        // A font in the script's own [Fonts] section, and the video's attachments, before the renderer looks up any.
        ass_set_extract_fonts(library, 1)
        for font in fonts {
            font.data.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                ass_add_font(library, font.name, base.assumingMemoryBound(to: CChar.self), Int32(bytes.count))
            }
        }
        // Core Text finds the system's fonts on every Apple platform; no fontconfig, no font cache built at first use. A
        // family the system lacks falls back to its sans-serif.
        ass_set_fonts(renderer, nil, systemFonts ? "sans-serif" : nil,
                      Int32((systemFonts ? ASS_FONTPROVIDER_AUTODETECT : ASS_FONTPROVIDER_NONE).rawValue), nil, 1)

        // A Matroska header often ends with a NUL, and libass reads it as a C string: everything after a NUL is lost
        // (AetherEngine's `ASSScriptBuilder`, "2 styles, 0 events"). A header with no [Events] section is libass's to handle:
        // it takes the standard format line then.
        let cleaned = header.replacingOccurrences(of: "\0", with: "")
        var bytes = Array(cleaned.utf8)
        bytes.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress?.withMemoryRebound(to: CChar.self, capacity: buffer.count) {
                ass_process_codec_private(track, $0, Int32(buffer.count))
            }
        }
        ass_set_check_readorder(track, 0)
    }

    deinit {
        ass_free_track(track)
        ass_renderer_done(renderer)
        ass_library_done(library)
    }

    public var eventCount: Int { Int(track.pointee.n_events) }

    /// Hands libass the events of one cue: `rawEventText` is one or more lines in Matroska's event shape
    /// (`ReadOrder,Layer,Style,Name,MarginL,MarginR,MarginV,Effect,Text`, without times), joined by newlines, as the player
    /// passes them with its cue's start and end in seconds. An event already handed over is passed by.
    public func add(rawEventText: String, start: Double, end: Double) {
        guard start.isFinite, end.isFinite else { return }
        let startMs = Int64((start * 1000).rounded())
        let durationMs = max(0, Int64((end * 1000).rounded()) - startMs)
        for line in rawEventText.split(separator: "\n", omittingEmptySubsequences: true) {
            let key = "\(startMs)|\(durationMs)|\(line)"
            guard seen.insert(key).inserted else { continue }
            var bytes = Array(line.utf8)
            bytes.withUnsafeMutableBufferPointer { buffer in
                buffer.baseAddress?.withMemoryRebound(to: CChar.self, capacity: buffer.count) {
                    ass_process_chunk(track, $0, Int32(buffer.count), startMs, durationMs)
                }
            }
        }
    }

    /// Where it draws: `pixels`, the picture's rectangle on screen in pixels; `video`, the video's coded size, which the script's
    /// own coordinates are mapped from; `fontScale`, the person's size for dialogue, 1 as written. Signs, karaoke and anything
    /// placed by the script keep their size, as mpv draws them (`--sub-ass-override=scale` and `--sub-scale-signs=no`, its
    /// defaults: the Windows and Linux apps).
    public func setFrame(pixels: CGSize, video: CGSize, fontScale: Double) {
        let width = Int32(max(1, pixels.width.rounded())), height = Int32(max(1, pixels.height.rounded()))
        if (width, height) != frameSize {
            frameSize = (width, height)
            ass_set_frame_size(renderer, width, height)
            last = nil
        }
        ass_set_storage_size(renderer, Int32(max(0, video.width.rounded())), Int32(max(0, video.height.rounded())))
        ass_set_selective_style_override_enabled(renderer, Int32(ASS_OVERRIDE_BIT_SELECTIVE_FONT_SCALE.rawValue))
        ass_set_font_scale(renderer, fontScale.isFinite && fontScale > 0 ? fontScale : 1)
    }

    /// What shows at `seconds` on the track's own clock, nil when nothing does. `changed` says whether it differs from the last
    /// picture, so a caller can leave the screen as it is.
    public func render(at seconds: Double) -> (picture: Picture?, changed: Bool) {
        guard frameSize.width > 0, seconds.isFinite else { return (nil, false) }
        var change: Int32 = 0
        let images = ass_render_frame(renderer, track, Int64((seconds * 1000).rounded()), &change)
        if change == 0, last != nil || images == nil { return (last, false) }
        last = images.flatMap { Self.compose($0, in: frameSize) }
        return (last, true)
    }

    // MARK: - Putting libass's pieces into one picture

    /// `value / 255`, rounded, for `value` up to 255 * 255. In brackets on purpose: Swift's `>>` binds tighter than `*`, so the
    /// same sum written `(value + 128) * 257 >> 16` multiplies by 0 and every picture came out clear (seen on the agent simulator).
    @inline(__always)
    static func dividedBy255(_ value: UInt32) -> UInt32 {
        ((value + 128) * 257) >> 16
    }

    /// libass hands over a list of single-colour alpha masks, each with its own place; they are laid over one another in their
    /// order into one premultiplied RGBA picture the size of their bounds. The alpha of a colour is its transparency: 0 opaque.
    static func compose(_ first: UnsafeMutablePointer<ASS_Image>, in size: (width: Int32, height: Int32)) -> Picture? {
        var bounds = CGRect.null
        var node: UnsafeMutablePointer<ASS_Image>? = first
        while let image = node?.pointee {
            if image.w > 0, image.h > 0 {
                bounds = bounds.union(CGRect(x: Int(image.dst_x), y: Int(image.dst_y), width: Int(image.w), height: Int(image.h)))
            }
            node = image.next
        }
        bounds = bounds.intersection(CGRect(x: 0, y: 0, width: Int(size.width), height: Int(size.height)))
        guard !bounds.isNull, bounds.width >= 1, bounds.height >= 1 else { return nil }

        let width = Int(bounds.width), height = Int(bounds.height)
        let originX = Int(bounds.minX), originY = Int(bounds.minY)
        let rowBytes = width * 4
        // One zeroed buffer, written in place and handed to Core Graphics as it is (an array copied into `Data` was two per frame).
        var pixels = Data(count: rowBytes * height)
        pixels.withUnsafeMutableBytes { canvas in
            guard let out = canvas.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            node = first
            while let image = node?.pointee {
                defer { node = image.next }
                guard image.w > 0, image.h > 0, let mask = image.bitmap else { continue }
                let red = UInt32(image.color >> 24 & 0xFF), green = UInt32(image.color >> 16 & 0xFF)
                let blue = UInt32(image.color >> 8 & 0xFF), opacity = 255 - UInt32(image.color & 0xFF)
                guard opacity > 0 else { continue }
                // Only the part inside the picture: libass may place a mask partly outside the frame.
                let left = max(Int(image.dst_x), originX), right = min(Int(image.dst_x) + Int(image.w), originX + width)
                let top = max(Int(image.dst_y), originY), bottom = min(Int(image.dst_y) + Int(image.h), originY + height)
                guard left < right, top < bottom else { continue }
                for y in top..<bottom {
                    let source = mask + (y - Int(image.dst_y)) * Int(image.stride) + (left - Int(image.dst_x))
                    var target = out + (y - originY) * rowBytes + (left - originX) * 4
                    for x in 0..<(right - left) {
                        let coverage = UInt32(source[x])
                        if coverage != 0 {
                            // Source over destination, premultiplied.
                            let alpha = Self.dividedBy255(coverage * opacity)
                            let keep = 255 - alpha
                            target[0] = UInt8(Self.dividedBy255(red * alpha + UInt32(target[0]) * keep))
                            target[1] = UInt8(Self.dividedBy255(green * alpha + UInt32(target[1]) * keep))
                            target[2] = UInt8(Self.dividedBy255(blue * alpha + UInt32(target[2]) * keep))
                            target[3] = UInt8(Self.dividedBy255(alpha * 255 + UInt32(target[3]) * keep))
                        }
                        target += 4
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return Picture(image: image, frame: bounds)
    }
}
