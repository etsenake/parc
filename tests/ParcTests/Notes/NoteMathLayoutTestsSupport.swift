import AppKit
import CoreText
import Testing
@testable import ParcCore
@testable import ParcNotes

enum NoteMathLayoutTestsSupport {
    @MainActor struct Fixture {
        let font: NoteMathFont

        let size: CGFloat = 20

        init() throws {
            NoteEditorFixtures.useMathFont()
            font = try #require(NoteMathRenderer.font)
        }

        func box(_ latex: String, display: Bool = true) throws -> NoteMathBox {
            NoteMathTypesetter(font: font, baseSize: size).typeset(try NoteMathParser.parse(latex), display: display)
        }

        func tagged(_ latex: String) throws -> NoteMathBox {
            NoteMathTypesetter(font: font, baseSize: size).typeset(try NoteMathParser.parseEquation(latex, display: true), display: true)
        }

        func glyph(_ symbol: String) -> CGGlyph { font.glyph(for: symbol.unicodeScalars.first!) }

        func scriptGlyph(_ symbol: String, _ level: Int) -> CGGlyph { font.scriptGlyph(glyph(symbol), level: level) }

        func inks(_ box: NoteMathBox, glyph target: CGGlyph) -> [NoteMathInk] {
            box.inks.filter { ink in
                if case .glyph(let glyph, _) = ink.content { return glyph == target }
                return false
            }
        }

        func extent(_ inks: [NoteMathInk]) -> CGRect {
            inks.reduce(CGRect.null) { result, ink in
                guard case .glyph(let glyph, let ctFont) = ink.content else { return result }
                let scale = CTFontGetSize(ctFont) / font.unitsPerEm
                let bounds = font.metrics(glyph).bounds
                return result.union(CGRect(x: ink.origin.x + bounds.minX * scale, y: ink.origin.y + bounds.minY * scale,
                                           width: bounds.width * scale, height: bounds.height * scale))
            }
        }

        func rules(_ box: NoteMathBox) -> [NoteMathInk] {
            box.inks.filter { if case .rule = $0.content { return true } else { return false } }
        }

        func ruleCount(_ box: NoteMathBox) -> Int { rules(box).count }

        func segments(_ box: NoteMathBox) -> Int {
            box.inks.filter { if case .segment = $0.content { return true } else { return false } }.count
        }

        var axis: CGFloat { font.constants[.axisHeight] * size / 1000 }

        struct Bitmap {
            let width: Int
            let height: Int
            let alpha: [UInt8]

            func ink(x: ClosedRange<Double>, y: ClosedRange<Double>) -> Int {
                var count = 0
                let columns = Int(x.lowerBound * Double(width))..<max(Int(x.upperBound * Double(width)), Int(x.lowerBound * Double(width)) + 1)
                let rows = Int(y.lowerBound * Double(height))..<max(Int(y.upperBound * Double(height)), Int(y.lowerBound * Double(height)) + 1)
                for row in rows where row >= 0 && row < height {
                    for column in columns where column >= 0 && column < width {
                        if alpha[row * width + column] > 40 { count += 1 }
                    }
                }
                return count
            }

            func fullRows() -> [Int] {
                (0..<height).filter { row in (0..<width).filter { alpha[row * width + $0] > 200 }.count > width * 6 / 10 }
            }
        }

        func bitmap(_ rendering: NoteMathRendering, scale: CGFloat = 2) -> Bitmap {
            let width = Int((rendering.size.width * scale).rounded(.up)), height = Int((rendering.size.height * scale).rounded(.up))
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            pixels.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                context.scaleBy(x: scale, y: scale)
                rendering.draw(in: context, at: .zero)
            }
            return Bitmap(width: width, height: height, alpha: stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] })
        }

        func picture(_ latex: String, scale: CGFloat = 2) -> Bitmap {
            bitmap(NoteMathRenderer.render(latex, fontSize: 40, color: .black, display: true), scale: scale)
        }
    }
}
