import SwiftGlyph

/// A single line of left-to-right text.
///
/// The text is a borrowed `UTF8Span` — a ``TextBuffer``'s ``TextBuffer/span``
/// for dynamic values, a stored `String`'s `utf8Span`, or a
/// `StaticString` literal via the convenience initializer. Font, size,
/// and color default to the ``Environment``'s values.
///
/// Sizing: the label reports its measured text size, pushed into the
/// constraints. When the constraints force it wider (a tight-width
/// ``SizedBox``, a stretched stack), `alignment` places the text
/// within the extra room. There is no clipping in v1 — text wider
/// than its frame paints past it.
///
/// Glyph fallback: unmapped scalars and glyphs whose data is corrupt
/// render as glyph 0, the font's tofu box.
public struct Label: Element, ~Escapable {
    public var text: UTF8Span
    public var font: FontRef?
    public var size: Double?
    public var color: Color?
    public var alignment: HorizontalAlignment
    var cachedSize = Size.zero
    var contentWidth = 0.0
    var ascent = 0.0

    @_lifetime(copy text)
    public init(_ text: UTF8Span, font: FontRef? = nil, size: Double? = nil,
                color: Color? = nil, alignment: HorizontalAlignment = .leading) {
        self.text = text
        self.font = font
        self.size = size
        self.color = color
        self.alignment = alignment
    }

    /// Static label text; the literal's storage is immortal, so this
    /// label (alone among labels) borrows nothing.
    @_lifetime(immortal)
    public init(_ text: StaticString, font: FontRef? = nil, size: Double? = nil,
                color: Color? = nil, alignment: HorizontalAlignment = .leading) {
        let bytes = UnsafeBufferPointer(start: text.utf8Start, count: text.utf8CodeUnitCount)
        let span = _overrideLifetime(try! UTF8Span(validating: Span(_unsafeElements: bytes)),
                                     copying: ())
        self.init(span, font: font, size: size, color: color, alignment: alignment)
    }

    public mutating func layout(in constraints: Constraints,
                                _ env: borrowing Environment) -> Size {
        let sized = env.sizedFont(font, size: size)
        let line = sized.metrics
        contentWidth = walkGlyphs(sized) { _, _, _ in }
        ascent = line.ascender
        let natural = Size(width: Int(contentWidth.rounded(.up)),
                           height: Int((line.ascender - line.descender).rounded(.up)))
        cachedSize = constraints.constrain(natural)
        return cachedSize
    }

    public borrowing func render(into canvas: inout Canvas, at origin: Point,
                                 _ env: borrowing Environment) {
        let sized = env.sizedFont(font, size: size)
        let tint = color ?? env.textColor
        let slack = Double(cachedSize.width) - contentWidth
        let startX: Double =
            switch alignment {
            case .leading: 0
            case .center: slack / 2
            case .trailing: slack
            }
        let baselineY = origin.y + Int(ascent.rounded())
        _ = walkGlyphs(sized) { glyph, metrics, penX in
            let left = Double(origin.x) + startX + penX + metrics.leftSideBearing
            let x = left.rounded(.down)
            let topLeft = Point(x: Int(x), y: baselineY - Int(metrics.yOffset))
            // Corrupt outline data: fall through to nothing — mapping
            // and metrics fallbacks above already caught the usual cases.
            try? canvas.drawGlyph(glyph, metrics: metrics, font: sized,
                                  subpixelShift: left - x, tint: tint, topLeft: topLeft)
        }
    }

    public func glyphScratchSize(_ env: borrowing Environment) -> Int {
        let bound = env.sizedFont(font, size: size).maximumBitmapSize
        return bound.width * bound.height
    }

    /// Walks the text's scalars as (glyph, metrics, pen x) — the shared
    /// engine of measuring and rendering — and returns the total
    /// advance. Unmapped or broken glyphs resolve to glyph 0.
    private func walkGlyphs(
        _ sized: SizedFont,
        _ body: (GlyphID, GlyphMetrics, Double) -> Void
    ) -> Double {
        let tofu = GlyphID(rawValue: 0)
        var pen = 0.0
        var previous: GlyphID? = nil
        var iterator = text.makeUnicodeScalarIterator()
        while let scalar = iterator.next() {
            var glyph = sized.font.glyphID(for: scalar) ?? tofu
            var metrics = (try? sized.metrics(of: glyph)) ?? .init(
                advanceWidth: 0, leftSideBearing: 0, yOffset: 0,
                bitmapWidth: 0, bitmapHeight: 0)
            if metrics.bitmapWidth == 0 && metrics.advanceWidth == 0 && glyph != tofu {
                glyph = tofu
                metrics = (try? sized.metrics(of: tofu)) ?? metrics
            }
            if let previous {
                pen += sized.kerning(between: previous, and: glyph)
            }
            body(glyph, metrics, pen)
            pen += metrics.advanceWidth
            previous = glyph
        }
        return pen
    }
}
