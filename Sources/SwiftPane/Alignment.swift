/// Horizontal placement, as used by ``Label`` and ``Alignment``.
public enum HorizontalAlignment: Sendable, Equatable {
    /// `leading`: at the left edge (LTR); `center`: centered;
    /// `trailing`: at the right edge.
    case leading, center, trailing

    /// Offset of a `content`-wide thing inside a `container`-wide
    /// frame (negative when the content overflows).
    func offset(content: Int, in container: Int) -> Int {
        switch self {
        case .leading: 0
        case .center: (container - content) / 2
        case .trailing: container - content
        }
    }
}

/// Vertical placement.
public enum VerticalAlignment: Sendable, Equatable {
    /// `top`: at the top edge; `center`: centered; `bottom`: at the
    /// bottom edge.
    case top, center, bottom

    func offset(content: Int, in container: Int) -> Int {
        switch self {
        case .top: 0
        case .center: (container - content) / 2
        case .bottom: container - content
        }
    }
}

/// A two-axis placement, as used by ``Align`` and ``Overlay``.
public struct Alignment: Sendable, Equatable {
    /// Placement along the x axis.
    public var horizontal: HorizontalAlignment
    /// Placement along the y axis.
    public var vertical: VerticalAlignment

    public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    public static let topLeading = Alignment(horizontal: .leading, vertical: .top)
    public static let top = Alignment(horizontal: .center, vertical: .top)
    public static let topTrailing = Alignment(horizontal: .trailing, vertical: .top)
    public static let leading = Alignment(horizontal: .leading, vertical: .center)
    public static let center = Alignment(horizontal: .center, vertical: .center)
    public static let trailing = Alignment(horizontal: .trailing, vertical: .center)
    public static let bottomLeading = Alignment(horizontal: .leading, vertical: .bottom)
    public static let bottom = Alignment(horizontal: .center, vertical: .bottom)
    public static let bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)

    /// Top-left offset of a `content`-sized thing in a `container`.
    func offset(content: Size, in container: Size) -> Point {
        Point(x: horizontal.offset(content: content.width, in: container.width),
              y: vertical.offset(content: content.height, in: container.height))
    }
}

/// Cross-axis placement of children in a ``Row`` or ``Column``.
public enum CrossAlignment: Sendable, Equatable {
    /// Children keep their own cross size, packed to the start
    /// (top of a `Row`, leading edge of a `Column`).
    case start
    /// Children are centered across the axis.
    case center
    /// Children are packed to the end (bottom of a `Row`, trailing
    /// edge of a `Column`).
    case end
    /// Children are forced to the container's full cross extent
    /// (when it is bounded).
    case stretch
}
