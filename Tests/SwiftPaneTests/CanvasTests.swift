import Testing
@testable import SwiftPane

/// Draws a little scene exercising every canvas primitive.
private func drawScene(into canvas: inout Canvas) {
    canvas.fill(Rect(x: 0, y: 0, width: 64, height: 64), color: Color(r: 20, g: 24, b: 40))
    canvas.fill(Rect(x: -10, y: 5, width: 30, height: 200), color: Color(r: 200, g: 40, b: 40))
    canvas.fillRounded(Rect(x: 24, y: 10, width: 30, height: 40), cornerRadius: 8,
                       color: Color(r: 40, g: 180, b: 90))
    canvas.strokeRounded(Rect(x: 4, y: 30, width: 40, height: 28), cornerRadius: 6, width: 3,
                         color: Color(r: 240, g: 200, b: 60))
    canvas.fill(Rect(x: 10, y: 40, width: 50, height: 20),
                color: Color(r: 255, g: 255, b: 255, a: 90))
}

private func bgra(_ pixels: [UInt8], _ x: Int, _ y: Int, width: Int = 64) -> (UInt8, UInt8, UInt8, UInt8) {
    let i = (y * width + x) * 4
    return (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
}

struct CanvasTests {
    /// The load-bearing banding property: rendering in one pass and in
    /// uneven bands must produce byte-identical pixels.
    @Test func bandedRenderingMatchesWholeFrame() {
        var whole = [UInt8](repeating: 0, count: 64 * 64 * 4)
        whole.withUnsafeMutableBufferPointer { buf in
            var canvas = Canvas(pixels: buf.mutableSpan,
                                bandRect: Rect(x: 0, y: 0, width: 64, height: 64))
            drawScene(into: &canvas)
        }

        var banded = [UInt8](repeating: 0, count: 64 * 64 * 4)
        var y = 0
        for bandHeight in [24, 24, 16] {
            banded.withUnsafeMutableBufferPointer { buf in
                let slice = UnsafeMutableBufferPointer(
                    rebasing: buf[(y * 64 * 4)..<((y + bandHeight) * 64 * 4)])
                var canvas = Canvas(pixels: slice.mutableSpan,
                                    bandRect: Rect(x: 0, y: y, width: 64, height: bandHeight))
                drawScene(into: &canvas)
            }
            y += bandHeight
        }

        #expect(whole == banded)
    }

    @Test func fillClipsAndWritesBGRA() {
        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
        pixels.withUnsafeMutableBufferPointer { buf in
            var canvas = Canvas(pixels: buf.mutableSpan,
                                bandRect: Rect(x: 0, y: 0, width: 64, height: 64))
            canvas.fill(Rect(x: -10, y: -10, width: 20, height: 20),
                        color: Color(r: 1, g: 2, b: 3))
        }
        // BGRA byte order, clipped to the canvas.
        #expect(bgra(pixels, 0, 0) == (3, 2, 1, 255))
        #expect(bgra(pixels, 9, 9) == (3, 2, 1, 255))
        #expect(bgra(pixels, 10, 10) == (0, 0, 0, 0))
    }

    @Test func roundedCornersAreShapedAndCrisp() {
        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
        pixels.withUnsafeMutableBufferPointer { buf in
            var canvas = Canvas(pixels: buf.mutableSpan,
                                bandRect: Rect(x: 0, y: 0, width: 64, height: 64))
            canvas.fillRounded(Rect(x: 8, y: 8, width: 48, height: 48), cornerRadius: 12,
                               color: .white)
        }
        // Center: solid. Corner point of the rect: outside the rounding.
        #expect(bgra(pixels, 32, 32) == (255, 255, 255, 255))
        #expect(bgra(pixels, 8, 8) == (0, 0, 0, 0))
        // Straight edges land crisply: just inside is opaque, just outside is empty.
        #expect(bgra(pixels, 8, 32) == (255, 255, 255, 255))
        #expect(bgra(pixels, 7, 32) == (0, 0, 0, 0))
        #expect(bgra(pixels, 55, 32) == (255, 255, 255, 255))
        #expect(bgra(pixels, 56, 32) == (0, 0, 0, 0))
    }

    @Test func strokeLeavesInteriorEmpty() {
        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
        pixels.withUnsafeMutableBufferPointer { buf in
            var canvas = Canvas(pixels: buf.mutableSpan,
                                bandRect: Rect(x: 0, y: 0, width: 64, height: 64))
            canvas.strokeRounded(Rect(x: 8, y: 8, width: 48, height: 48), cornerRadius: 0,
                                 width: 2, color: .white)
        }
        #expect(bgra(pixels, 9, 32) == (255, 255, 255, 255))   // in the border
        #expect(bgra(pixels, 32, 9) == (255, 255, 255, 255))
        #expect(bgra(pixels, 32, 32) == (0, 0, 0, 0))          // interior untouched
        #expect(bgra(pixels, 6, 32) == (0, 0, 0, 0))           // outside untouched
    }
}
