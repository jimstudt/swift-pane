/// ``Row`` and ``Column``: main-axis stacks with spacing, cross-axis
/// alignment, and flex distribution — plus ``Overlay`` for z-stacking.
///
/// Layout follows the flex model: children with ``Element/flexFactor``
/// zero are sized to content first, then leftover main-axis space is
/// divided among flexed children (``Spacer``, ``Flexible``) in
/// proportion to their factors. With an unbounded main axis there is
/// no leftover, and flexed children collapse to their minimum.

enum Axis {
    case horizontal, vertical

    func main(_ s: Size) -> Int { self == .horizontal ? s.width : s.height }
    func cross(_ s: Size) -> Int { self == .horizontal ? s.height : s.width }

    func size(main: Int, cross: Int) -> Size {
        self == .horizontal ? Size(width: main, height: cross)
                            : Size(width: cross, height: main)
    }

    func point(main: Int, cross: Int) -> Point {
        self == .horizontal ? Point(x: main, y: cross) : Point(x: cross, y: main)
    }

    func mainMax(_ c: Constraints) -> Int { self == .horizontal ? c.maxWidth : c.maxHeight }
    func mainMin(_ c: Constraints) -> Int { self == .horizontal ? c.minWidth : c.minHeight }
    func crossMax(_ c: Constraints) -> Int { self == .horizontal ? c.maxHeight : c.maxWidth }
    func crossMin(_ c: Constraints) -> Int { self == .horizontal ? c.minHeight : c.minWidth }

    func constraints(mainMin: Int, mainMax: Int, crossMin: Int, crossMax: Int) -> Constraints {
        self == .horizontal
            ? Constraints(minWidth: mainMin, maxWidth: mainMax,
                          minHeight: crossMin, maxHeight: crossMax)
            : Constraints(minWidth: crossMin, maxWidth: crossMax,
                          minHeight: mainMin, maxHeight: mainMax)
    }
}

/// Shared Row/Column layout. Sizes every child, stores its frame
/// (container-relative) in `frames`, and returns the stack's size.
func layoutStack<L: ElementList & ~Escapable>(
    children: inout L, frames: inout InlineArray<8, Rect>,
    axis: Axis, spacing: Int, crossAlignment: CrossAlignment,
    in constraints: Constraints, _ env: borrowing Environment
) -> Size {
    let n = children.count
    precondition(n <= maxContainerChildren, "containers hold at most \(maxContainerChildren) children")
    guard n > 0 else { return constraints.constrain(.zero) }

    let mainMax = axis.mainMax(constraints)
    let crossMax = axis.crossMax(constraints)
    let boundedMain = mainMax != Constraints.unbounded
    let boundedCross = crossMax != Constraints.unbounded

    let childCrossMin = (crossAlignment == .stretch && boundedCross) ? crossMax : 0
    let spacingTotal = spacing * (n - 1)

    // Pass 1: content-sized children.
    var sizes = InlineArray<8, Size>(repeating: .zero)
    var fixedMain = 0
    var totalFlex = 0
    for i in 0..<n {
        let flex = children.childFlex(i)
        if flex > 0 {
            totalFlex += flex
        } else {
            let c = axis.constraints(mainMin: 0, mainMax: mainMax,
                                     crossMin: childCrossMin, crossMax: crossMax)
            let s = children.layoutChild(i, in: c, env)
            sizes[i] = s
            fixedMain += axis.main(s)
        }
    }

    // Pass 2: flexed children share the leftover.
    if totalFlex > 0 {
        let remaining = boundedMain ? max(0, mainMax - fixedMain - spacingTotal) : 0
        var distributed = 0
        var flexSeen = 0
        for i in 0..<n {
            let flex = children.childFlex(i)
            guard flex > 0 else { continue }
            flexSeen += flex
            // Cumulative rounding so the shares sum exactly to remaining.
            let share = remaining * flexSeen / totalFlex - distributed
            distributed += share
            let c = boundedMain
                ? axis.constraints(mainMin: share, mainMax: share,
                                   crossMin: childCrossMin, crossMax: crossMax)
                : axis.constraints(mainMin: 0, mainMax: Constraints.unbounded,
                                   crossMin: childCrossMin, crossMax: crossMax)
            sizes[i] = children.layoutChild(i, in: c, env)
        }
    }

    // Own size.
    var usedMain = spacingTotal
    var maxChildCross = 0
    for i in 0..<n {
        usedMain += axis.main(sizes[i])
        maxChildCross = max(maxChildCross, axis.cross(sizes[i]))
    }
    let ownSize = constraints.constrain(axis.size(main: usedMain, cross: maxChildCross))
    let ownCross = axis.cross(ownSize)

    // Positions.
    var pen = 0
    for i in 0..<n {
        let childCross = axis.cross(sizes[i])
        let crossOffset: Int =
            switch crossAlignment {
            case .start, .stretch: 0
            case .center: (ownCross - childCross) / 2
            case .end: ownCross - childCross
            }
        frames[i] = Rect(origin: axis.point(main: pen, cross: crossOffset), size: sizes[i])
        pen += axis.main(sizes[i]) + spacing
    }
    return ownSize
}

/// Renders stack/overlay children at their cached frames, skipping
/// those that miss the canvas's band.
func renderChildren<L: ElementList & ~Escapable>(
    _ children: borrowing L, frames: borrowing InlineArray<8, Rect>,
    into canvas: inout Canvas, at origin: Point, _ env: borrowing Environment
) {
    for i in 0..<children.count {
        let frame = frames[i].offset(by: origin)
        if frame.intersects(canvas.bandRect) {
            children.renderChild(i, into: &canvas, at: frame.origin, env)
        }
    }
}

/// A horizontal stack: children laid left to right.
public struct Row<Children: ElementList & ~Escapable>: Element, ~Escapable {
    /// Pixels between adjacent children on the main axis.
    public var spacing: Int
    /// How children sit across the axis.
    public var alignment: CrossAlignment
    var children: Children
    var frames: InlineArray<8, Rect>

    @_lifetime(copy children)
    /// The designated initializer; the arity overloads in
    /// ContainerInits.swift build `children` for you.
    public init(spacing: Int = 0, alignment: CrossAlignment = .start,
                children: consuming Children) {
        self.spacing = spacing
        self.alignment = alignment
        self.children = children
        self.frames = InlineArray(repeating: .zero)
    }

    public mutating func layout(in constraints: Constraints,
                                _ env: borrowing Environment) -> Size {
        layoutStack(children: &children, frames: &frames, axis: .horizontal,
                    spacing: spacing, crossAlignment: alignment,
                    in: constraints, env)
    }

    public borrowing func render(into canvas: inout Canvas, at origin: Point,
                                 _ env: borrowing Environment) {
        renderChildren(children, frames: frames, into: &canvas, at: origin, env)
    }

    public func glyphScratchSize(_ env: borrowing Environment) -> Int {
        children.maxGlyphScratchSize(env)
    }
}

/// A vertical stack: children laid top to bottom.
public struct Column<Children: ElementList & ~Escapable>: Element, ~Escapable {
    /// Pixels between adjacent children on the main axis.
    public var spacing: Int
    /// How children sit across the axis.
    public var alignment: CrossAlignment
    var children: Children
    var frames: InlineArray<8, Rect>

    @_lifetime(copy children)
    /// The designated initializer; the arity overloads in
    /// ContainerInits.swift build `children` for you.
    public init(spacing: Int = 0, alignment: CrossAlignment = .start,
                children: consuming Children) {
        self.spacing = spacing
        self.alignment = alignment
        self.children = children
        self.frames = InlineArray(repeating: .zero)
    }

    public mutating func layout(in constraints: Constraints,
                                _ env: borrowing Environment) -> Size {
        layoutStack(children: &children, frames: &frames, axis: .vertical,
                    spacing: spacing, crossAlignment: alignment,
                    in: constraints, env)
    }

    public borrowing func render(into canvas: inout Canvas, at origin: Point,
                                 _ env: borrowing Environment) {
        renderChildren(children, frames: frames, into: &canvas, at: origin, env)
    }

    public func glyphScratchSize(_ env: borrowing Environment) -> Int {
        children.maxGlyphScratchSize(env)
    }
}

/// A z-stack: children drawn in order (first is the bottom layer),
/// each placed by `alignment` within the overlay's bounds.
public struct Overlay<Children: ElementList & ~Escapable>: Element, ~Escapable {
    /// Where each child sits within the overlay's bounds.
    public var alignment: Alignment
    var children: Children
    var frames: InlineArray<8, Rect>

    @_lifetime(copy children)
    /// The designated initializer; the arity overloads in
    /// ContainerInits.swift build `children` for you.
    public init(alignment: Alignment = .topLeading, children: consuming Children) {
        self.alignment = alignment
        self.children = children
        self.frames = InlineArray(repeating: .zero)
    }

    public mutating func layout(in constraints: Constraints,
                                _ env: borrowing Environment) -> Size {
        let n = children.count
        precondition(n <= maxContainerChildren,
                     "containers hold at most \(maxContainerChildren) children")
        var maxSize = Size.zero
        for i in 0..<n {
            let s = children.layoutChild(i, in: constraints.loosened(), env)
            frames[i] = Rect(origin: .zero, size: s)
            maxSize.width = max(maxSize.width, s.width)
            maxSize.height = max(maxSize.height, s.height)
        }
        let own = constraints.constrain(maxSize)
        for i in 0..<n {
            frames[i].origin = alignment.offset(content: frames[i].size, in: own)
        }
        return own
    }

    public borrowing func render(into canvas: inout Canvas, at origin: Point,
                                 _ env: borrowing Environment) {
        renderChildren(children, frames: frames, into: &canvas, at: origin, env)
    }

    public func glyphScratchSize(_ env: borrowing Environment) -> Int {
        children.maxGlyphScratchSize(env)
    }
}
