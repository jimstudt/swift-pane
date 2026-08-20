/// A heterogeneous, statically-typed list of children — how ``Row``,
/// ``Column``, and ``Overlay`` hold elements of different types
/// without existentials or allocation.
///
/// The list is a cons chain of ``ElementPair`` ending in
/// ``EmptyList``, built for you by the containers' arity overloads
/// (see ContainerInits.swift). Indexed access recurses down the
/// chain; every arm statically dispatches, so the "loop" a container
/// runs over its children flattens out at compile time.
public protocol ElementList: ~Escapable {
    var count: Int { get }

    /// Lays out the child at `index` and returns its size.
    mutating func layoutChild(_ index: Int, in constraints: Constraints,
                              _ env: borrowing Environment) -> Size

    /// Renders the child at `index` with its top-left at `origin`.
    borrowing func renderChild(_ index: Int, into canvas: inout Canvas, at origin: Point,
                               _ env: borrowing Environment)

    /// The child's ``Element/flexFactor``.
    func childFlex(_ index: Int) -> Int

    /// The largest ``Element/glyphScratchSize(_:)`` in the list.
    func maxGlyphScratchSize(_ env: borrowing Environment) -> Int
}

/// The end of a child list.
public struct EmptyList: ElementList {
    public init() {}

    public var count: Int { 0 }

    public mutating func layoutChild(_ index: Int, in constraints: Constraints,
                                     _ env: borrowing Environment) -> Size {
        preconditionFailure("child index out of range")
    }

    public borrowing func renderChild(_ index: Int, into canvas: inout Canvas, at origin: Point,
                                      _ env: borrowing Environment) {
        preconditionFailure("child index out of range")
    }

    public func childFlex(_ index: Int) -> Int {
        preconditionFailure("child index out of range")
    }

    public func maxGlyphScratchSize(_ env: borrowing Environment) -> Int { 0 }
}

/// One link in a child list: a head element and the rest of the list.
public struct ElementPair<Head: Element & ~Escapable,
                          Tail: ElementList & ~Escapable>: ElementList, ~Escapable {
    public var head: Head
    public var tail: Tail

    @_lifetime(copy head, copy tail)
    public init(_ head: consuming Head, _ tail: consuming Tail) {
        self.head = head
        self.tail = tail
    }

    public var count: Int { 1 + tail.count }

    public mutating func layoutChild(_ index: Int, in constraints: Constraints,
                                     _ env: borrowing Environment) -> Size {
        index == 0
            ? head.layout(in: constraints, env)
            : tail.layoutChild(index - 1, in: constraints, env)
    }

    public borrowing func renderChild(_ index: Int, into canvas: inout Canvas, at origin: Point,
                                      _ env: borrowing Environment) {
        if index == 0 {
            head.render(into: &canvas, at: origin, env)
        } else {
            tail.renderChild(index - 1, into: &canvas, at: origin, env)
        }
    }

    public func childFlex(_ index: Int) -> Int {
        index == 0 ? head.flexFactor : tail.childFlex(index - 1)
    }

    public func maxGlyphScratchSize(_ env: borrowing Environment) -> Int {
        max(head.glyphScratchSize(env), tail.maxGlyphScratchSize(env))
    }
}

/// The most children a single ``Row``, ``Column``, or ``Overlay`` can
/// hold (nest containers for more) — the bound on their inline frame
/// storage.
public let maxContainerChildren = 8
