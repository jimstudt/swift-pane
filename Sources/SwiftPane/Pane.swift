/// The top-level dashboard: a root ``Element`` bound to a frame size,
/// owning the layout-once / render-per-band loop.
///
/// ```swift
/// var pane = Pane(size: Size(width: 320, height: 240),
///                 root: Column(spacing: 4, title, gaugeRow))
/// pane.layout(env)
/// for band in bands {
///     var canvas = Canvas(pixels: bandPixels, bandRect: band,
///                         glyphScratch: scratch)
///     pane.render(into: &canvas, env)
/// }
/// ```
///
/// A pane is built, laid out, rendered, and discarded each frame —
/// it borrows its labels' text, and the `~Escapable` types hold it to
/// that lifecycle.
public struct Pane<Root: Element & ~Escapable>: ~Escapable {
    /// The element tree.
    public var root: Root
    /// The frame size; ``layout(_:)`` hands it to ``root`` as tight
    /// constraints.
    public let size: Size
    /// The glyph scratch bytes rendering this pane needs — the largest
    /// single-glyph bitmap any of its text can produce, gathered from
    /// the tree (``Element/glyphScratchSize(_:)``) during ``layout(_:)``.
    /// Zero before the first layout, and for panes with no text. Size
    /// the ``Canvas``'s scratch buffer from this; it holds still
    /// across every band of every render until the fonts or text
    /// sizes in the environment change.
    public private(set) var glyphScratchSize = 0

    @_lifetime(copy root)
    /// Binds an element tree to a frame size.
    public init(size: Size, root: consuming Root) {
        self.size = size
        self.root = root
    }

    /// Runs the layout pass: the root gets the frame size as tight
    /// constraints, and ``glyphScratchSize`` is gathered. Call once
    /// per frame, before any rendering.
    public mutating func layout(_ env: borrowing Environment) {
        _ = root.layout(in: .tight(size), env)
        glyphScratchSize = root.glyphScratchSize(env)
    }

    /// Renders into one canvas — a whole frame or any band of it.
    /// Requires ``layout(_:)`` to have run; call once per band.
    public borrowing func render(into canvas: inout Canvas, _ env: borrowing Environment) {
        root.render(into: &canvas, at: .zero, env)
    }
}
