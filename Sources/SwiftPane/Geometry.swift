/// Integer pixel geometry.
///
/// Layout runs on whole pixels by design: rectangle edges and borders
/// land crisply on the pixel grid. The only fractional arithmetic in
/// the package is inside text measurement (glyph advances are
/// fractional; a label reports a rounded-up size) and the
/// anti-aliasing math for rounded corners, both contained in their
/// own corners of the code.

/// A position in pixels, y-down.
public struct Point: Sendable, Equatable {
    /// Horizontal position, increasing rightward.
    public var x: Int
    /// Vertical position, increasing downward.
    public var y: Int

    /// A point at (`x`, `y`).
    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    /// The origin, `(0, 0)`.
    public static let zero = Point(x: 0, y: 0)

    /// Component-wise translation.
    public static func + (l: Point, r: Point) -> Point {
        Point(x: l.x + r.x, y: l.y + r.y)
    }
}

/// A width and height in pixels. Negative values are never meaningful.
public struct Size: Sendable, Equatable {
    /// Horizontal extent.
    public var width: Int
    /// Vertical extent.
    public var height: Int

    /// A size of `width` × `height`.
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// The empty size, `0 × 0`.
    public static let zero = Size(width: 0, height: 0)
}

/// An axis-aligned rectangle in pixels.
public struct Rect: Sendable, Equatable {
    /// The top-left corner.
    public var origin: Point
    /// The extent from ``origin``, rightward and downward.
    public var size: Size

    /// A rect from its top-left corner and extent.
    public init(origin: Point, size: Size) {
        self.origin = origin
        self.size = size
    }

    /// A rect from edge coordinates and extents.
    public init(x: Int, y: Int, width: Int, height: Int) {
        self.origin = Point(x: x, y: y)
        self.size = Size(width: width, height: height)
    }

    /// The empty rectangle at the origin.
    public static let zero = Rect(origin: .zero, size: .zero)

    /// The left edge.
    public var minX: Int { origin.x }
    /// The top edge.
    public var minY: Int { origin.y }
    /// The right edge (exclusive: first column beyond the rect).
    public var maxX: Int { origin.x + size.width }
    /// The bottom edge (exclusive: first row beyond the rect).
    public var maxY: Int { origin.y + size.height }
    /// True when the rect covers no pixels.
    public var isEmpty: Bool { size.width <= 0 || size.height <= 0 }

    /// The same rect translated by `p`.
    public func offset(by p: Point) -> Rect {
        Rect(origin: origin + p, size: size)
    }

    /// True when the rects share at least one pixel.
    public func intersects(_ other: Rect) -> Bool {
        minX < other.maxX && other.minX < maxX
            && minY < other.maxY && other.minY < maxY
    }

    /// The overlapping region, or `nil` when the rects don't overlap.
    public func intersection(_ other: Rect) -> Rect? {
        let x0 = max(minX, other.minX)
        let y0 = max(minY, other.minY)
        let x1 = min(maxX, other.maxX)
        let y1 = min(maxY, other.maxY)
        guard x0 < x1, y0 < y1 else { return nil }
        return Rect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}

/// Per-edge spacing, as used by ``Padding`` and ``Box``.
public struct EdgeInsets: Sendable, Equatable {
    /// Inset from the top edge.
    public var top: Int
    /// Inset from the leading (left, in LTR) edge.
    public var leading: Int
    /// Inset from the bottom edge.
    public var bottom: Int
    /// Inset from the trailing (right, in LTR) edge.
    public var trailing: Int

    /// Per-edge insets.
    public init(top: Int, leading: Int, bottom: Int, trailing: Int) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    /// The same inset on all four edges.
    public init(_ all: Int) {
        self.init(top: all, leading: all, bottom: all, trailing: all)
    }

    /// Symmetric insets: `horizontal` on leading/trailing, `vertical`
    /// on top/bottom.
    public init(horizontal: Int = 0, vertical: Int = 0) {
        self.init(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
    }

    /// No insets.
    public static let zero = EdgeInsets(0)

    /// `leading + trailing` — the total width the insets consume.
    public var horizontal: Int { leading + trailing }
    /// `top + bottom` — the total height the insets consume.
    public var vertical: Int { top + bottom }
}

/// The box-layout contract: constraints go down, sizes come up.
///
/// A parent hands each child a `Constraints`; the child must answer
/// with a ``Size`` inside it (which ``constrain(_:)`` guarantees).
/// `Int.max` as a maximum means unbounded on that axis; arithmetic
/// helpers here are careful to keep the sentinel from overflowing.
public struct Constraints: Sendable, Equatable {
    /// The smallest acceptable width.
    public var minWidth: Int
    /// The largest acceptable width, or ``unbounded``.
    public var maxWidth: Int
    /// The smallest acceptable height.
    public var minHeight: Int
    /// The largest acceptable height, or ``unbounded``.
    public var maxHeight: Int

    /// A maximum meaning "no limit on this axis".
    public static let unbounded = Int.max

    /// Constraints from explicit bounds; omitted bounds don't constrain.
    public init(minWidth: Int = 0, maxWidth: Int = unbounded,
                minHeight: Int = 0, maxHeight: Int = unbounded) {
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.minHeight = minHeight
        self.maxHeight = maxHeight
    }

    /// Constraints that permit exactly one size.
    public static func tight(_ size: Size) -> Constraints {
        Constraints(minWidth: size.width, maxWidth: size.width,
                    minHeight: size.height, maxHeight: size.height)
    }

    /// Constraints from zero up to `size`.
    public static func loose(_ size: Size) -> Constraints {
        Constraints(maxWidth: size.width, maxHeight: size.height)
    }

    /// True when ``maxWidth`` is a real limit rather than ``unbounded``.
    public var hasBoundedWidth: Bool { maxWidth != Constraints.unbounded }
    /// True when ``maxHeight`` is a real limit rather than ``unbounded``.
    public var hasBoundedHeight: Bool { maxHeight != Constraints.unbounded }

    /// The nearest size to `size` that satisfies the constraints.
    public func constrain(_ size: Size) -> Size {
        Size(width: min(max(size.width, minWidth), maxWidth),
             height: min(max(size.height, minHeight), maxHeight))
    }

    /// The same maxima with the minima dropped to zero.
    public func loosened() -> Constraints {
        Constraints(maxWidth: maxWidth, maxHeight: maxHeight)
    }

    /// Constraints for a child inset by `insets` on all sides.
    /// Unbounded axes stay unbounded.
    public func deflated(by insets: EdgeInsets) -> Constraints {
        func shrink(_ v: Int, by amount: Int) -> Int {
            v == Constraints.unbounded ? v : max(0, v - amount)
        }
        return Constraints(
            minWidth: shrink(minWidth, by: insets.horizontal),
            maxWidth: shrink(maxWidth, by: insets.horizontal),
            minHeight: shrink(minHeight, by: insets.vertical),
            maxHeight: shrink(maxHeight, by: insets.vertical))
    }

    /// Overrides an axis with a tight extent where given, clamped into
    /// the incoming bounds so the result is still satisfiable.
    public func tightened(width: Int? = nil, height: Int? = nil) -> Constraints {
        var c = self
        if let width {
            let w = min(max(width, minWidth), maxWidth)
            c.minWidth = w
            c.maxWidth = w
        }
        if let height {
            let h = min(max(height, minHeight), maxHeight)
            c.minHeight = h
            c.maxHeight = h
        }
        return c
    }
}
