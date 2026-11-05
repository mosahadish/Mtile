import XCTest
@testable import Mtile

/// Records every canvas call; text is measured at a fixed 10pt per character.
private final class FakeCanvas: BarCanvas {
    var fills: [(BarRect, RGBColor)] = []
    var texts: [(String, BarRect)] = []

    func measure(_ text: String) -> Double { Double(text.count) * 10 }
    func fill(_ rect: BarRect, _ color: RGBColor) { fills.append((rect, color)) }
    func drawText(_ text: String, in rect: BarRect, color: RGBColor, alignment: BarTextAlignment) { texts.append((text, rect)) }
}

private final class FakeSegment: Segment {
    let width: Double
    let isFlexible: Bool
    var drawnBounds: BarRect?
    var clicks: [Double] = []

    init(width: Double, flexible: Bool = false) {
        self.width = width
        self.isFlexible = flexible
    }

    func measure(_ canvas: BarCanvas) -> Double { width }
    func draw(_ canvas: BarCanvas, _ bounds: BarRect) { drawnBounds = bounds }
    func onClick(_ xInSegment: Double) { clicks.append(xInSegment) }
}

final class BarRendererTests: XCTestCase {
    private let bounds = BarRect(x: 0, y: 0, width: 1000, height: 24)
    private let theme = BarTheme(BarColorsConfig())

    func testDraw_FillsBackgroundFirst() {
        let canvas = FakeCanvas()
        _ = BarRenderer(left: [], right: [], theme: theme).draw(canvas, bounds)
        XCTAssertEqual(canvas.fills.first?.0, bounds)
        XCTAssertEqual(canvas.fills.first?.1, theme.background)
    }

    func testDraw_FlexibleSegmentGetsLeftoverWidth_RightSegmentsAreRightAligned() {
        let tags = FakeSegment(width: 252)
        let symbol = FakeSegment(width: 30)
        let title = FakeSegment(width: 0, flexible: true)
        let clock = FakeSegment(width: 200)
        let hits = BarRenderer(left: [tags, symbol, title], right: [clock], theme: theme).draw(FakeCanvas(), bounds)

        XCTAssertEqual(tags.drawnBounds, BarRect(x: 0, y: 0, width: 252, height: 24))
        XCTAssertEqual(symbol.drawnBounds, BarRect(x: 252, y: 0, width: 30, height: 24))
        XCTAssertEqual(title.drawnBounds, BarRect(x: 282, y: 0, width: 518, height: 24))
        XCTAssertEqual(clock.drawnBounds, BarRect(x: 800, y: 0, width: 200, height: 24))
        XCTAssertEqual(hits.count, 4)
    }

    func testDraw_FlexibleSegmentNeverGoesNegative() {
        let title = FakeSegment(width: 0, flexible: true)
        _ = BarRenderer(left: [FakeSegment(width: 700), title], right: [FakeSegment(width: 500)], theme: theme).draw(FakeCanvas(), bounds)
        XCTAssertEqual(title.drawnBounds?.width, 0)
    }

    func testDraw_FlexibleSegmentStopsAtObstruction() {
        let tags = FakeSegment(width: 252)
        let title = FakeSegment(width: 0, flexible: true)
        let clock = FakeSegment(width: 200)
        _ = BarRenderer(left: [tags, title], right: [clock], theme: theme).draw(FakeCanvas(), bounds, obstruction: 400...600)
        XCTAssertEqual(title.drawnBounds, BarRect(x: 252, y: 0, width: 148, height: 24))
        XCTAssertEqual(clock.drawnBounds, BarRect(x: 800, y: 0, width: 200, height: 24))
    }

    func testDraw_ObstructionLeftOfFixedSegments_IsIgnoredForTitle() {
        let title = FakeSegment(width: 0, flexible: true)
        _ = BarRenderer(left: [FakeSegment(width: 500), title], right: [FakeSegment(width: 200)], theme: theme)
            .draw(FakeCanvas(), bounds, obstruction: 400...450)
        XCTAssertEqual(title.drawnBounds?.width, 300)
    }

    func testClick_DispatchesToSegmentUnderX_WithLocalOffset() {
        let tags = FakeSegment(width: 252)
        let title = FakeSegment(width: 0, flexible: true)
        let clock = FakeSegment(width: 200)
        let hits = BarRenderer(left: [tags, title], right: [clock], theme: theme).draw(FakeCanvas(), bounds)

        BarRenderer.click(hits, x: 30)
        BarRenderer.click(hits, x: 850)
        XCTAssertEqual(tags.clicks, [30])
        XCTAssertEqual(clock.clicks, [50])
        XCTAssertTrue(title.clicks.isEmpty)
    }

    func testTagsSegment_ClickViewsTheClickedTag() {
        let backend = FakeBackend()
        let manager = WindowManager(backend: backend, layouts: LayoutRegistry.createDefault(), defaultLayoutName: "master-stack",
                                    defaultLayoutParams: [:], tagCount: 9)
        manager.initializeMonitors()
        let registry = CommandRegistry()
        var executed: [[String]] = []
        registry.register(ClosureCommand("view-tag") { executed.append($0) })
        let segment = TagsSegment(manager: manager, commands: registry, theme: theme, monitorIndex: 0, useBackgroundIndicator: false)

        XCTAssertEqual(segment.measure(FakeCanvas()), 28 * 9)
        segment.onClick(30)   // second pill (28pt each)
        segment.onClick(500)  // past the last tag
        XCTAssertEqual(executed, [["2"]])
    }

    func testTagsSegment_DrawsOneLabelPerTag() {
        let manager = WindowManager(backend: FakeBackend(), layouts: LayoutRegistry.createDefault(), defaultLayoutName: "master-stack",
                                    defaultLayoutParams: [:], tagCount: 4)
        manager.initializeMonitors()
        let segment = TagsSegment(manager: manager, commands: CommandRegistry(), theme: theme, monitorIndex: 0, useBackgroundIndicator: false)
        let canvas = FakeCanvas()
        segment.draw(canvas, BarRect(x: 0, y: 0, width: 112, height: 24))
        XCTAssertEqual(canvas.texts.map(\.0), ["1", "2", "3", "4"])
        XCTAssertEqual(canvas.texts[1].1, BarRect(x: 28, y: 0, width: 28, height: 24))
    }

    func testRGBColor_Parse() {
        XCTAssertEqual(RGBColor.parse("#1e1e2e"), RGBColor(0x1e, 0x1e, 0x2e))
        XCTAssertEqual(RGBColor.parse("#fff"), RGBColor(255, 255, 255))
        XCTAssertNil(RGBColor.parse("1e1e2e"))
        XCTAssertNil(RGBColor.parse("#12345"))
        XCTAssertNil(RGBColor.parse("#gggggg"))
    }
}
