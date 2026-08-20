import SwiftGlyph

/// The BGRA8888 compositor: a caller-owned pixel buffer plus the band
/// of the frame it represents.
///
/// All drawing operations take *frame* coordinates and clip to
/// ``bandRect``, so banded rendering and whole-frame rendering are the
/// same code path — a full frame is just the one-band case. The
/// element tree renders identically into every band; pixels outside
/// the band are simply not written.
///
/// The canvas also carries the glyph scratch buffer: A8 coverage from
/// SwiftGlyph is rasterized there, then composited. The caller sizes
/// it once for the largest glyph the pane can produce —
/// ``Pane/glyphScratchSize`` reports the exact requirement after
/// layout.
public struct Canvas: ~Copyable, ~Escapable {
    /// The destination pixels: BGRA8888, row-major, ``rowStride``
    /// bytes per row, covering exactly ``bandRect``.
    public var pixels: MutableSpan<UInt8>
    /// The frame region this buffer holds.
    public let bandRect: Rect
    /// Bytes per row in ``pixels``.
    public let rowStride: Int
    /// A8 scratch for glyph rasterization; caller-owned, unmanaged.
    /// Must outlive the canvas (the type can't express that for an
    /// unsafe buffer — keeping it alive is the caller's contract).
    @usableFromInline
    let glyphScratch: UnsafeMutableBufferPointer<UInt8>

    /// Creates a canvas over a caller-owned buffer.
    ///
    /// - Parameters:
    ///   - pixels: BGRA8888 storage, at least
    ///     `rowStride * (bandRect.height - 1) + bandRect.width * 4` bytes.
    ///   - bandRect: The frame region the buffer holds. For a whole
    ///     frame, `Rect(origin: .zero, size: frameSize)`.
    ///   - rowStride: Bytes per row; defaults to `bandRect.width * 4`.
    ///   - glyphScratch: A8 scratch sized for the largest glyph —
    ///     ``Pane/glyphScratchSize`` after layout, or the tree's
    ///     ``Element/glyphScratchSize(_:)``. May be empty for panes
    ///     that render no text.
    @_lifetime(copy pixels)
    public init(pixels: consuming MutableSpan<UInt8>, bandRect: Rect,
                rowStride: Int? = nil,
                glyphScratch: UnsafeMutableBufferPointer<UInt8> = .init(start: nil, count: 0)) {
        let stride = rowStride ?? bandRect.size.width * 4
        precondition(!bandRect.isEmpty, "canvas band must not be empty")
        precondition(stride >= bandRect.size.width * 4, "row stride shorter than a row")
        precondition(
            pixels.count >= stride * (bandRect.size.height - 1) + bandRect.size.width * 4,
            "pixel buffer too small for band")
        self.pixels = pixels
        self.bandRect = bandRect
        self.rowStride = stride
        self.glyphScratch = glyphScratch
    }

    // MARK: Rectangles

    /// Fills a rectangle, blending when the color is translucent.
    public mutating func fill(_ rect: Rect, color: Color) {
        guard color.a > 0, let clip = rect.intersection(bandRect) else { return }
        let x0 = clip.minX - bandRect.minX
        let y0 = clip.minY - bandRect.minY
        if color.isOpaque {
            for row in 0..<clip.size.height {
                var i = (y0 + row) * rowStride + x0 * 4
                for _ in 0..<clip.size.width {
                    pixels[i] = color.b
                    pixels[i + 1] = color.g
                    pixels[i + 2] = color.r
                    pixels[i + 3] = 255
                    i += 4
                }
            }
        } else {
            for row in 0..<clip.size.height {
                for col in 0..<clip.size.width {
                    blendLocal(x: x0 + col, y: y0 + row, color: color, coverage: 255)
                }
            }
        }
    }

    /// Fills a rounded rectangle; corners are anti-aliased, straight
    /// edges land crisply on the pixel grid. Radius 0 is a plain fill.
    public mutating func fillRounded(_ rect: Rect, cornerRadius: Int, color: Color) {
        let r = min(max(cornerRadius, 0), min(rect.size.width, rect.size.height) / 2)
        guard r > 0 else { return fill(rect, color: color) }
        guard color.a > 0, let clip = rect.intersection(bandRect) else { return }
        let zone = r + 1  // corner influence, plus AA margin
        for fy in clip.minY..<clip.maxY {
            let inTopZone = fy < rect.minY + zone
            let inBottomZone = fy >= rect.maxY - zone
            if !inTopZone && !inBottomZone {
                fillRow(y: fy, x0: clip.minX, x1: clip.maxX, color: color)
                continue
            }
            // Corner rows: SDF pixels in the corner spans, straight fill between.
            let leftEnd = min(rect.minX + zone, clip.maxX)
            let rightStart = max(rect.maxX - zone, clip.minX)
            for fx in clip.minX..<leftEnd {
                blendSDF(fx: fx, fy: fy, rect: rect, radius: r, color: color)
            }
            if leftEnd < rightStart {
                fillRow(y: fy, x0: leftEnd, x1: rightStart, color: color)
            }
            for fx in max(rightStart, leftEnd)..<clip.maxX {
                blendSDF(fx: fx, fy: fy, rect: rect, radius: r, color: color)
            }
        }
    }

    /// Strokes a (rounded) rectangle border of `width` pixels just
    /// inside `rect`. Radius 0 gives square corners.
    public mutating func strokeRounded(_ rect: Rect, cornerRadius: Int, width: Int, color: Color) {
        guard width > 0, color.a > 0, let clip = rect.intersection(bandRect) else { return }
        let r = min(max(cornerRadius, 0), min(rect.size.width, rect.size.height) / 2)
        let zone = max(r, width) + 1
        let band = width + 1  // vertical border span, plus AA margin
        for fy in clip.minY..<clip.maxY {
            let inTopZone = fy < rect.minY + zone
            let inBottomZone = fy >= rect.maxY - zone
            let xRanges: (Range<Int>, Range<Int>)
            if inTopZone || inBottomZone {
                xRanges = (clip.minX..<clip.maxX, 0..<0)
            } else {
                let leftEnd = min(rect.minX + band, clip.maxX)
                let rightStart = max(rect.maxX - band, leftEnd)
                xRanges = (clip.minX..<leftEnd, rightStart..<clip.maxX)
            }
            for fx in xRanges.0 {
                strokeSDF(fx: fx, fy: fy, rect: rect, radius: r, width: width, color: color)
            }
            for fx in xRanges.1 {
                strokeSDF(fx: fx, fy: fy, rect: rect, radius: r, width: width, color: color)
            }
        }
    }

    // MARK: Glyphs

    /// Rasterizes one glyph into the scratch buffer and composites it
    /// at `topLeft` (frame coordinates, the bitmap's top-left corner).
    ///
    /// Does nothing for empty glyphs or glyphs entirely outside the
    /// band. Throws SwiftGlyph's error for corrupt outline data; the
    /// caller decides on a fallback.
    public mutating func drawGlyph(
        _ glyph: GlyphID, metrics: GlyphMetrics, font: SizedFont,
        subpixelShift: Double, tint: Color, topLeft: Point
    ) throws(FontError) {
        let w = metrics.bitmapWidth
        let h = metrics.bitmapHeight
        guard w > 0, h > 0, tint.a > 0 else { return }
        let glyphRect = Rect(origin: topLeft, size: Size(width: w, height: h))
        guard let clip = glyphRect.intersection(bandRect) else { return }
        precondition(glyphScratch.count >= w * h,
                     "glyph scratch too small — size it from Pane.glyphScratchSize")

        let scratch = UnsafeMutableBufferPointer(rebasing: glyphScratch[0..<(w * h)])
        do {
            var target = RenderTarget(pixels: scratch.mutableSpan, width: w, height: h, stride: w)
            try font.render(glyph, subpixelShift: subpixelShift, into: &target)
        }
        for fy in clip.minY..<clip.maxY {
            let sy = fy - topLeft.y
            for fx in clip.minX..<clip.maxX {
                let coverage = glyphScratch[sy * w + (fx - topLeft.x)]
                if coverage > 0 {
                    blendLocal(x: fx - bandRect.minX, y: fy - bandRect.minY,
                               color: tint, coverage: coverage)
                }
            }
        }
    }

    // MARK: Pixel plumbing

    /// Fills one row span in frame coordinates (already clipped in x).
    private mutating func fillRow(y fy: Int, x0: Int, x1: Int, color: Color) {
        let y = fy - bandRect.minY
        if color.isOpaque {
            var i = y * rowStride + (x0 - bandRect.minX) * 4
            for _ in x0..<x1 {
                pixels[i] = color.b
                pixels[i + 1] = color.g
                pixels[i + 2] = color.r
                pixels[i + 3] = 255
                i += 4
            }
        } else {
            for fx in x0..<x1 {
                blendLocal(x: fx - bandRect.minX, y: y, color: color, coverage: 255)
            }
        }
    }

    private mutating func blendSDF(fx: Int, fy: Int, rect: Rect, radius: Int, color: Color) {
        let d = Canvas.roundedDistance(fx: fx, fy: fy, rect: rect, radius: radius)
        let coverage = min(max(0.5 - d, 0), 1)
        if coverage > 0 {
            blendLocal(x: fx - bandRect.minX, y: fy - bandRect.minY, color: color,
                       coverage: UInt8((coverage * 255).rounded()))
        }
    }

    private mutating func strokeSDF(fx: Int, fy: Int, rect: Rect, radius: Int, width: Int,
                                    color: Color) {
        let d = Canvas.roundedDistance(fx: fx, fy: fy, rect: rect, radius: radius)
        let outer = min(max(0.5 - d, 0), 1)
        let inner = min(max(0.5 - (d + Double(width)), 0), 1)
        let coverage = outer - inner
        if coverage > 0 {
            blendLocal(x: fx - bandRect.minX, y: fy - bandRect.minY, color: color,
                       coverage: UInt8((coverage * 255).rounded()))
        }
    }

    /// Signed distance from the pixel center to the rounded rect's edge
    /// (negative inside).
    private static func roundedDistance(fx: Int, fy: Int, rect: Rect, radius: Int) -> Double {
        let r = Double(radius)
        let hw = Double(rect.size.width) / 2
        let hh = Double(rect.size.height) / 2
        let px = Double(fx) + 0.5 - (Double(rect.minX) + hw)
        let py = Double(fy) + 0.5 - (Double(rect.minY) + hh)
        let qx = abs(px) - (hw - r)
        let qy = abs(py) - (hh - r)
        let ax = max(qx, 0)
        let ay = max(qy, 0)
        return (ax * ax + ay * ay).squareRoot() + min(max(qx, qy), 0) - r
    }

    /// Source-over of `color` scaled by `coverage` at buffer-local
    /// (x, y). Callers guarantee the coordinates are in the band.
    @inline(__always)
    private mutating func blendLocal(x: Int, y: Int, color: Color, coverage: UInt8) {
        let i = y * rowStride + x * 4
        let alpha = Canvas.mul8(color.a, coverage)
        if alpha == 255 {
            pixels[i] = color.b
            pixels[i + 1] = color.g
            pixels[i + 2] = color.r
            pixels[i + 3] = 255
            return
        }
        if alpha == 0 { return }
        let inv = 255 - alpha
        pixels[i] = Canvas.mul8(color.b, alpha) &+ Canvas.mul8(pixels[i], inv)
        pixels[i + 1] = Canvas.mul8(color.g, alpha) &+ Canvas.mul8(pixels[i + 1], inv)
        pixels[i + 2] = Canvas.mul8(color.r, alpha) &+ Canvas.mul8(pixels[i + 2], inv)
        pixels[i + 3] = alpha &+ Canvas.mul8(pixels[i + 3], inv)
    }

    /// `(x * y) / 255` with rounding.
    @inline(__always)
    private static func mul8(_ x: UInt8, _ y: UInt8) -> UInt8 {
        UInt8((Int(x) * Int(y) + 127) / 255)
    }
}
