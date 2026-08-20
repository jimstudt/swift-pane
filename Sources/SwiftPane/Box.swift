/// A rectangle — filled, bordered, or both, with optional rounded
/// corners — optionally decorating a child.
///
/// With a child, the box hugs it (plus `padding`). Without one, it
/// expands to the available space, which is what a gauge bar inside a
/// ``SizedBox`` wants:
///
/// ```swift
/// SizedBox(width: barWidth, height: 10,
///          Box(fill: barColor, cornerRadius: 5))
/// ```
public struct Box<Child: Element & ~Escapable>: Element, ~Escapable {
    /// The interior color; `nil` fills nothing.
    public var fill: Color?
    /// The border color; `nil` strokes nothing.
    public var border: Color?
    /// Border thickness in pixels, drawn just inside the box's edge.
    public var borderWidth: Int
    /// Corner radius in pixels; 0 is a square-cornered rectangle.
    public var cornerRadius: Int
    /// Space between the box's edge and its child.
    public var padding: EdgeInsets
    var child: Child
    let expands: Bool
    var cachedSize = Size.zero

    @_lifetime(copy child)
    /// A box decorating `child`: the box hugs the child plus `padding`.
    public init(fill: Color? = nil, border: Color? = nil, borderWidth: Int = 1,
                cornerRadius: Int = 0, padding: EdgeInsets = .zero,
                _ child: consuming Child) {
        self.fill = fill
        self.border = border
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.child = child
        self.expands = false
    }

    @_lifetime(immortal)
    public init(fill: Color? = nil, border: Color? = nil, borderWidth: Int = 1,
                cornerRadius: Int = 0) where Child == EmptyElement {
        self.fill = fill
        self.border = border
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
        self.padding = .zero
        self.child = EmptyElement()
        self.expands = true
    }

    public mutating func layout(in constraints: Constraints,
                                _ env: borrowing Environment) -> Size {
        if expands {
            _ = child.layout(in: constraints.loosened(), env)
            cachedSize = Size(
                width: constraints.hasBoundedWidth ? constraints.maxWidth : constraints.minWidth,
                height: constraints.hasBoundedHeight ? constraints.maxHeight : constraints.minHeight)
        } else {
            let s = child.layout(in: constraints.deflated(by: padding), env)
            cachedSize = constraints.constrain(Size(width: s.width + padding.horizontal,
                                                    height: s.height + padding.vertical))
        }
        return cachedSize
    }

    public borrowing func render(into canvas: inout Canvas, at origin: Point,
                                 _ env: borrowing Environment) {
        let rect = Rect(origin: origin, size: cachedSize)
        if let fill {
            canvas.fillRounded(rect, cornerRadius: cornerRadius, color: fill)
        }
        if let border {
            canvas.strokeRounded(rect, cornerRadius: cornerRadius, width: borderWidth,
                                 color: border)
        }
        if !expands {
            child.render(into: &canvas,
                         at: origin + Point(x: padding.leading, y: padding.top), env)
        }
    }

    public func glyphScratchSize(_ env: borrowing Environment) -> Int {
        child.glyphScratchSize(env)
    }
}
