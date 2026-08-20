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
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    public static let zero = Point(x: 0, y: 0)

    public static func + (l: Point, r: Point) -> Point {
        Point(x: l.x + r.x, y: l.y + r.y)
    }
}

/// A width and height in pixels. Negative values are never meaningful.
public struct Size: Sendable, Equatable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public static let zero = Size(width: 0, height: 0)
}

/// An axis-aligned rectangle in pixels.
public struct Rect: Sendable, Equatable {
    public var origin: Point
    public var size: Size

    public init(origin: Point, size: Size) {
        self.origin = origin
        self.size = size
    }

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.origin = Point(x: x, y: y)
        self.size = Size(width: width, height: height)
    }

    public static let zero = Rect(origin: .zero, size: .zero)

    public var minX: Int { origin.x }
    public var minY: Int { origin.y }
    public var maxX: Int { origin.x + size.width }
    public var maxY: Int { origin.y + size.height }
    public var isEmpty: Bool { size.width <= 0 || size.height <= 0 }

    public func offset(by p: Point) -> Rect {
        Rect(origin: origin + p, size: size)
    }

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
    public var top: Int
    public var leading: Int
    public var bottom: Int
    public var trailing: Int

    public init(top: Int, leading: Int, bottom: Int, trailing: Int) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public init(_ all: Int) {
        self.init(top: all, leading: all, bottom: all, trailing: all)
    }

    public init(horizontal: Int = 0, vertical: Int = 0) {
        self.init(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
    }

    public static let zero = EdgeInsets(0)

    public var horizontal: Int { leading + trailing }
    public var vertical: Int { top + bottom }
}

/// The box-layout contract: constraints go down, sizes come up.
///
/// A parent hands each child a `Constraints`; the child must answer
/// with a ``Size`` inside it (which ``constrain(_:)`` guarantees).
/// `Int.max` as a maximum means unbounded on that axis; arithmetic
/// helpers here are careful to keep the sentinel from overflowing.
public struct Constraints: Sendable, Equatable {
    public var minWidth: Int
    public var maxWidth: Int
    public var minHeight: Int
    public var maxHeight: Int

    /// A maximum meaning "no limit on this axis".
    public static let unbounded = Int.max

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

    public var hasBoundedWidth: Bool { maxWidth != Constraints.unbounded }
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
