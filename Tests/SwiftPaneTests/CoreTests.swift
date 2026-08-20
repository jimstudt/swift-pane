import Testing
@testable import SwiftPane

private func text<let N: Int>(_ buffer: borrowing TextBuffer<N>) -> String {
    let span = buffer.span.span
    var bytes: [UInt8] = []
    for i in 0..<span.count {
        bytes.append(span[i])
    }
    return String(decoding: bytes, as: UTF8.self)
}

struct ColorTests {
    @Test func hslPrimaries() {
        #expect(Color(hue: 0, saturation: 1, lightness: 0.5) == Color(r: 255, g: 0, b: 0))
        #expect(Color(hue: 1.0 / 3, saturation: 1, lightness: 0.5) == Color(r: 0, g: 255, b: 0))
        #expect(Color(hue: 2.0 / 3, saturation: 1, lightness: 0.5) == Color(r: 0, g: 0, b: 255))
        #expect(Color(hue: 0.5, saturation: 0, lightness: 1) == .white)
    }

    @Test func blending() {
        let translucentWhite = Color(r: 255, g: 255, b: 255, a: 128)
        let onBlack = translucentWhite.over(.black)
        #expect(onBlack.a == 255)
        #expect(abs(Int(onBlack.r) - 128) <= 1)

        let mid = Color.black.mixed(with: .white, amount: 0.5)
        #expect(abs(Int(mid.g) - 128) <= 1)
        #expect(Color.black.mixed(with: .white, amount: 0) == .black)
        #expect(Color.black.mixed(with: .white, amount: 1) == .white)
    }
}

struct ConstraintsTests {
    @Test func constrainAndDeflate() {
        let c = Constraints(minWidth: 10, maxWidth: 100, minHeight: 5, maxHeight: 50)
        #expect(c.constrain(Size(width: 200, height: 1)) == Size(width: 100, height: 5))
        #expect(c.constrain(Size(width: 50, height: 20)) == Size(width: 50, height: 20))

        let d = c.deflated(by: EdgeInsets(4))
        #expect(d.maxWidth == 92)
        #expect(d.maxHeight == 42)
        #expect(d.minWidth == 2)

        let unbounded = Constraints().deflated(by: EdgeInsets(100))
        #expect(unbounded.maxWidth == Constraints.unbounded)

        let tight = Constraints.tight(Size(width: 30, height: 30)).tightened(width: 99)
        #expect(tight.minWidth == 30 && tight.maxWidth == 30)
    }
}

struct TextBufferTests {
    @Test func integers() {
        var b = TextBuffer<32>()
        b.append(42, width: 5)
        b.append("|")
        b.append(-7, width: 4, pad: "0")
        b.append("|")
        b.append(123)
        #expect(text(b) == "   42|-007|123")
        #expect(!b.overflowed)
    }

    @Test func doubles() {
        var b = TextBuffer<40>()
        b.append(3.14159, decimals: 2)
        b.append("|")
        b.append(-0.5, decimals: 1)
        b.append("|")
        b.append(2.5, decimals: 0)
        b.append("|")
        b.append(78.46, decimals: 1, width: 7)
        #expect(text(b) == "3.14|-0.5|3|   78.5")
    }

    @Test func nonFinite() {
        var b = TextBuffer<16>()
        b.append(Double.infinity, decimals: 1, width: 5)
        #expect(text(b) == "#####")
    }

    @Test func multibyte() {
        var b = TextBuffer<16>()
        b.append(21.5, decimals: 1)
        b.append("°C")
        #expect(text(b) == "21.5°C")
    }

    @Test func overflowIsStickyAndAtomic() {
        var b = TextBuffer<4>()
        b.append("hello")
        #expect(b.overflowed)
        #expect(b.isEmpty)

        var c = TextBuffer<4>()
        c.append("hi")
        c.append(1000)
        #expect(c.overflowed)
        #expect(text(c) == "hi")  // the failed append wrote nothing

        c.clear()
        #expect(!c.overflowed && c.isEmpty)
    }
}
