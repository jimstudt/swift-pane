import Foundation
import SwiftGlyph

/// Tests use a real system font, as swift-glyph's own tests do: these
/// are functional tests of the machinery, not pixel-correctness tests
/// of any particular typeface.
enum TestFont {
    static let candidates = [
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Supplemental/Verdana.ttf",
        "/System/Library/Fonts/Supplemental/Times New Roman.ttf",
        "/System/Library/Fonts/Supplemental/Georgia.ttf",
        "/System/Library/Fonts/Supplemental/Tahoma.ttf",
    ]

    static var path: String? {
        candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    static func load() throws -> Font {
        guard let path else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = [UInt8](try Data(contentsOf: URL(filePath: path)))
        return try Font(validating: data)
    }
}
