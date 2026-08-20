/// Single-child layout adapters: ``Padding``, ``Align``, ``SizedBox``,
/// ``Flexible`` — and the childless ``Spacer``.

/// Insets its child on all four sides.
public struct Padding<Child: Element & ~Escapable>: Element, ~Escapable {
    /// The space added around the child.
    public var insets: EdgeInsets
    var child: Child

    @_lifetime(copy child)
    /// Insets `child` by `insets`.
    public init(_ insets: EdgeInsets, _ child: consuming Child) {
        self.insets = insets
        self.child = child
    }

    @_lifetime(copy child)
    /// Insets `child` by `all` on every edge.
    public init(_ all: Int, _ child: consuming Child) {
        self.init(EdgeInsets(all), child)
    }

    public mutating func layout(in constraints: Constraints,
                                _ env: borrowing Environment) -> Size {
        let s = child.layout(in: constraints.deflated(by: insets), env)
        return constraints.constrain(Size(width: s.width + insets.horizontal,
                                          height: s.height + insets.vertical))
    }

    public borrowing func render(into canvas: inout Canvas, at origin: Point,
                                 _ env: borrowing Environment) {
        child.render(into: &canvas, at: origin + Point(x: insets.leading, y: insets.top), env)
    }

    public func glyphScratchSize(_ env: borrowing Environment) -> Int {
        child.glyphScratchSize(env)
    }
}

/// Fills the available space (on bounded axes) and places its child
/// within by alignment. The standard way to center something.
public struct Align<Child: Element & ~Escapable>: Element, ~Escapable {
    /// Where the child sits in the claimed space.
    public var alignment: Alignment
    var child: Child
    var childOffset = Point.zero

    @_lifetime(copy child)
    /// Places `child` by `alignment` within the available space.
    public init(_ alignment: Alignment, _ child: consuming Child) {
        self.alignment = alignment
        self.child = child
    }

    public mutating func layout(in constraints: Constraints,
                                _ env: borrowing Environment) -> Size {
        let s = child.layout(in: constraints.loosened(), env)
        let own = constraints.constrain(Size(
            width: constraints.hasBoundedWidth ? constraints.maxWidth : s.width,
            height: constraints.hasBoundedHeight ? constraints.maxHeight : s.height))
        childOffset = alignment.offset(content: s, in: own)
        return own
    }

    public borrowing func render(into canvas: inout Canvas, at origin: Point,
                                 _ env: borrowing Environment) {
        child.render(into: &canvas, at: origin + childOffset, env)
    }

    public func glyphScratchSize(_ env: borrowing Environment) -> Int {
        child.glyphScratchSize(env)
    }
}

/// Forces one or both axes to a fixed extent (clamped into the
/// incoming constraints). Without a child it is a rigid blank —
/// a fixed gap, or the frame for an expanding ``Box``.
public struct SizedBox<Child: Element & ~Escapable>: Element, ~Escapable {
    /// The forced width, or `nil` to leave the axis to the child.
    public var width: Int?
    /// The forced height, or `nil` to leave the axis to the child.
    public var height: Int?
    var child: Child

    @_lifetime(copy child)
    /// Forces `child` to the given extents (tight constraints).
    public init(width: Int? = nil, height: Int? = nil, _ child: consuming Child) {
        self.width = width
        self.height = height
        self.child = child
    }

    @_lifetime(immortal)
    /// A rigid blank of the given extents.
    public init(width: Int? = nil, height: Int? = nil) where Child == EmptyElement {
        self.init(width: width, height: height, EmptyElement())
    }

    public mutating func layout(in constraints: Constraints,
                                _ env: borrowing Environment) -> Size {
        let c = constraints.tightened(width: width, height: height)
        return c.constrain(child.layout(in: c, env))
    }

    public borrowing func render(into canvas: inout Canvas, at origin: Point,
                                 _ env: borrowing Environment) {
        child.render(into: &canvas, at: origin, env)
    }

    public func glyphScratchSize(_ env: borrowing Environment) -> Int {
        child.glyphScratchSize(env)
    }
}

/// Greedy blank space inside a ``Row`` or ``Column``: takes `flex`
/// shares of whatever main-axis space content didn't use.
public struct Spacer: Element {
    public let flexFactor: Int

    /// A spacer taking `flex` shares of leftover space.
    public init(flex: Int = 1) {
        precondition(flex > 0, "a spacer's flex must be positive")
        self.flexFactor = flex
    }

    public mutating func layout(in constraints: Constraints,
                                _ env: borrowing Environment) -> Size {
        Size(width: constraints.minWidth, height: constraints.minHeight)
    }

    public borrowing func render(into canvas: inout Canvas, at origin: Point,
                                 _ env: borrowing Environment) {}
}

/// Gives its child a flex share of a stack's main axis. The child is
/// laid out with the share as a tight main-axis constraint.
public struct Flexible<Child: Element & ~Escapable>: Element, ~Escapable {
    public let flexFactor: Int
    var child: Child

    @_lifetime(copy child)
    /// Gives `child` `flex` shares of the stack's main axis.
    public init(flex: Int = 1, _ child: consuming Child) {
        precondition(flex > 0, "flex must be positive")
        self.flexFactor = flex
        self.child = child
    }

    public mutating func layout(in constraints: Constraints,
                                _ env: borrowing Environment) -> Size {
        child.layout(in: constraints, env)
    }

    public borrowing func render(into canvas: inout Canvas, at origin: Point,
                                 _ env: borrowing Environment) {
        child.render(into: &canvas, at: origin, env)
    }

    public func glyphScratchSize(_ env: borrowing Environment) -> Int {
        child.glyphScratchSize(env)
    }
}
