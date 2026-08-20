/// A trivial, allocation-free PNG encoder, plus ``Pane``'s render-to-PNG.
///
/// PNG's only codec is zlib/DEFLATE — there is no RLE mode — but a
/// fixed-Huffman deflate stream that encodes runs as LZ77 matches with
/// distance 4 (one BGRA pixel back) *is* run-length encoding, wearing
/// a deflate costume every decoder understands. Dashboard content —
/// flat fills, thin borders, sparse text — collapses well: runs of up
/// to 256 bytes cost ~3 bytes.
///
/// The encoder is sans-IO: the caller pumps BGRA rows in, and finished
/// byte pieces (chunk headers, staged IDAT data, CRCs) come out
/// through the `sink` closure in stream order. Nothing is allocated;
/// the IDAT staging buffer lives inline in the struct.
public struct PNGStream {
    /// Image width in pixels.
    public let width: Int
    /// Image height in pixels — the number of ``writeRow(bgra:_:)``
    /// calls ``finish(_:)`` expects.
    public let height: Int

    // Deflate bit accumulator (bits are appended LSB-first).
    private var acc: UInt64 = 0
    private var accBits: Int = 0

    // Adler-32 over the raw (filtered, uncompressed) stream.
    private var adlerA: UInt32 = 1
    private var adlerB: UInt32 = 0
    private var adlerPending: Int = 0

    // IDAT staging: one chunk's worth of compressed bytes.
    private var chunk: InlineArray<4096, UInt8>
    private var chunkCount: Int = 0

    private var crcTable: InlineArray<256, UInt32>
    private var rowsWritten: Int = 0

    /// An encoder for one `width` × `height` image.
    public init(width: Int, height: Int) {
        precondition(width > 0 && height > 0, "PNG dimensions must be positive")
        self.width = width
        self.height = height
        self.chunk = InlineArray(repeating: 0)
        var table = InlineArray<256, UInt32>(repeating: 0)
        for n in 0..<256 {
            var c = UInt32(n)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
            }
            table[n] = c
        }
        self.crcTable = table
    }

    /// Emits the PNG signature, IHDR, and the zlib/deflate preamble.
    public mutating func begin(_ sink: (Span<UInt8>) -> Void) {
        let signature: InlineArray<8, UInt8> = [137, 80, 78, 71, 13, 10, 26, 10]
        sink(signature.span)

        var ihdr = InlineArray<16, UInt8>(repeating: 0)
        putBE32(&ihdr, at: 0, UInt32(width))
        putBE32(&ihdr, at: 4, UInt32(height))
        ihdr[8] = 8   // bit depth
        ihdr[9] = 6   // color type: truecolor + alpha
        ihdr[10] = 0  // compression: deflate
        ihdr[11] = 0  // filter method 0
        ihdr[12] = 0  // no interlace
        emitSmallChunk(type: (73, 72, 68, 82), data: ihdr, count: 13, sink)  // "IHDR"

        // zlib header (0x78 0x01: 32K window, no preset, check bits ok),
        // then one fixed-Huffman deflate block spanning the whole image.
        putIDATByte(0x78, sink)
        putIDATByte(0x01, sink)
        writeBits(1, count: 1, sink)  // BFINAL
        writeBits(1, count: 2, sink)  // BTYPE 01: fixed Huffman
    }

    /// Encodes one BGRA row (`width * 4` bytes) as an RGBA scanline.
    public mutating func writeRow(bgra row: Span<UInt8>, _ sink: (Span<UInt8>) -> Void) {
        precondition(row.count >= width * 4, "row shorter than the image width")
        precondition(rowsWritten < height, "more rows than the image height")
        rowsWritten += 1

        rawLiteral(0, sink)  // filter type 0: none

        // First pixel is always literal; runs of equal pixels become
        // distance-4 matches.
        emitPixelLiteral(row, 0, sink)
        var p = 1
        while p < width {
            if pixelEquals(row, p, p - 1) {
                var q = p + 1
                while q < width && pixelEquals(row, q, p) { q += 1 }
                var runBytes = (q - p) * 4
                // Chunks of 256 (a multiple of 4) keep leftovers ≥ 4,
                // clear of deflate's minimum match length of 3.
                while runBytes > 0 {
                    let take = min(runBytes, 256)
                    emitMatch(length: take, sink)
                    runBytes -= take
                }
                // Adler covers the raw bytes the match expands to.
                let base = p * 4
                for _ in p..<q {
                    adler(row[base + 2]); adler(row[base + 1])
                    adler(row[base]); adler(row[base + 3])
                }
                p = q
            } else {
                emitPixelLiteral(row, p, sink)
                p += 1
            }
        }
    }

    /// Ends the deflate stream and emits the zlib trailer, final IDAT,
    /// and IEND.
    public mutating func finish(_ sink: (Span<UInt8>) -> Void) {
        precondition(rowsWritten == height, "finish before all rows were written")
        writeCode(0, length: 7, sink)  // end-of-block symbol 256
        while accBits > 0 {  // byte-align
            putIDATByte(UInt8(acc & 0xFF), sink)
            acc >>= 8
            accBits -= 8
        }
        accBits = 0
        adlerA %= 65521
        adlerB %= 65521
        let adler32 = (adlerB << 16) | adlerA
        putIDATByte(UInt8((adler32 >> 24) & 0xFF), sink)
        putIDATByte(UInt8((adler32 >> 16) & 0xFF), sink)
        putIDATByte(UInt8((adler32 >> 8) & 0xFF), sink)
        putIDATByte(UInt8(adler32 & 0xFF), sink)
        flushIDAT(sink)
        emitSmallChunk(type: (73, 69, 78, 68), data: InlineArray(repeating: 0), count: 0, sink)  // "IEND"
    }

    // MARK: Symbols

    /// A literal raw byte: Huffman-coded into the stream, counted by
    /// Adler.
    private mutating func rawLiteral(_ byte: UInt8, _ sink: (Span<UInt8>) -> Void) {
        if byte < 144 {
            writeCode(0x30 + UInt32(byte), length: 8, sink)
        } else {
            writeCode(0x190 + UInt32(byte) - 144, length: 9, sink)
        }
        adler(byte)
    }

    private mutating func emitPixelLiteral(_ row: Span<UInt8>, _ p: Int,
                                           _ sink: (Span<UInt8>) -> Void) {
        let i = p * 4  // BGRA in, RGBA out
        rawLiteral(row[i + 2], sink)
        rawLiteral(row[i + 1], sink)
        rawLiteral(row[i], sink)
        rawLiteral(row[i + 3], sink)
    }

    private func pixelEquals(_ row: Span<UInt8>, _ a: Int, _ b: Int) -> Bool {
        let i = a * 4
        let j = b * 4
        return row[i] == row[j] && row[i + 1] == row[j + 1]
            && row[i + 2] == row[j + 2] && row[i + 3] == row[j + 3]
    }

    /// A distance-4 match of `length` bytes (3...258): the RLE step.
    private mutating func emitMatch(length: Int, _ sink: (Span<UInt8>) -> Void) {
        let (symbol, extraBits, extraValue): (Int, Int, Int) =
            switch length {
            case 3...10: (257 + length - 3, 0, 0)
            case 11...18: (265 + (length - 11) / 2, 1, (length - 11) % 2)
            case 19...34: (269 + (length - 19) / 4, 2, (length - 19) % 4)
            case 35...66: (273 + (length - 35) / 8, 3, (length - 35) % 8)
            case 67...130: (277 + (length - 67) / 16, 4, (length - 67) % 16)
            case 131...257: (281 + (length - 131) / 32, 5, (length - 131) % 32)
            case 258: (285, 0, 0)
            default: preconditionFailure("match length out of range")
            }
        if symbol <= 279 {
            writeCode(UInt32(symbol - 256), length: 7, sink)
        } else {
            writeCode(0xC0 + UInt32(symbol - 280), length: 8, sink)
        }
        if extraBits > 0 {
            writeBits(UInt32(extraValue), count: extraBits, sink)
        }
        writeCode(3, length: 5, sink)  // distance code 3 = distance 4
    }

    // MARK: Bits and bytes

    /// Appends `count` bits LSB-first (deflate's order for headers and
    /// extra bits).
    private mutating func writeBits(_ value: UInt32, count: Int,
                                    _ sink: (Span<UInt8>) -> Void) {
        acc |= UInt64(value) << accBits
        accBits += count
        while accBits >= 8 {
            putIDATByte(UInt8(acc & 0xFF), sink)
            acc >>= 8
            accBits -= 8
        }
    }

    /// Appends a Huffman code (deflate packs codes MSB-first).
    private mutating func writeCode(_ code: UInt32, length: Int,
                                    _ sink: (Span<UInt8>) -> Void) {
        var reversed: UInt32 = 0
        for i in 0..<length {
            if code & (1 << (length - 1 - i)) != 0 {
                reversed |= 1 << i
            }
        }
        writeBits(reversed, count: length, sink)
    }

    private mutating func adler(_ byte: UInt8) {
        adlerA &+= UInt32(byte)
        adlerB &+= adlerA
        adlerPending += 1
        if adlerPending >= 5000 {  // safely below the 5552 overflow bound
            adlerA %= 65521
            adlerB %= 65521
            adlerPending = 0
        }
    }

    private mutating func putIDATByte(_ byte: UInt8, _ sink: (Span<UInt8>) -> Void) {
        chunk[chunkCount] = byte
        chunkCount += 1
        if chunkCount == 4096 {
            flushIDAT(sink)
        }
    }

    private mutating func flushIDAT(_ sink: (Span<UInt8>) -> Void) {
        guard chunkCount > 0 else { return }
        var head = InlineArray<8, UInt8>(repeating: 0)
        putBE32(&head, at: 0, UInt32(chunkCount))
        head[4] = 73; head[5] = 68; head[6] = 65; head[7] = 84  // "IDAT"
        sink(head.span)
        var crc: UInt32 = 0xFFFF_FFFF
        for i in 4..<8 { crc = crcUpdate(crc, head[i]) }
        for i in 0..<chunkCount { crc = crcUpdate(crc, chunk[i]) }
        sink(chunk.span.extracting(0..<chunkCount))
        var tail = InlineArray<4, UInt8>(repeating: 0)
        putBE32(&tail, at: 0, crc ^ 0xFFFF_FFFF)
        sink(tail.span)
        chunkCount = 0
    }

    /// Emits a complete small chunk (IHDR, IEND) in one go.
    private mutating func emitSmallChunk(type: (UInt8, UInt8, UInt8, UInt8),
                                         data: InlineArray<16, UInt8>, count: Int,
                                         _ sink: (Span<UInt8>) -> Void) {
        var out = InlineArray<28, UInt8>(repeating: 0)
        putBE32(&out, at: 0, UInt32(count))
        out[4] = type.0; out[5] = type.1; out[6] = type.2; out[7] = type.3
        for i in 0..<count { out[8 + i] = data[i] }
        var crc: UInt32 = 0xFFFF_FFFF
        for i in 4..<(8 + count) { crc = crcUpdate(crc, out[i]) }
        putBE32(&out, at: 8 + count, crc ^ 0xFFFF_FFFF)
        sink(out.span.extracting(0..<(12 + count)))
    }

    private func crcUpdate(_ crc: UInt32, _ byte: UInt8) -> UInt32 {
        crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
    }
}

private func putBE32<let N: Int>(_ buffer: inout InlineArray<N, UInt8>, at offset: Int,
                                 _ value: UInt32) {
    buffer[offset] = UInt8((value >> 24) & 0xFF)
    buffer[offset + 1] = UInt8((value >> 16) & 0xFF)
    buffer[offset + 2] = UInt8((value >> 8) & 0xFF)
    buffer[offset + 3] = UInt8(value & 0xFF)
}

extension Pane where Root: ~Escapable {
    /// Lays out and renders the pane band by band, streaming a
    /// complete PNG to `emit` — an embedded target can serve a
    /// full-frame image over HTTP while owning only a band buffer.
    ///
    /// - Parameters:
    ///   - env: The frame's environment.
    ///   - background: Painted under the tree in every band (elements
    ///     only write where they draw).
    ///   - bandHeight: Rows rendered per pass.
    ///   - bandBuffer: BGRA storage for one band:
    ///     at least `size.width * 4 * min(bandHeight, size.height)` bytes.
    ///   - glyphScratch: A8 glyph scratch, at least
    ///     ``Pane/glyphScratchSize`` bytes (checked after the layout
    ///     pass; query it via an earlier ``Pane/layout(_:)`` when
    ///     sizing a static buffer up front).
    ///   - emit: Receives the PNG's bytes, in order, in pieces.
    public mutating func renderPNG(
        _ env: borrowing Environment,
        background: Color = .black,
        bandHeight: Int = 32,
        bandBuffer: UnsafeMutableBufferPointer<UInt8>,
        glyphScratch: UnsafeMutableBufferPointer<UInt8>,
        emit: (Span<UInt8>) -> Void
    ) {
        precondition(bandHeight > 0, "bandHeight must be positive")
        let rowBytes = size.width * 4
        precondition(bandBuffer.count >= rowBytes * min(bandHeight, size.height),
                     "band buffer too small")
        layout(env)
        precondition(glyphScratch.count >= glyphScratchSize,
                     "glyph scratch too small — size it from Pane.glyphScratchSize")
        var png = PNGStream(width: size.width, height: size.height)
        png.begin(emit)
        var y = 0
        while y < size.height {
            let h = min(bandHeight, size.height - y)
            let bandRect = Rect(x: 0, y: y, width: size.width, height: h)
            do {
                var canvas = Canvas(pixels: bandBuffer.mutableSpan, bandRect: bandRect,
                                    glyphScratch: glyphScratch)
                canvas.fill(bandRect, color: background)
                render(into: &canvas, env)
            }
            for row in 0..<h {
                let slice = bandBuffer[(row * rowBytes)..<((row + 1) * rowBytes)]
                png.writeRow(bgra: Span(_unsafeElements: UnsafeBufferPointer(rebasing: slice)),
                             emit)
            }
            y += h
        }
        png.finish(emit)
    }

    /// Convenience for hosts with an allocator (tests, tools): the
    /// same banded render, returning the PNG as an array.
    public mutating func renderPNGData(
        _ env: borrowing Environment,
        background: Color = .black,
        bandHeight: Int = 32
    ) -> [UInt8] {
        let bandBuffer = UnsafeMutableBufferPointer<UInt8>.allocate(
            capacity: size.width * 4 * min(bandHeight, size.height))
        defer { bandBuffer.deallocate() }
        layout(env)  // learn the exact scratch requirement
        let scratch = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: glyphScratchSize)
        defer { scratch.deallocate() }
        var data: [UInt8] = []
        renderPNG(env, background: background, bandHeight: bandHeight,
                  bandBuffer: bandBuffer, glyphScratch: scratch) { piece in
            for i in 0..<piece.count {
                data.append(piece[i])
            }
        }
        return data
    }
}
