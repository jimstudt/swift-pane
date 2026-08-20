import SwiftGlyph

/// An index into the ``Environment``'s font table.
///
/// Register fonts once, in a fixed order, and name the slots:
///
/// ```swift
/// extension FontRef {
///     static let body = FontRef(0)
///     static let bold = FontRef(1)
/// }
/// ```
public struct FontRef: Sendable, Equatable {
    /// Position of the font in the environment's table.
    public var index: Int

    /// References the font at `index` in the environment's table.
    public init(_ index: Int) {
        self.index = index
    }
}

/// Inherited context flowing down the element tree: the font table
/// and the text defaults.
///
/// The environment is a small copyable value passed `borrowing` into
/// every layout and render call. An element that overrides a default
/// for its subtree copies the struct on its own stack frame, edits
/// the copy, and passes that down — no storage, no ARC.
public struct Environment: Copyable, ~Escapable {
    /// The registered fonts, borrowed from the caller for the frame.
    public let fonts: Span<Font>
    /// Default font for text elements that don't specify one.
    public var font: FontRef
    /// Default text pixel height.
    public var textSize: Double
    /// Default text color.
    public var textColor: Color

    /// Creates a frame's environment.
    ///
    /// - Parameters:
    ///   - fonts: The font table, borrowed for the frame; must not be
    ///     empty. ``FontRef`` values index into it.
    ///   - font: Default font for text that doesn't specify one.
    ///   - textSize: Default text pixel height.
    ///   - textColor: Default text color.
    @_lifetime(copy fonts)
    public init(fonts: consuming Span<Font>, font: FontRef = FontRef(0),
                textSize: Double = 16, textColor: Color = .black) {
        precondition(!fonts.isEmpty, "environment needs at least one font")
        self.fonts = fonts
        self.font = font
        self.textSize = textSize
        self.textColor = textColor
    }

    /// Resolves an element's (possibly absent) font and size against
    /// the defaults.
    public func sizedFont(_ ref: FontRef?, size: Double?) -> SizedFont {
        let index = (ref ?? font).index
        precondition(index >= 0 && index < fonts.count, "font index out of range")
        return fonts[index].sized(pixelHeight: size ?? textSize)
    }
}
