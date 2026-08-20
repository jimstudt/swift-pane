import Foundation
import Testing
@testable import SwiftPane

/// The whole package in one frame: a representative dashboard built
/// from every element type, rendered banded, streamed to a PNG, and
/// verified through a real decoder.
struct DashboardTests {
    static let background = Color(r: 16, g: 20, b: 30)
    static let card = Color(hue: 0.6, saturation: 0.35, lightness: 0.22)
    static let accent = Color(hue: 0.45, saturation: 0.8, lightness: 0.5)
    static let warn = Color(hue: 0.08, saturation: 0.9, lightness: 0.55)

    /// Counts decoded pixels within ±3 per channel of `color`.
    private func count(_ color: Color, in decoded: (width: Int, height: Int, rgba: [UInt8])) -> Int {
        var n = 0
        for p in stride(from: 0, to: decoded.rgba.count, by: 4) {
            if abs(Int(decoded.rgba[p]) - Int(color.r)) <= 3,
               abs(Int(decoded.rgba[p + 1]) - Int(color.g)) <= 3,
               abs(Int(decoded.rgba[p + 2]) - Int(color.b)) <= 3 {
                n += 1
            }
        }
        return n
    }

    /// Builds the dashboard and renders it to PNG bytes. A fresh tree
    /// per call, as the per-frame design intends.
    private func renderDashboard(bandHeight: Int) throws -> [UInt8] {
        let font = try TestFont.load()
        let fonts = [font]
        let textDim = Color(white: 0.7)

        // Dynamic values, formatted allocation-free.
        var tempText = TextBuffer<16>()
        tempText.append(321.46, decimals: 1)
        tempText.append("°C")
        var rpmText = TextBuffer<16>()
        rpmText.append(3180, width: 5)
        rpmText.append(" rpm")
        var pctText = TextBuffer<8>()
        pctText.append(87)
        pctText.append("%")

        var pane = Pane(size: Size(width: 320, height: 240), root:
            Padding(10, Column(spacing: 8,
                // Title row: static labels, spacer-driven layout.
                Row(spacing: 8, alignment: .center,
                    Label("REACTOR 4", size: 26, color: .white),
                    Spacer(),
                    Label("ONLINE", size: 14, color: Self.accent)),
                // A plain filled rectangle as a divider.
                SizedBox(height: 2, Box(fill: Color(white: 0.35))),
                // Two gauge cards: rounded fills, dynamic text, overlay bars.
                Row(spacing: 8,
                    Box(fill: Self.card, cornerRadius: 8, padding: EdgeInsets(8),
                        Column(spacing: 4,
                            Label("CORE TEMP", size: 11, color: textDim),
                            Label(tempText.span, size: 20, color: .white),
                            SizedBox(width: 120, height: 10, Overlay(alignment: .leading,
                                Box(fill: Color(white: 0.15), cornerRadius: 5),
                                SizedBox(width: 78, height: 10,
                                         Box(fill: Self.warn, cornerRadius: 5)))))),
                    Box(fill: Self.card, cornerRadius: 8, padding: EdgeInsets(8),
                        Column(spacing: 4,
                            Label("TURBINE", size: 11, color: textDim),
                            Label(rpmText.span, size: 20, color: .white),
                            SizedBox(width: 120, height: 10, Overlay(alignment: .leading,
                                Box(fill: Color(white: 0.15), cornerRadius: 5),
                                SizedBox(width: 104, height: 10,
                                         Box(fill: Self.accent, cornerRadius: 5))))))),
                // A bordered rounded rect with trailing-aligned dynamic text.
                Box(border: Self.warn.mixed(with: .white, amount: 0.3), borderWidth: 2,
                    cornerRadius: 10, padding: EdgeInsets(horizontal: 10, vertical: 6),
                    Row(spacing: 6, alignment: .center,
                        Label("COOLANT", size: 14, color: .white),
                        Spacer(),
                        SizedBox(width: 60,
                                 Label(pctText.span, size: 14, color: Self.accent,
                                       alignment: .trailing)))),
                Spacer(),
                // Footer pinned to the bottom by the spacer above.
                Row(alignment: .center,
                    Label("swift-pane", size: 12, color: textDim),
                    Spacer(),
                    Label("14:32:07", size: 12, color: textDim)))))

        let env = Environment(fonts: fonts.span, textColor: .white)
        return pane.renderPNGData(env, background: Self.background, bandHeight: bandHeight)
    }

    @Test func rendersRepresentativeDashboardToPNG() throws {
        // 240 = 8 × 28 + 16: the last band is partial on purpose.
        let png = try renderDashboard(bandHeight: 28)

        // It's a real PNG of the right size, and compression did its job.
        #expect(Array(png.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
        #expect(png.count < 60_000)
        let decoded = try #require(decodePNG(png))
        #expect(decoded.width == 320 && decoded.height == 240)

        // Background reaches the corners (padding margin).
        func rgba(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
            let i = (y * 320 + x) * 4
            return (decoded.rgba[i], decoded.rgba[i + 1], decoded.rgba[i + 2])
        }
        #expect(rgba(2, 2) == (16, 20, 30))
        #expect(rgba(317, 237) == (16, 20, 30))

        // Every feature left enough of its color behind: card fills,
        // both gauge-bar fills, the mixed border, and white glyph cores.
        #expect(count(Self.card, in: decoded) > 2000)
        #expect(count(Self.warn, in: decoded) > 400)
        #expect(count(Self.accent, in: decoded) > 500)
        #expect(count(Self.warn.mixed(with: .white, amount: 0.3), in: decoded) > 300)
        #expect(count(.white, in: decoded) > 100)

        // Keep a copy a human can look at.
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-pane-dashboard.png")
        try Data(png).write(to: out)
        print("dashboard PNG written to \(out.path)")
    }

    /// Banding must be invisible: uneven bands and a single full-frame
    /// pass produce byte-identical PNGs.
    @Test func bandedAndWholeFrameAgree() throws {
        let banded = try renderDashboard(bandHeight: 28)
        let whole = try renderDashboard(bandHeight: 240)
        #expect(banded == whole)
    }

    /// The pane's scratch requirement is the exact bound of its
    /// largest text, gathered once at layout.
    @Test func glyphScratchSizeIsAPaneProperty() throws {
        let font = try TestFont.load()
        let fonts = [font]
        let env = Environment(fonts: fonts.span)

        var pane = Pane(size: Size(width: 100, height: 50), root:
            Column(spacing: 2,
                Label("small", size: 11),
                Box(fill: .white, padding: EdgeInsets(2), Label("big", size: 26))))
        #expect(pane.glyphScratchSize == 0)  // not laid out yet
        pane.layout(env)
        let bound = font.sized(pixelHeight: 26).maximumBitmapSize
        #expect(pane.glyphScratchSize == bound.width * bound.height)

        var textless = Pane(size: Size(width: 10, height: 10),
                            root: Box(fill: .white))
        textless.layout(env)
        #expect(textless.glyphScratchSize == 0)
    }
}
