/// An 8-bit RGBA color with straight (non-premultiplied) alpha.
///
/// Storage is logical `r, g, b, a` regardless of the framebuffer's
/// byte order — ``Canvas`` swizzles to BGRA8888 on store. Blending
/// helpers here are conveniences for *computing* colors (hover
/// states, gauge gradients); the per-pixel hot path in ``Canvas``
/// uses its own integer arithmetic.
public struct Color: Sendable, Equatable {
    /// Red, `0...255`.
    public var r: UInt8
    /// Green, `0...255`.
    public var g: UInt8
    /// Blue, `0...255`.
    public var b: UInt8
    /// Straight (non-premultiplied) alpha; 255 is opaque.
    public var a: UInt8

    /// Component-wise RGBA; alpha defaults to opaque.
    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// A gray level, components in `0...1`.
    public init(white: Float, alpha: Float = 1) {
        let w = Color.unit(white)
        self.init(r: w, g: w, b: w, a: Color.unit(alpha))
    }

    /// HSL, all components in `0...1` (hue wraps).
    public init(hue: Float, saturation: Float, lightness: Float, alpha: Float = 1) {
        let h = hue - hue.rounded(.down)  // wrap into 0..<1
        let s = min(max(saturation, 0), 1)
        let l = min(max(lightness, 0), 1)
        let c = (1 - abs(2 * l - 1)) * s
        let hp = h * 6
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Float, Float, Float)
        switch hp {
        case ..<1: (r1, g1, b1) = (c, x, 0)
        case ..<2: (r1, g1, b1) = (x, c, 0)
        case ..<3: (r1, g1, b1) = (0, c, x)
        case ..<4: (r1, g1, b1) = (0, x, c)
        case ..<5: (r1, g1, b1) = (x, 0, c)
        default:   (r1, g1, b1) = (c, 0, x)
        }
        let m = l - c / 2
        self.init(r: Color.unit(r1 + m), g: Color.unit(g1 + m), b: Color.unit(b1 + m),
                  a: Color.unit(alpha))
    }

    /// Fully transparent.
    public static let clear = Color(r: 0, g: 0, b: 0, a: 0)
    /// Opaque black.
    public static let black = Color(r: 0, g: 0, b: 0)
    /// Opaque white.
    public static let white = Color(r: 255, g: 255, b: 255)

    /// True when compositing this color fully covers what's beneath.
    public var isOpaque: Bool { a == 255 }

    /// Source-over: `self` composited onto `dst`.
    public func over(_ dst: Color) -> Color {
        let sa = Float(a) / 255
        let da = Float(dst.a) / 255
        let oa = sa + da * (1 - sa)
        guard oa > 0 else { return .clear }
        func ch(_ s: UInt8, _ d: UInt8) -> UInt8 {
            let v = (Float(s) * sa + Float(d) * da * (1 - sa)) / oa
            return UInt8((v + 0.5).rounded(.down))
        }
        return Color(r: ch(r, dst.r), g: ch(g, dst.g), b: ch(b, dst.b),
                     a: Color.unit(oa))
    }

    /// Linear interpolation toward `other` in RGBA;
    /// `amount` 0 is `self`, 1 is `other`.
    public func mixed(with other: Color, amount: Float) -> Color {
        let t = min(max(amount, 0), 1)
        func ch(_ x: UInt8, _ y: UInt8) -> UInt8 {
            UInt8((Float(x) + (Float(y) - Float(x)) * t + 0.5).rounded(.down))
        }
        return Color(r: ch(r, other.r), g: ch(g, other.g), b: ch(b, other.b), a: ch(a, other.a))
    }

    /// Clamps a `0...1` component to a byte.
    private static func unit(_ v: Float) -> UInt8 {
        UInt8((min(max(v, 0), 1) * 255 + 0.5).rounded(.down))
    }
}
