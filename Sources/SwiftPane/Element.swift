/// One node in a pane's tree of visual objects.
///
/// The layout contract is Flutter's: constraints go down, sizes come
/// up, the parent assigns positions. `layout` is `mutating` because an
/// element caches whatever `render` will need — its own size, its
/// children's frames — inline in the node; there is no separate render
/// tree. `render` is `borrowing` and repeatable: banded rendering
/// calls it once per band with a canvas windowed to that band, and the
/// cached layout holds still across the calls.
///
/// Elements are `~Escapable` because text nodes borrow their bytes
/// (``Label`` stores a `UTF8Span`). A tree is built, laid out,
/// rendered, and discarded within the frame — the type system enforces
/// what the design wants anyway.
public protocol Element: ~Escapable {
    /// Measures the element under `constraints` and caches what
    /// ``render(into:at:_:)`` needs. Returns a size satisfying the
    /// constraints.
    mutating func layout(in constraints: Constraints, _ env: borrowing Environment) -> Size

    /// Draws the element with its top-left corner at `origin` (frame
    /// coordinates). Must only be called after `layout`.
    borrowing func render(into canvas: inout Canvas, at origin: Point, _ env: borrowing Environment)

    /// This element's share of leftover main-axis space inside a
    /// ``Row`` or ``Column``; 0 (the default) means "sized to content".
    var flexFactor: Int { get }

    /// The glyph scratch bytes this element's subtree needs to render
    /// with the given environment — the largest single-glyph bitmap
    /// any of its text can produce (``Label`` computes it in O(1) from
    /// the font; containers take the max over children; everything
    /// else reports 0, the default). ``Pane`` gathers this once per
    /// layout, not per render.
    func glyphScratchSize(_ env: borrowing Environment) -> Int
}

extension Element where Self: ~Escapable {
    public var flexFactor: Int { 0 }

    public func glyphScratchSize(_ env: borrowing Environment) -> Int { 0 }
}

/// The nothing element: occupies the constraints' minimum, draws
/// nothing. The default child of ``Box`` and ``SizedBox``.
public struct EmptyElement: Element {
    /// Creates the nothing element.
    public init() {}

    public mutating func layout(in constraints: Constraints, _ env: borrowing Environment) -> Size {
        Size(width: constraints.minWidth, height: constraints.minHeight)
    }

    public borrowing func render(into canvas: inout Canvas, at origin: Point,
                                 _ env: borrowing Environment) {}
}
