import AppKit
import CoreText

enum NoteMathConstant: Int, CaseIterable {
    case mathLeading, axisHeight, accentBaseHeight, flattenedAccentBaseHeight, subscriptShiftDown, subscriptTopMax
    case subscriptBaselineDropMin, superscriptShiftUp, superscriptShiftUpCramped, superscriptBottomMin
    case superscriptBaselineDropMax, subSuperscriptGapMin, superscriptBottomMaxWithSubscript, spaceAfterScript
    case upperLimitGapMin, upperLimitBaselineRiseMin, lowerLimitGapMin, lowerLimitBaselineDropMin
    case stackTopShiftUp, stackTopDisplayStyleShiftUp, stackBottomShiftDown, stackBottomDisplayStyleShiftDown
    case stackGapMin, stackDisplayStyleGapMin, stretchStackTopShiftUp, stretchStackBottomShiftDown
    case stretchStackGapAboveMin, stretchStackGapBelowMin, fractionNumeratorShiftUp
    case fractionNumeratorDisplayStyleShiftUp, fractionDenominatorShiftDown, fractionDenominatorDisplayStyleShiftDown
    case fractionNumeratorGapMin, fractionNumDisplayStyleGapMin, fractionRuleThickness, fractionDenominatorGapMin
    case fractionDenomDisplayStyleGapMin, skewedFractionHorizontalGap, skewedFractionVerticalGap, overbarVerticalGap
    case overbarRuleThickness, overbarExtraAscender, underbarVerticalGap, underbarRuleThickness
    case underbarExtraDescender, radicalVerticalGap, radicalDisplayStyleVerticalGap, radicalRuleThickness
    case radicalExtraAscender, radicalKernBeforeDegree, radicalKernAfterDegree
}

struct NoteMathConstants {
    var scriptPercentScaleDown: CGFloat = 70
    var scriptScriptPercentScaleDown: CGFloat = 50
    var delimitedSubFormulaMinHeight: CGFloat = 1300
    var displayOperatorMinHeight: CGFloat = 1300
    var radicalDegreeBottomRaisePercent: CGFloat = 60
    var values: [CGFloat] = Array(repeating: 0, count: NoteMathConstant.allCases.count)

    subscript(_ constant: NoteMathConstant) -> CGFloat { values[constant.rawValue] }
}

struct NoteMathGlyphPart {
    var glyph: CGGlyph
    var startConnector: CGFloat
    var endConnector: CGFloat
    var fullAdvance: CGFloat
    var isExtender: Bool
}

struct NoteMathGlyphConstruction {
    var variants: [(glyph: CGGlyph, advance: CGFloat)] = []
    var parts: [NoteMathGlyphPart] = []
    var assemblyItalicCorrection: CGFloat = 0
}

struct NoteMathKern {
    var heights: [CGFloat]
    var kerns: [CGFloat]

    func value(at height: CGFloat) -> CGFloat {
        for (index, limit) in heights.enumerated() where height < limit { return kerns[index] }
        return kerns.last ?? 0
    }
}

struct NoteMathKernSet {
    var topRight: NoteMathKern?
    var topLeft: NoteMathKern?
    var bottomRight: NoteMathKern?
    var bottomLeft: NoteMathKern?
}

struct NoteMathGlyphMetrics {
    var advance: CGFloat
    var bounds: CGRect
}

final class NoteMathFont {
    let descriptor: CTFontDescriptor
    let unitsPerEm: CGFloat
    let constants: NoteMathConstants
    let minConnectorOverlap: CGFloat
    let hasMathTable: Bool
    private let unitFont: CTFont
    private let italicCorrections: [CGGlyph: CGFloat]
    private let topAccentAttachments: [CGGlyph: CGFloat]
    private let extendedShapes: Set<CGGlyph>
    private let kerns: [CGGlyph: NoteMathKernSet]
    private let verticalConstructions: [CGGlyph: NoteMathGlyphConstruction]
    private let horizontalConstructions: [CGGlyph: NoteMathGlyphConstruction]
    private let scriptAlternates: [CGGlyph: [CGGlyph]]
    private let flattenedAccents: [CGGlyph: CGGlyph]
    private let lock = NSLock()
    private var sizedFonts: [CGFloat: CTFont] = [:]
    private var metricsCache: [CGGlyph: NoteMathGlyphMetrics] = [:]
    private var glyphCache: [UInt32: CGGlyph] = [:]

    convenience init?(url: URL) {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else { return nil }
        self.init(descriptor: descriptor)
    }

    convenience init?(name: String) {
        let descriptor = CTFontDescriptorCreateWithNameAndSize(name as CFString, 0)
        let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
        guard CTFontCopyPostScriptName(font) as String == name else { return nil }
        self.init(descriptor: descriptor)
    }

    init?(descriptor: CTFontDescriptor) {
        let probe = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
        let units = CGFloat(CTFontGetUnitsPerEm(probe))
        guard units > 0 else { return nil }
        self.descriptor = descriptor
        unitsPerEm = units
        unitFont = CTFontCreateWithFontDescriptor(descriptor, units, nil)
        let substitutions = CTFontCopyTable(unitFont, CTFontTableTag(0x4753_5542), []).map { [UInt8]($0 as Data) } ?? []
        let substitutionReader = NoteMathTableReader(bytes: substitutions)
        let scriptStyle = substitutionReader.substitutions(feature: 0x7373_7479)
        scriptAlternates = scriptStyle.alternates.merging(scriptStyle.singles.mapValues { [$0] }) { current, _ in current }
        flattenedAccents = substitutionReader.substitutions(feature: 0x666C_6163).singles
        let table = CTFontCopyTable(unitFont, CTFontTableTag(0x4D41_5448), []).map { [UInt8]($0 as Data) } ?? []
        let reader = NoteMathTableReader(bytes: table)
        hasMathTable = reader.u16(0) == 1
        if hasMathTable {
            let constantsOffset = reader.u16(4)
            let glyphInfoOffset = reader.u16(6)
            let variantsOffset = reader.u16(8)
            constants = reader.constants(at: constantsOffset)
            let glyphInfo = reader.glyphInfo(at: glyphInfoOffset)
            italicCorrections = glyphInfo.italicCorrections
            topAccentAttachments = glyphInfo.topAccents
            extendedShapes = glyphInfo.extendedShapes
            kerns = glyphInfo.kerns
            let variants = reader.variants(at: variantsOffset)
            minConnectorOverlap = variants.minConnectorOverlap
            verticalConstructions = variants.vertical
            horizontalConstructions = variants.horizontal
        } else {
            var fallback = NoteMathConstants()
            let em = units
            let assign: [(NoteMathConstant, CGFloat)] = [
                (.axisHeight, 0.25), (.accentBaseHeight, 0.45), (.subscriptShiftDown, 0.15), (.subscriptTopMax, 0.34),
                (.subscriptBaselineDropMin, 0.05), (.superscriptShiftUp, 0.36), (.superscriptShiftUpCramped, 0.29),
                (.superscriptBottomMin, 0.11), (.superscriptBaselineDropMax, 0.39), (.subSuperscriptGapMin, 0.16),
                (.superscriptBottomMaxWithSubscript, 0.34), (.spaceAfterScript, 0.05), (.upperLimitGapMin, 0.11),
                (.upperLimitBaselineRiseMin, 0.11), (.lowerLimitGapMin, 0.17), (.lowerLimitBaselineDropMin, 0.6),
                (.stackTopShiftUp, 0.44), (.stackTopDisplayStyleShiftUp, 0.68), (.stackBottomShiftDown, 0.35),
                (.stackBottomDisplayStyleShiftDown, 0.69), (.stackGapMin, 0.2), (.stackDisplayStyleGapMin, 0.47),
                (.stretchStackTopShiftUp, 0.3), (.stretchStackBottomShiftDown, 0.3), (.stretchStackGapAboveMin, 0.1),
                (.stretchStackGapBelowMin, 0.1), (.fractionNumeratorShiftUp, 0.39),
                (.fractionNumeratorDisplayStyleShiftUp, 0.68), (.fractionDenominatorShiftDown, 0.34),
                (.fractionDenominatorDisplayStyleShiftDown, 0.69), (.fractionNumeratorGapMin, 0.04),
                (.fractionNumDisplayStyleGapMin, 0.12), (.fractionRuleThickness, 0.04),
                (.fractionDenominatorGapMin, 0.04), (.fractionDenomDisplayStyleGapMin, 0.12),
                (.overbarVerticalGap, 0.12), (.overbarRuleThickness, 0.04), (.overbarExtraAscender, 0.04),
                (.underbarVerticalGap, 0.12), (.underbarRuleThickness, 0.04), (.underbarExtraDescender, 0.04),
                (.radicalVerticalGap, 0.05), (.radicalDisplayStyleVerticalGap, 0.15), (.radicalRuleThickness, 0.04),
                (.radicalExtraAscender, 0.04), (.radicalKernBeforeDegree, 0.28), (.radicalKernAfterDegree, -0.56),
            ]
            for (constant, value) in assign { fallback.values[constant.rawValue] = value * em }
            fallback.delimitedSubFormulaMinHeight = 1.3 * em
            fallback.displayOperatorMinHeight = 1.3 * em
            constants = fallback
            italicCorrections = [:]
            topAccentAttachments = [:]
            extendedShapes = []
            kerns = [:]
            minConnectorOverlap = 0
            verticalConstructions = [:]
            horizontalConstructions = [:]
        }
    }

    func font(size: CGFloat) -> CTFont {
        let key = (size * 64).rounded() / 64
        lock.lock()
        defer { lock.unlock() }
        if let font = sizedFonts[key] { return font }
        let font = CTFontCreateWithFontDescriptor(descriptor, key, nil)
        sizedFonts[key] = font
        return font
    }

    func glyph(for scalar: Unicode.Scalar) -> CGGlyph {
        lock.lock()
        if let cached = glyphCache[scalar.value] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        var units = Array(String(scalar).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        let found = CTFontGetGlyphsForCharacters(unitFont, &units, &glyphs, units.count)
        let glyph = found ? glyphs[0] : 0
        lock.lock()
        glyphCache[scalar.value] = glyph
        lock.unlock()
        return glyph
    }

    func metrics(_ glyph: CGGlyph) -> NoteMathGlyphMetrics {
        lock.lock()
        if let cached = metricsCache[glyph] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        var value = glyph
        var advance = CGSize.zero
        var bounds = CGRect.zero
        CTFontGetAdvancesForGlyphs(unitFont, .horizontal, &value, &advance, 1)
        CTFontGetBoundingRectsForGlyphs(unitFont, .horizontal, &value, &bounds, 1)
        let metrics = NoteMathGlyphMetrics(advance: advance.width, bounds: bounds)
        lock.lock()
        metricsCache[glyph] = metrics
        lock.unlock()
        return metrics
    }

    func italicCorrection(_ glyph: CGGlyph) -> CGFloat { italicCorrections[glyph] ?? 0 }

    func topAccentAttachment(_ glyph: CGGlyph) -> CGFloat? { topAccentAttachments[glyph] }

    func isExtendedShape(_ glyph: CGGlyph) -> Bool { extendedShapes.contains(glyph) }

    func kernSet(_ glyph: CGGlyph) -> NoteMathKernSet? { kerns[glyph] }

    func verticalConstruction(_ glyph: CGGlyph) -> NoteMathGlyphConstruction? { verticalConstructions[glyph] }

    func horizontalConstruction(_ glyph: CGGlyph) -> NoteMathGlyphConstruction? { horizontalConstructions[glyph] }

    var hasScriptAlternates: Bool { !scriptAlternates.isEmpty }

    func scriptGlyph(_ glyph: CGGlyph, level: Int) -> CGGlyph {
        guard level > 0, let alternates = scriptAlternates[glyph], !alternates.isEmpty else { return glyph }
        let alternate = alternates[min(level, alternates.count) - 1]
        return alternate == 0 ? glyph : alternate
    }

    func flattenedAccent(_ glyph: CGGlyph) -> CGGlyph? { flattenedAccents[glyph] }
}

private struct NoteMathSubstitutions {
    var singles: [CGGlyph: CGGlyph] = [:]
    var alternates: [CGGlyph: [CGGlyph]] = [:]
}

private struct NoteMathTableReader {
    let bytes: [UInt8]

    func u16(_ offset: Int) -> Int {
        guard offset >= 0, offset + 1 < bytes.count else { return 0 }
        return Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
    }

    func i16(_ offset: Int) -> Int {
        let value = u16(offset)
        return value >= 0x8000 ? value - 0x10000 : value
    }

    func u32(_ offset: Int) -> Int { u16(offset) << 16 | u16(offset + 2) }

    func lookupOffsets(feature tag: Int) -> [Int] {
        guard bytes.count > 10 else { return [] }
        let featureList = u16(6), lookupList = u16(8)
        guard featureList > 0, lookupList > 0 else { return [] }
        var lookups: [Int] = []
        for index in 0..<u16(featureList) {
            let record = featureList + 2 + index * 6
            guard u32(record) == tag else { continue }
            let feature = featureList + u16(record + 4)
            for item in 0..<u16(feature + 2) {
                let lookup = u16(feature + 4 + item * 2)
                let offset = lookupList + u16(lookupList + 2 + lookup * 2)
                if !lookups.contains(offset) { lookups.append(offset) }
            }
        }
        return lookups
    }

    func substitutions(feature tag: Int) -> NoteMathSubstitutions {
        var result = NoteMathSubstitutions()
        for lookup in lookupOffsets(feature: tag) {
            for index in 0..<u16(lookup + 4) {
                var subtable = lookup + u16(lookup + 6 + index * 2)
                var kind = u16(lookup)
                if kind == 7 {
                    kind = u16(subtable + 2)
                    subtable += u32(subtable + 4)
                }
                let glyphs = coverage(at: subtable + u16(subtable + 2))
                switch (kind, u16(subtable)) {
                case (1, 1):
                    let delta = i16(subtable + 4)
                    for glyph in glyphs where result.singles[glyph] == nil {
                        result.singles[glyph] = CGGlyph(truncatingIfNeeded: (Int(glyph) + delta) & 0xFFFF)
                    }
                case (1, 2):
                    for index in 0..<min(u16(subtable + 4), glyphs.count) where result.singles[glyphs[index]] == nil {
                        result.singles[glyphs[index]] = CGGlyph(u16(subtable + 6 + index * 2))
                    }
                case (3, 1):
                    for index in 0..<min(u16(subtable + 4), glyphs.count) where result.alternates[glyphs[index]] == nil {
                        let set = subtable + u16(subtable + 6 + index * 2)
                        result.alternates[glyphs[index]] = (0..<u16(set)).map { CGGlyph(u16(set + 2 + $0 * 2)) }
                    }
                default:
                    break
                }
            }
        }
        return result
    }

    func coverage(at offset: Int) -> [CGGlyph] {
        guard offset > 0 else { return [] }
        switch u16(offset) {
        case 1:
            let count = u16(offset + 2)
            return (0..<count).map { CGGlyph(u16(offset + 4 + $0 * 2)) }
        case 2:
            let count = u16(offset + 2)
            var glyphs: [(index: Int, glyph: CGGlyph)] = []
            for range in 0..<count {
                let record = offset + 4 + range * 6
                let start = u16(record), end = u16(record + 2), first = u16(record + 4)
                guard end >= start, end - start < 0x10000 else { continue }
                for glyph in start...end { glyphs.append((first + glyph - start, CGGlyph(glyph))) }
            }
            return glyphs.sorted { $0.index < $1.index }.map(\.glyph)
        default:
            return []
        }
    }

    func constants(at offset: Int) -> NoteMathConstants {
        var constants = NoteMathConstants()
        constants.scriptPercentScaleDown = CGFloat(i16(offset))
        constants.scriptScriptPercentScaleDown = CGFloat(i16(offset + 2))
        constants.delimitedSubFormulaMinHeight = CGFloat(u16(offset + 4))
        constants.displayOperatorMinHeight = CGFloat(u16(offset + 6))
        for constant in NoteMathConstant.allCases {
            constants.values[constant.rawValue] = CGFloat(i16(offset + 8 + constant.rawValue * 4))
        }
        constants.radicalDegreeBottomRaisePercent = CGFloat(i16(offset + 8 + NoteMathConstant.allCases.count * 4))
        if constants.scriptPercentScaleDown <= 0 { constants.scriptPercentScaleDown = 70 }
        if constants.scriptScriptPercentScaleDown <= 0 { constants.scriptScriptPercentScaleDown = 50 }
        return constants
    }

    func valueRecords(at offset: Int) -> [CGGlyph: CGFloat] {
        guard offset > 0 else { return [:] }
        let glyphs = coverage(at: offset + u16(offset))
        let count = min(u16(offset + 2), glyphs.count)
        var values: [CGGlyph: CGFloat] = [:]
        for index in 0..<count { values[glyphs[index]] = CGFloat(i16(offset + 4 + index * 4)) }
        return values
    }

    func kern(at offset: Int) -> NoteMathKern? {
        guard offset > 0 else { return nil }
        let count = u16(offset)
        let heights = (0..<count).map { CGFloat(i16(offset + 2 + $0 * 4)) }
        let kerns = (0...count).map { CGFloat(i16(offset + 2 + (count + $0) * 4)) }
        return NoteMathKern(heights: heights, kerns: kerns)
    }

    func glyphInfo(at offset: Int) -> (italicCorrections: [CGGlyph: CGFloat], topAccents: [CGGlyph: CGFloat],
                                       extendedShapes: Set<CGGlyph>, kerns: [CGGlyph: NoteMathKernSet]) {
        guard offset > 0 else { return ([:], [:], [], [:]) }
        let italics = u16(offset).relative(to: offset)
        let accents = u16(offset + 2).relative(to: offset)
        let extended = u16(offset + 4).relative(to: offset)
        let kernInfo = u16(offset + 6).relative(to: offset)
        var kerns: [CGGlyph: NoteMathKernSet] = [:]
        if kernInfo > 0 {
            let glyphs = coverage(at: kernInfo + u16(kernInfo))
            let count = min(u16(kernInfo + 2), glyphs.count)
            for index in 0..<count {
                let record = kernInfo + 4 + index * 8
                func corner(_ slot: Int) -> NoteMathKern? {
                    let relative = u16(record + slot * 2)
                    return relative == 0 ? nil : kern(at: kernInfo + relative)
                }
                kerns[glyphs[index]] = NoteMathKernSet(topRight: corner(0), topLeft: corner(1),
                                                        bottomRight: corner(2), bottomLeft: corner(3))
            }
        }
        return (valueRecords(at: italics), valueRecords(at: accents), Set(coverage(at: extended)), kerns)
    }

    func construction(at offset: Int) -> NoteMathGlyphConstruction {
        var construction = NoteMathGlyphConstruction()
        let assembly = u16(offset)
        let variantCount = u16(offset + 2)
        for index in 0..<variantCount {
            let record = offset + 4 + index * 4
            construction.variants.append((CGGlyph(u16(record)), CGFloat(u16(record + 2))))
        }
        if assembly > 0 {
            let base = offset + assembly
            construction.assemblyItalicCorrection = CGFloat(i16(base))
            let partCount = u16(base + 4)
            for index in 0..<partCount {
                let record = base + 6 + index * 10
                construction.parts.append(NoteMathGlyphPart(
                    glyph: CGGlyph(u16(record)), startConnector: CGFloat(u16(record + 2)),
                    endConnector: CGFloat(u16(record + 4)), fullAdvance: CGFloat(u16(record + 6)),
                    isExtender: u16(record + 8) & 1 == 1))
            }
        }
        return construction
    }

    func variants(at offset: Int) -> (minConnectorOverlap: CGFloat, vertical: [CGGlyph: NoteMathGlyphConstruction],
                                      horizontal: [CGGlyph: NoteMathGlyphConstruction]) {
        guard offset > 0 else { return (0, [:], [:]) }
        let overlap = CGFloat(u16(offset))
        let verticalGlyphs = coverage(at: u16(offset + 2).relative(to: offset))
        let horizontalGlyphs = coverage(at: u16(offset + 4).relative(to: offset))
        let verticalCount = min(u16(offset + 6), verticalGlyphs.count)
        let horizontalCount = min(u16(offset + 8), horizontalGlyphs.count)
        let declaredVertical = u16(offset + 6)
        var vertical: [CGGlyph: NoteMathGlyphConstruction] = [:]
        var horizontal: [CGGlyph: NoteMathGlyphConstruction] = [:]
        for index in 0..<verticalCount {
            let relative = u16(offset + 10 + index * 2)
            if relative > 0 { vertical[verticalGlyphs[index]] = construction(at: offset + relative) }
        }
        for index in 0..<horizontalCount {
            let relative = u16(offset + 10 + (declaredVertical + index) * 2)
            if relative > 0 { horizontal[horizontalGlyphs[index]] = construction(at: offset + relative) }
        }
        return (overlap, vertical, horizontal)
    }
}

private extension Int {
    func relative(to base: Int) -> Int { self == 0 ? 0 : base + self }
}
