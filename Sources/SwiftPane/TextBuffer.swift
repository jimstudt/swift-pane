/// Fixed-capacity, allocation-free UTF-8 text assembly — the place a
/// dashboard formats its readings before handing them to ``Label``.
///
/// ```swift
/// var line = TextBuffer<32>()
/// line.append(rpm, width: 5)          // "  963"
/// line.append(" rpm")
/// var temp = TextBuffer<16>()
/// temp.append(celsius, decimals: 1)   // "78.4"
/// temp.append("°C")
/// ```
///
/// Formatting is printf-shaped: `width` right-aligns within a field,
/// space-padded by default (`pad: "0"` zero-pads after the sign). A
/// value wider than `width` writes in full — broken alignment beats a
/// silently corrupted reading. A value that doesn't fit the buffer's
/// remaining capacity writes *nothing* and sets the sticky
/// ``overflowed`` flag, so an undersized `N` shows up as visibly
/// missing text rather than a trap in the field.
public struct TextBuffer<let N: Int> {
    @usableFromInline
    var storage: InlineArray<N, UInt8>
    /// Bytes currently used.
    public private(set) var count: Int
    /// True once any append has been dropped for lack of space.
    public private(set) var overflowed: Bool

    public init() {
        storage = InlineArray(repeating: 0)
        count = 0
        overflowed = false
    }

    public var isEmpty: Bool { count == 0 }
    public var capacity: Int { N }

    public mutating func clear() {
        count = 0
        overflowed = false
    }

    /// The assembled text, borrowed from the buffer.
    public var span: UTF8Span {
        @_lifetime(borrow self)
        borrowing get {
            let bytes = storage.span.extracting(0..<count)
            // Appends only ever add whole, valid scalars.
            return try! UTF8Span(validating: bytes)
        }
    }

    /// Appends literal text.
    public mutating func append(_ text: StaticString) {
        text.withUTF8Buffer { bytes in
            guard count + bytes.count <= N else {
                overflowed = true
                return
            }
            for byte in bytes {
                storage[count] = byte
                count += 1
            }
        }
    }

    /// Appends an integer, right-aligned in a field of `width`
    /// (0 = natural width). `pad` must be a single ASCII scalar;
    /// `"0"` zero-pads after the sign.
    public mutating func append(_ value: Int, width: Int = 0, pad: Unicode.Scalar = " ") {
        var tmp = InlineArray<24, UInt8>(repeating: 0)
        var n = 0
        var magnitude = UInt(value.magnitude)
        repeat {
            tmp[n] = UInt8(ascii: "0") + UInt8(magnitude % 10)
            n += 1
            magnitude /= 10
        } while magnitude > 0
        if value < 0 {
            tmp[n] = UInt8(ascii: "-")
            n += 1
        }
        // tmp holds the text reversed; commit un-reverses.
        commitReversed(tmp, length: n, width: width, pad: pad)
    }

    /// Appends a fixed-point decimal, right-aligned in a field of
    /// `width`. `decimals` is clamped to `0...9`. Non-finite or
    /// astronomically large values render as `#` fill.
    public mutating func append(_ value: Double, decimals: Int, width: Int = 0,
                                pad: Unicode.Scalar = " ") {
        let places = min(max(decimals, 0), 9)
        guard value.isFinite, value.magnitude < 1e15 else {
            let fill = InlineArray<24, UInt8>(repeating: UInt8(ascii: "#"))
            commitReversed(fill, length: min(max(width, 3), 24), width: width, pad: " ")
            return
        }
        var power: UInt64 = 1
        for _ in 0..<places { power *= 10 }
        let scaled = UInt64((value.magnitude * Double(power)).rounded())
        var tmp = InlineArray<24, UInt8>(repeating: 0)
        var n = 0
        if places > 0 {
            var frac = scaled % power
            for _ in 0..<places {
                tmp[n] = UInt8(ascii: "0") + UInt8(frac % 10)
                n += 1
                frac /= 10
            }
            tmp[n] = UInt8(ascii: ".")
            n += 1
        }
        var whole = scaled / power
        repeat {
            tmp[n] = UInt8(ascii: "0") + UInt8(whole % 10)
            n += 1
            whole /= 10
        } while whole > 0
        if value < 0 && scaled > 0 {
            tmp[n] = UInt8(ascii: "-")
            n += 1
        }
        commitReversed(tmp, length: n, width: width, pad: pad)
    }

    /// Writes reversed ASCII `tmp[0..<length]` into storage in reading
    /// order, right-aligned in `width` — or drops it whole on overflow.
    private mutating func commitReversed(_ tmp: InlineArray<24, UInt8>, length: Int,
                                         width: Int, pad: Unicode.Scalar) {
        precondition(pad.isASCII, "pad must be a single ASCII scalar")
        let padByte = UInt8(pad.value)
        let padCount = max(0, width - length)
        guard count + padCount + length <= N else {
            overflowed = true
            return
        }
        let zeroPadded = padByte == UInt8(ascii: "0")
        let negative = length > 0 && tmp[length - 1] == UInt8(ascii: "-")
        if zeroPadded && negative {
            // Sign leads the zeros: "-0012.5", not "00-12.5".
            storage[count] = UInt8(ascii: "-")
            count += 1
            for _ in 0..<padCount {
                storage[count] = padByte
                count += 1
            }
            for i in stride(from: length - 2, through: 0, by: -1) {
                storage[count] = tmp[i]
                count += 1
            }
        } else {
            for _ in 0..<padCount {
                storage[count] = padByte
                count += 1
            }
            for i in stride(from: length - 1, through: 0, by: -1) {
                storage[count] = tmp[i]
                count += 1
            }
        }
    }
}
