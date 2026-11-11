import XCTest
import CoreGraphics
@testable import ASSRenderer

final class ASSTrackRendererTests: XCTestCase {
    /// A header as Matroska carries it: no [Events] section and a NUL at the end.
    private let header = """
    [Script Info]
    ScriptType: v4.00+
    PlayResX: 1920
    PlayResY: 1080

    [V4+ Styles]
    Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
    Style: Default,Helvetica,60,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,3,0,2,20,20,40,1
    \0
    """

    private func renderer(width: CGFloat = 1920, height: CGFloat = 1080) throws -> ASSTrackRenderer {
        let renderer = try XCTUnwrap(ASSTrackRenderer(header: header))
        renderer.setFrame(pixels: CGSize(width: width, height: height), video: CGSize(width: 1920, height: 1080), fontScale: 1)
        return renderer
    }

    func testAPositionedSignIsDrawnWhereTheScriptPutsIt() throws {
        let track = try renderer()
        // The column of letters in a report came from lines like this one: each its own place.
        track.add(rawEventText: #"0,0,Default,,0,0,0,,{\an7\pos(100,100)}A"#, start: 1, end: 3)
        track.add(rawEventText: #"1,0,Default,,0,0,0,,{\an7\pos(1500,800)}B"#, start: 1, end: 3)
        let picture = try XCTUnwrap(track.render(at: 2).picture)
        XCTAssertLessThan(picture.frame.minX, 200)
        XCTAssertLessThan(picture.frame.minY, 200)
        XCTAssertGreaterThan(picture.frame.maxX, 1500)
        XCTAssertGreaterThan(picture.frame.maxY, 800)
    }

    func testNothingShowsOutsideAnEventsTime() throws {
        let track = try renderer()
        track.add(rawEventText: "0,0,Default,,0,0,0,,Hello", start: 1, end: 2)
        XCTAssertNil(track.render(at: 0.5).picture)
        XCTAssertNotNil(track.render(at: 1.5).picture)
        XCTAssertNil(track.render(at: 2.5).picture)
    }

    /// The player hands the same event over again after a seek, and files set ReadOrder to 0 on every line: neither may lose or
    /// double an event.
    func testTheSameEventTwiceIsKeptOnceAndReadOrderIsNotTheKey() throws {
        let track = try renderer()
        track.add(rawEventText: "0,0,Default,,0,0,0,,One", start: 1, end: 2)
        track.add(rawEventText: "0,0,Default,,0,0,0,,One", start: 1, end: 2)
        track.add(rawEventText: "0,0,Default,,0,0,0,,Two", start: 3, end: 4)
        XCTAssertEqual(track.eventCount, 2)
    }

    func testAnUnchangedMomentSaysSo() throws {
        let track = try renderer()
        track.add(rawEventText: "0,0,Default,,0,0,0,,Still", start: 0, end: 10)
        XCTAssertTrue(track.render(at: 1).changed)
        XCTAssertFalse(track.render(at: 1.04).changed)
    }

    /// The person's size reaches dialogue and leaves a positioned sign as written (mpv's `--sub-scale-signs=no`).
    func testTheSizeSettingScalesDialogueAndNotSigns() throws {
        func width(of line: String, scale: Double) throws -> CGFloat {
            let track = try XCTUnwrap(ASSTrackRenderer(header: header))
            track.setFrame(pixels: CGSize(width: 1920, height: 1080), video: CGSize(width: 1920, height: 1080), fontScale: scale)
            track.add(rawEventText: line, start: 0, end: 5)
            return try XCTUnwrap(track.render(at: 1).picture).frame.width
        }
        let dialogue = "0,0,Default,,0,0,0,,Dialogue line"
        XCTAssertGreaterThan(try width(of: dialogue, scale: 1.5), try width(of: dialogue, scale: 1) * 1.3)
        let sign = #"0,0,Default,,0,0,0,,{\pos(960,300)}Sign"#
        XCTAssertEqual(try width(of: sign, scale: 1.5), try width(of: sign, scale: 1), accuracy: 2)
    }

    func testThePictureFollowsTheFrameSize() throws {
        let track = try renderer(width: 960, height: 540)
        track.add(rawEventText: #"0,0,Default,,0,0,0,,{\an7\pos(1800,1000)}Z"#, start: 0, end: 5)
        let picture = try XCTUnwrap(track.render(at: 1).picture)
        XCTAssertGreaterThan(picture.frame.minX, 850)
        XCTAssertLessThanOrEqual(picture.frame.maxX, 960)
    }

    /// The picture has the text in it: white letters on a clear ground. Every picture was clear until 2026-11-04 (an operator
    /// precedence slip in the blending), which the tests on placement alone did not see.
    func testThePictureHoldsTheLettersInTheirColour() throws {
        let track = try renderer()
        track.add(rawEventText: "0,0,Default,,0,0,0,,{\\bord0\\shad0}Hello", start: 0, end: 5)
        let picture = try XCTUnwrap(track.render(at: 1).picture)
        let data = try XCTUnwrap(picture.image.dataProvider?.data) as Data
        var opaque = 0, white = 0
        for index in stride(from: 0, to: data.count, by: 4) where data[index + 3] == 255 {
            opaque += 1
            if data[index] == 255, data[index + 1] == 255, data[index + 2] == 255 { white += 1 }
        }
        XCTAssertGreaterThan(opaque, 100)
        XCTAssertEqual(white, opaque, "a fully covered pixel of white text is white")
        XCTAssertEqual(ASSTrackRenderer.dividedBy255(255 * 255), 255)
        XCTAssertEqual(ASSTrackRenderer.dividedBy255(128 * 255), 128)
        XCTAssertEqual(ASSTrackRenderer.dividedBy255(0), 0)
    }

}
