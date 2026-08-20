import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import SwiftPane

/// Decodes a PNG through ImageIO into tightly-packed RGBA8.
func decodePNG(_ data: [UInt8]) -> (width: Int, height: Int, rgba: [UInt8])? {
    guard let source = CGImageSourceCreateWithData(Data(data) as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    let width = image.width
    let height = image.height
    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let ok: Bool = rgba.withUnsafeMutableBytes { buf in
        guard let context = CGContext(
            data: buf.baseAddress, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return ok ? (width, height, rgba) : nil
}

struct PNGStreamTests {
    /// Round-trips a synthetic image with flat runs (the RLE path) and
    /// a gradient (the literal path) through a real decoder.
    @Test func roundTrip() throws {
        let width = 64
        let height = 16
        var bgra = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if x < 32 {
                    bgra[i] = 30; bgra[i + 1] = 60; bgra[i + 2] = 200  // solid: runs
                } else {
                    bgra[i] = UInt8(x * 3); bgra[i + 1] = UInt8(y * 15)  // gradient: literals
                    bgra[i + 2] = 10
                }
                bgra[i + 3] = 255
            }
        }

        var png: [UInt8] = []
        var stream = PNGStream(width: width, height: height)
        let sink: (Span<UInt8>) -> Void = { piece in
            for i in 0..<piece.count { png.append(piece[i]) }
        }
        stream.begin(sink)
        bgra.withUnsafeBufferPointer { buf in
            for y in 0..<height {
                let row = UnsafeBufferPointer(
                    rebasing: buf[(y * width * 4)..<((y + 1) * width * 4)])
                stream.writeRow(bgra: Span(_unsafeElements: row), sink)
            }
        }
        stream.finish(sink)

        #expect(Array(png.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
        let decoded = try #require(decodePNG(png))
        #expect(decoded.width == width && decoded.height == height)
        for y in 0..<height {
            for x in 0..<width {
                let s = (y * width + x) * 4
                // Encoder input was BGRA; decoded output is RGBA.
                #expect(decoded.rgba[s] == bgra[s + 2])
                #expect(decoded.rgba[s + 1] == bgra[s + 1])
                #expect(decoded.rgba[s + 2] == bgra[s])
                #expect(decoded.rgba[s + 3] == 255)
            }
        }
    }
}
