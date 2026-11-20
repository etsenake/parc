import AppKit
import CoreText

enum NoteMathInkColor {
    case inherited
    case custom(CGColor)
    case muted
}

struct NoteMathInk {
    enum Content {
        case glyph(CGGlyph, CTFont)
        case rule(CGSize)
        case line(CTLine)
    }

    var content: Content
    var origin: CGPoint
    var color: NoteMathInkColor
}

struct NoteMathBox {
    var width: CGFloat = 0
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var italicCorrection: CGFloat = 0
    var accentAttachment: CGFloat?
    var glyph: CGGlyph?
    var glyphSize: CGFloat = 0
    var inks: [NoteMathInk] = []

    var height: CGFloat { ascent + descent }

    mutating func draw(_ box: NoteMathBox, at point: CGPoint) {
        inks.reserveCapacity(inks.count + box.inks.count)
        for var ink in box.inks {
            ink.origin.x += point.x
            ink.origin.y += point.y
            inks.append(ink)
        }
    }

    func raised(by amount: CGFloat) -> NoteMathBox {
        var result = self
        result.ascent += amount
        result.descent -= amount
        for index in result.inks.indices { result.inks[index].origin.y += amount }
        return result
    }

    func withoutGlyphIdentity() -> NoteMathBox {
        var result = self
        result.glyph = nil
        result.accentAttachment = nil
        return result
    }
}

struct NoteMathRow {
    var box = NoteMathBox()

    mutating func append(_ item: NoteMathBox) {
        box.draw(item, at: CGPoint(x: box.width, y: 0))
        box.width += item.width
        box.ascent = max(box.ascent, item.ascent)
        box.descent = max(box.descent, item.descent)
    }

    mutating func skip(_ amount: CGFloat) {
        box.width += amount
    }
}

struct NoteMathStyle: Equatable {
    var level: NoteMathStyleLevel
    var cramped: Bool

    var isDisplay: Bool { level == .display }
    var isScript: Bool { level == .script || level == .scriptScript }
    var superscriptStyle: NoteMathStyle {
        NoteMathStyle(level: level == .display || level == .text ? .script : .scriptScript, cramped: cramped)
    }
    var subscriptStyle: NoteMathStyle { superscriptStyle.crampedStyle }
    var numerator: NoteMathStyle {
        NoteMathStyle(level: level == .display ? .text : level == .text ? .script : .scriptScript, cramped: cramped)
    }
    var denominator: NoteMathStyle { numerator.crampedStyle }
    var crampedStyle: NoteMathStyle { NoteMathStyle(level: level, cramped: true) }
}

struct NoteMathContext {
    var style: NoteMathStyle
    var variant: NoteMathVariant = .normal
    var color: NoteMathInkColor = .inherited

    func with(style: NoteMathStyle) -> NoteMathContext {
        var copy = self
        copy.style = style
        return copy
    }

    func with(variant: NoteMathVariant) -> NoteMathContext {
        var copy = self
        copy.variant = variant
        return copy
    }

    func with(color: NoteMathInkColor) -> NoteMathContext {
        var copy = self
        copy.color = color
        return copy
    }
}

struct NoteMathTypesetter {
    let font: NoteMathFont
    let baseSize: CGFloat

    private struct Atom {
        var kind: NoteMathAtomKind?
        var box: NoteMathBox
        var style: NoteMathStyle
    }

    private struct Nucleus {
        var box: NoteMathBox
        var isCharacter = false
        var isLargeOperator = false
        var usesLimits = false
        var stretchStack = false
    }

    private static let spacingTable: [[Int]] = [
        [0, 1, -2, -3, 0, 0, 0, -1],
        [1, 1, 0, -3, 0, 0, 0, -1],
        [-2, -2, 0, 0, -2, 0, 0, -2],
        [-3, -3, 0, 0, -3, 0, 0, -3],
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 1, -2, -3, 0, 0, 0, -1],
        [-1, -1, 0, -1, -1, -1, -1, -1],
        [-1, 1, -2, -3, -1, 0, -1, -1],
    ]

    private static let integralSymbols: Set<String> = ["∫", "∬", "∭", "⨌", "∮", "∯", "∰", "∱", "∲", "∳", "⨍", "⨎", "⨏", "⨐", "⨑", "⨒", "⨓", "⨔", "⨕", "⨖", "⨗"]

    func typeset(_ nodes: [NoteMathNode], display: Bool) -> NoteMathBox {
        layoutList(nodes, NoteMathContext(style: NoteMathStyle(level: display ? .display : .text, cramped: false)))
    }

    func size(_ style: NoteMathStyle) -> CGFloat {
        switch style.level {
        case .display, .text: return baseSize
        case .script: return baseSize * font.constants.scriptPercentScaleDown / 100
        case .scriptScript: return baseSize * font.constants.scriptScriptPercentScaleDown / 100
        }
    }

    private func scale(_ context: NoteMathContext) -> CGFloat { size(context.style) / font.unitsPerEm }

    private func em(_ context: NoteMathContext) -> CGFloat { size(context.style) }

    private func constant(_ constant: NoteMathConstant, _ context: NoteMathContext) -> CGFloat {
        font.constants[constant] * scale(context)
    }

    private func color(_ color: NoteMathColor) -> CGColor {
        CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
    }

    func layoutList(_ nodes: [NoteMathNode], _ context: NoteMathContext) -> NoteMathBox {
        var atoms: [Atom] = []
        collectAtoms(nodes, context, into: &atoms)
        if atoms.count == 1 { return atoms[0].box }
        var previous: Int?
        for index in atoms.indices {
            guard let kind = atoms[index].kind else { continue }
            let previousKind = previous.flatMap { atoms[$0].kind }
            if kind == .bin, previousKind == nil || [.bin, .op, .rel, .open, .punct].contains(previousKind!) {
                atoms[index].kind = .ord
            }
            if [.rel, .close, .punct].contains(kind), let previous, atoms[previous].kind == .bin {
                atoms[previous].kind = .ord
            }
            previous = index
        }
        if let previous, atoms[previous].kind == .bin { atoms[previous].kind = .ord }
        var row = NoteMathRow()
        var lastKind: NoteMathAtomKind?
        for atom in atoms {
            if let kind = atom.kind {
                if let lastKind {
                    let entry = Self.spacingTable[Self.index(lastKind)][Self.index(kind)]
                    if entry > 0 || (entry < 0 && !atom.style.isScript) {
                        let mu = [0, 3, 4, 5][abs(entry)]
                        row.skip(CGFloat(mu) * size(atom.style) / 18)
                    }
                }
                lastKind = kind
            }
            row.append(atom.box)
        }
        return row.box
    }

    private static func index(_ kind: NoteMathAtomKind) -> Int {
        switch kind {
        case .ord: return 0
        case .op: return 1
        case .bin: return 2
        case .rel: return 3
        case .open: return 4
        case .close: return 5
        case .punct: return 6
        case .inner: return 7
        }
    }

    private func collectAtoms(_ nodes: [NoteMathNode], _ context: NoteMathContext, into atoms: inout [Atom]) {
        for node in nodes {
            switch node {
            case .colored(let value, let content):
                collectAtoms(content, context.with(color: .custom(color(value))), into: &atoms)
            case .styled(let variant, let content):
                collectAtoms(content, context.with(variant: variant), into: &atoms)
            case .mathStyle(let level, let content):
                collectAtoms(content, context.with(style: NoteMathStyle(level: level, cramped: context.style.cramped)), into: &atoms)
            case .space(let amount):
                atoms.append(Atom(kind: nil, box: NoteMathBox(width: CGFloat(amount) * em(context)), style: context.style))
            default:
                let laidOut = layoutAtom(node, context)
                atoms.append(Atom(kind: laidOut.kind, box: laidOut.box, style: context.style))
            }
        }
    }

    private func atomKind(_ node: NoteMathNode?) -> NoteMathAtomKind {
        guard let node else { return .ord }
        switch node {
        case .char(_, let kind): return kind
        case .largeOperator, .function, .operatorName: return .op
        case .fraction, .fenced: return .inner
        case .sizedDelimiter(_, _, let kind): return kind
        case .classed(let kind, _): return kind
        case .decorated(.overbrace, _), .decorated(.underbrace, _): return .op
        case .environment(let environment): return environment.left != nil || environment.right != nil ? .inner : .ord
        case .styled(_, let content), .colored(_, let content), .mathStyle(_, let content):
            return content.count == 1 ? atomKind(content[0]) : .ord
        case .stacked(let base, _, _): return base.count == 1 ? atomKind(base[0]) : .ord
        case .scripts(let base, _, _): return atomKind(base)
        default: return .ord
        }
    }

    private func layoutAtom(_ node: NoteMathNode, _ context: NoteMathContext) -> (box: NoteMathBox, kind: NoteMathAtomKind) {
        switch node {
        case .char(let symbol, let kind):
            var box = character(symbol, context)
            if kind == .ord { box.width += box.italicCorrection }
            return (box, kind)
        case .largeOperator(let symbol, _):
            var box = largeOperator(symbol, context)
            box.width += box.italicCorrection
            return (box, .op)
        case .function(let name, _):
            return (textRun(name, context, style: .roman), .op)
        case .operatorName(let content, _):
            return (layoutList(content, context.with(variant: .roman)).withoutGlyphIdentity(), .op)
        case .text(let text, let style):
            return (textRun(text, context, style: style), .ord)
        case .group(let content):
            return (layoutList(content, context), .ord)
        case .scripts(let base, let upper, let lower):
            return (scripts(base: base, superscript: upper, subscript: lower, context), atomKind(base))
        case .fraction(let fraction):
            return (self.fraction(fraction, context), .inner)
        case .radical(let radicand, let degree):
            return (radical(radicand, degree: degree, context), .ord)
        case .fenced(let left, let right, let middles, let segments):
            return (fenced(left: left, right: right, middles: middles, segments: segments, context), .inner)
        case .sizedDelimiter(let symbol, let level, let kind):
            return (sizedDelimiter(symbol, level: level, context), kind)
        case .decorated(let decoration, let content):
            return (decorated(decoration, content, context), atomKind(node))
        case .stacked(let base, let over, let under):
            return (stacked(base: base, over: over, under: under, context), atomKind(node))
        case .environment(let environment):
            return (self.environment(environment, context), atomKind(node))
        case .classed(let kind, let content):
            return (layoutList(content, context), kind)
        case .lines(let lines):
            return (self.lines(lines, context), .ord)
        case .phantom(let content, let keepsWidth, let keepsHeight):
            var box = layoutList(content, context).withoutGlyphIdentity()
            box.inks = []
            if !keepsWidth { box.width = 0 }
            if !keepsHeight {
                box.ascent = 0
                box.descent = 0
            }
            return (box, .ord)
        case .boxed(let content):
            return (boxed(content, context), .ord)
        case .space(let amount):
            return (NoteMathBox(width: CGFloat(amount) * em(context)), .ord)
        case .styled(let variant, let content):
            return (layoutList(content, context.with(variant: variant)), atomKind(node))
        case .colored(let value, let content):
            return (layoutList(content, context.with(color: .custom(color(value)))), atomKind(node))
        case .mathStyle(let level, let content):
            return (layoutList(content, context.with(style: NoteMathStyle(level: level, cramped: context.style.cramped))), atomKind(node))
        }
    }

    func glyphBox(_ glyph: CGGlyph, size: CGFloat, color: NoteMathInkColor) -> NoteMathBox {
        let metrics = font.metrics(glyph)
        let scale = size / font.unitsPerEm
        var box = NoteMathBox()
        box.width = metrics.advance * scale
        if !metrics.bounds.isEmpty {
            box.ascent = max(0, metrics.bounds.maxY * scale)
            box.descent = max(0, -metrics.bounds.minY * scale)
        }
        box.italicCorrection = font.italicCorrection(glyph) * scale
        box.accentAttachment = font.topAccentAttachment(glyph).map { $0 * scale }
        box.glyph = glyph
        box.glyphSize = size
        box.inks = [NoteMathInk(content: .glyph(glyph, font.font(size: size)), origin: .zero, color: color)]
        return box
    }

    private func singleGlyph(_ symbol: String) -> CGGlyph? {
        let scalars = symbol.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first else { return nil }
        let glyph = font.glyph(for: scalar)
        return glyph == 0 ? nil : glyph
    }

    private func character(_ symbol: String, _ context: NoteMathContext) -> NoteMathBox {
        let mapped = NoteMathAlphabet.map(symbol, variant: context.variant)
        if let glyph = singleGlyph(mapped) { return glyphBox(glyph, size: size(context.style), color: context.color) }
        if mapped != symbol, let glyph = singleGlyph(symbol) {
            return glyphBox(glyph, size: size(context.style), color: context.color)
        }
        return textRun(mapped, context, style: .roman)
    }

    func textRun(_ text: String, _ context: NoteMathContext, style: NoteMathTextStyle, font override: CTFont? = nil) -> NoteMathBox {
        let ctFont = override ?? font.font(size: size(context.style))
        let attributes: [CFString: Any] = [kCTFontAttributeName: ctFont, kCTForegroundColorFromContextAttributeName: kCFBooleanTrue as Any]
        let mapped = override == nil ? NoteMathAlphabet.mapText(text, style: style) : text
        guard let string = CFAttributedStringCreate(kCFAllocatorDefault, mapped as CFString, attributes as CFDictionary) else {
            return NoteMathBox()
        }
        let line = CTLineCreateWithAttributedString(string)
        var box = NoteMathBox()
        box.width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let ink = CTLineGetImageBounds(line, nil)
        if !ink.isNull, !ink.isEmpty {
            box.ascent = max(0, ink.maxY)
            box.descent = max(0, -ink.minY)
        }
        box.inks = [NoteMathInk(content: .line(line), origin: .zero, color: context.color)]
        return box
    }

    private func largeOperator(_ symbol: String, _ context: NoteMathContext) -> NoteMathBox {
        guard var glyph = singleGlyph(symbol) else { return character(symbol, context) }
        if context.style.isDisplay, let construction = font.verticalConstruction(glyph) {
            let minimum = font.constants.displayOperatorMinHeight
            if font.metrics(glyph).bounds.height < minimum {
                for variant in construction.variants {
                    glyph = variant.glyph
                    if variant.advance >= minimum { break }
                }
            }
        }
        let box = glyphBox(glyph, size: size(context.style), color: context.color)
        let shift = (box.ascent - box.descent) / 2 - constant(.axisHeight, context)
        return box.raised(by: -shift)
    }

    private func nucleus(_ node: NoteMathNode?, _ context: NoteMathContext) -> Nucleus {
        guard let node else { return Nucleus(box: NoteMathBox()) }
        func wantsLimits(_ value: NoteMathLimits) -> Bool { value == .above || (value == .auto && context.style.isDisplay) }
        switch node {
        case .char(let symbol, _):
            let box = character(symbol, context)
            return Nucleus(box: box, isCharacter: box.glyph != nil)
        case .largeOperator(let symbol, let value):
            let resolved: NoteMathLimits = value == .auto && Self.integralSymbols.contains(symbol) ? .beside : value
            return Nucleus(box: largeOperator(symbol, context), isLargeOperator: true, usesLimits: wantsLimits(resolved))
        case .function(let name, let value):
            return Nucleus(box: textRun(name, context, style: .roman), usesLimits: wantsLimits(value))
        case .operatorName(let content, let value):
            return Nucleus(box: layoutList(content, context.with(variant: .roman)).withoutGlyphIdentity(), usesLimits: wantsLimits(value))
        case .classed(.op, let content):
            return Nucleus(box: layoutList(content, context).withoutGlyphIdentity(), usesLimits: context.style.isDisplay)
        case .decorated(.overbrace, _), .decorated(.underbrace, _):
            return Nucleus(box: layoutAtom(node, context).box, usesLimits: true, stretchStack: true)
        case .styled(let variant, let content) where content.count == 1:
            return nucleus(content[0], context.with(variant: variant))
        case .colored(let value, let content) where content.count == 1:
            return nucleus(content[0], context.with(color: .custom(color(value))))
        default:
            return Nucleus(box: layoutAtom(node, context).box.withoutGlyphIdentity())
        }
    }

    private func scripts(base node: NoteMathNode?, superscript upper: [NoteMathNode]?, subscript lower: [NoteMathNode]?,
                         _ context: NoteMathContext) -> NoteMathBox {
        let nucleus = self.nucleus(node, context)
        let superscriptBox = upper.map { layoutList($0, context.with(style: context.style.superscriptStyle)) }
        let subscriptBox = lower.map { layoutList($0, context.with(style: context.style.subscriptStyle)) }
        if nucleus.usesLimits {
            return limits(nucleus, over: superscriptBox, under: subscriptBox, context)
        }
        let base = nucleus.box
        let value = { (name: NoteMathConstant) in self.constant(name, context) }
        var up: CGFloat = 0
        var down: CGFloat = 0
        if !nucleus.isCharacter {
            up = base.ascent - value(.superscriptBaselineDropMax)
            down = base.descent + value(.subscriptBaselineDropMin)
        }
        let shiftUp = value(context.style.cramped ? .superscriptShiftUpCramped : .superscriptShiftUp)
        switch (superscriptBox, subscriptBox) {
        case (let sup?, nil):
            up = max(up, shiftUp, sup.descent + value(.superscriptBottomMin))
        case (nil, let sub?):
            down = max(down, value(.subscriptShiftDown), sub.ascent - value(.subscriptTopMax))
        case (let sup?, let sub?):
            up = max(up, shiftUp, sup.descent + value(.superscriptBottomMin))
            down = max(down, value(.subscriptShiftDown))
            let gap = (up - sup.descent) - (sub.ascent - down)
            if gap < value(.subSuperscriptGapMin) {
                down += value(.subSuperscriptGapMin) - gap
                let lift = value(.superscriptBottomMaxWithSubscript) - (up - sup.descent)
                if lift > 0 {
                    up += lift
                    down -= lift
                }
            }
        case (nil, nil):
            break
        }
        var box = NoteMathBox(width: base.width, ascent: base.ascent, descent: base.descent)
        box.draw(base, at: .zero)
        var superscriptX = base.width + (nucleus.isLargeOperator ? 0 : base.italicCorrection)
        var subscriptX = base.width - (nucleus.isLargeOperator ? base.italicCorrection : 0)
        let kernSet = nucleus.isCharacter ? base.glyph.flatMap { font.kernSet($0) } : nil
        if let sup = superscriptBox {
            if kernSet != nil || sup.glyph.flatMap({ font.kernSet($0)?.bottomLeft }) != nil {
                superscriptX += cornerKern(base: base, baseKern: kernSet?.topRight, script: sup,
                                           scriptKern: sup.glyph.flatMap { font.kernSet($0)?.bottomLeft },
                                           heights: [up - sup.descent, base.ascent], shift: up)
            }
            box.draw(sup, at: CGPoint(x: superscriptX, y: up))
            box.width = max(box.width, superscriptX + sup.width)
            box.ascent = max(box.ascent, up + sup.ascent)
            box.descent = max(box.descent, sup.descent - up)
        }
        if let sub = subscriptBox {
            if kernSet != nil || sub.glyph.flatMap({ font.kernSet($0)?.topLeft }) != nil {
                subscriptX += cornerKern(base: base, baseKern: kernSet?.bottomRight, script: sub,
                                         scriptKern: sub.glyph.flatMap { font.kernSet($0)?.topLeft },
                                         heights: [sub.ascent - down, -base.descent], shift: -down)
            }
            box.draw(sub, at: CGPoint(x: subscriptX, y: -down))
            box.width = max(box.width, subscriptX + sub.width)
            box.ascent = max(box.ascent, sub.ascent - down)
            box.descent = max(box.descent, down + sub.descent)
        }
        box.width += value(.spaceAfterScript)
        return box
    }

    private func cornerKern(base: NoteMathBox, baseKern: NoteMathKern?, script: NoteMathBox, scriptKern: NoteMathKern?,
                            heights: [CGFloat], shift: CGFloat) -> CGFloat {
        let baseScale = base.glyphSize / font.unitsPerEm
        let scriptScale = script.glyphSize / font.unitsPerEm
        var best = -CGFloat.infinity
        for height in heights {
            var kern: CGFloat = 0
            if let baseKern, baseScale > 0 { kern += baseKern.value(at: height / baseScale) * baseScale }
            if let scriptKern, scriptScale > 0 { kern += scriptKern.value(at: (height - shift) / scriptScale) * scriptScale }
            best = max(best, kern)
        }
        return best.isFinite ? best : 0
    }

    private func limits(_ nucleus: Nucleus, over: NoteMathBox?, under: NoteMathBox?, _ context: NoteMathContext) -> NoteMathBox {
        let base = nucleus.box
        let value = { (name: NoteMathConstant) in self.constant(name, context) }
        let italic = nucleus.isLargeOperator ? base.italicCorrection : 0
        let center = base.width / 2
        var items: [(box: NoteMathBox, point: CGPoint)] = [(base, .zero)]
        var ascent = base.ascent
        var descent = base.descent
        if let over {
            let shift = nucleus.stretchStack
                ? max(value(.stretchStackTopShiftUp), base.ascent + value(.stretchStackGapAboveMin) + over.descent)
                : base.ascent + max(value(.upperLimitBaselineRiseMin), value(.upperLimitGapMin) + over.descent)
            items.append((over, CGPoint(x: center - over.width / 2 + italic / 2, y: shift)))
            ascent = max(ascent, shift + over.ascent)
        }
        if let under {
            let shift = nucleus.stretchStack
                ? max(value(.stretchStackBottomShiftDown), base.descent + value(.stretchStackGapBelowMin) + under.ascent)
                : base.descent + max(value(.lowerLimitBaselineDropMin), value(.lowerLimitGapMin) + under.ascent)
            items.append((under, CGPoint(x: center - under.width / 2 - italic / 2, y: -shift)))
            descent = max(descent, shift + under.descent)
        }
        let minX = items.map(\.point.x).min() ?? 0
        let maxX = items.map { $0.point.x + $0.box.width }.max() ?? 0
        var box = NoteMathBox(width: maxX - minX, ascent: ascent, descent: descent)
        for item in items { box.draw(item.box, at: CGPoint(x: item.point.x - minX, y: item.point.y)) }
        return box
    }

    private func fraction(_ fraction: NoteMathFraction, _ context: NoteMathContext) -> NoteMathBox {
        var context = context
        if let level = fraction.level { context.style = NoteMathStyle(level: level, cramped: context.style.cramped) }
        let numerator = layoutList(fraction.numerator, context.with(style: context.style.numerator))
        let denominator = layoutList(fraction.denominator, context.with(style: context.style.denominator))
        let display = context.style.isDisplay
        let value = { (name: NoteMathConstant) in self.constant(name, context) }
        let axis = value(.axisHeight)
        var up: CGFloat
        var down: CGFloat
        let thickness = fraction.hasRule ? value(.fractionRuleThickness) : 0
        if fraction.hasRule {
            up = max(value(display ? .fractionNumeratorDisplayStyleShiftUp : .fractionNumeratorShiftUp),
                     axis + thickness / 2 + value(display ? .fractionNumDisplayStyleGapMin : .fractionNumeratorGapMin) + numerator.descent)
            down = max(value(display ? .fractionDenominatorDisplayStyleShiftDown : .fractionDenominatorShiftDown),
                       value(display ? .fractionDenomDisplayStyleGapMin : .fractionDenominatorGapMin) + denominator.ascent - (axis - thickness / 2))
        } else {
            up = value(display ? .stackTopDisplayStyleShiftUp : .stackTopShiftUp)
            down = value(display ? .stackBottomDisplayStyleShiftDown : .stackBottomShiftDown)
            let minimum = value(display ? .stackDisplayStyleGapMin : .stackGapMin)
            let gap = (up - numerator.descent) - (denominator.ascent - down)
            if gap < minimum {
                up += (minimum - gap) / 2
                down += (minimum - gap) / 2
            }
        }
        let padding = fraction.left == nil && fraction.right == nil ? 0.12 * em(context) : 0
        let inner = max(numerator.width, denominator.width)
        var box = NoteMathBox(width: inner + padding * 2, ascent: up + numerator.ascent, descent: down + denominator.descent)
        box.draw(numerator, at: CGPoint(x: padding + (inner - numerator.width) / 2, y: up))
        box.draw(denominator, at: CGPoint(x: padding + (inner - denominator.width) / 2, y: -down))
        if fraction.hasRule {
            box.inks.append(NoteMathInk(content: .rule(CGSize(width: inner + padding * 2 - 0.0001, height: thickness)),
                                        origin: CGPoint(x: 0, y: axis - thickness / 2), color: context.color))
        }
        guard fraction.left != nil || fraction.right != nil else { return box }
        let minimum = (display ? 2.39 : 1.01) * em(context)
        let target = max(minimum, delimiterTarget(ascent: box.ascent, descent: box.descent, context))
        var row = NoteMathRow()
        row.append(delimiter(fraction.left, target: target, context))
        row.append(box)
        row.append(delimiter(fraction.right, target: target, context))
        return row.box
    }

    private func radical(_ radicand: [NoteMathNode], degree: [NoteMathNode]?, _ context: NoteMathContext) -> NoteMathBox {
        let inner = layoutList(radicand, context.with(style: context.style.crampedStyle))
        let value = { (name: NoteMathConstant) in self.constant(name, context) }
        var gap = value(context.style.isDisplay ? .radicalDisplayStyleVerticalGap : .radicalVerticalGap)
        let thickness = value(.radicalRuleThickness)
        let target = inner.height + gap + thickness
        var surd = verticalStretch("√", target: target, context)
        if surd.height > target { gap += (surd.height - target) / 2 }
        let top = inner.ascent + gap + thickness
        surd = surd.raised(by: top - surd.ascent)
        var box = NoteMathBox()
        var x: CGFloat = 0
        var ascent = top + value(.radicalExtraAscender)
        if let degree {
            let degreeBox = layoutList(degree, context.with(style: NoteMathStyle(level: .scriptScript, cramped: true)))
            let raise = font.constants.radicalDegreeBottomRaisePercent / 100 * surd.height
            let baseline = -surd.descent + raise + degreeBox.descent
            let before = value(.radicalKernBeforeDegree)
            let after = value(.radicalKernAfterDegree)
            box.draw(degreeBox, at: CGPoint(x: before, y: baseline))
            x = max(0, before + degreeBox.width + after)
            ascent = max(ascent, baseline + degreeBox.ascent)
            box.descent = max(box.descent, degreeBox.descent - baseline)
        }
        box.draw(surd, at: CGPoint(x: x, y: 0))
        box.draw(inner, at: CGPoint(x: x + surd.width, y: 0))
        box.inks.append(NoteMathInk(content: .rule(CGSize(width: inner.width, height: thickness)),
                                    origin: CGPoint(x: x + surd.width, y: top - thickness), color: context.color))
        box.width = x + surd.width + inner.width
        box.ascent = ascent
        box.descent = max(box.descent, inner.descent, surd.descent)
        return box
    }

    func delimiterTarget(ascent: CGFloat, descent: CGFloat, _ context: NoteMathContext) -> CGFloat {
        let axis = constant(.axisHeight, context)
        let delta = max(ascent - axis, descent + axis)
        return max(delta * 2 * 0.901, delta * 2 - 0.5 * em(context))
    }

    private func delimiter(_ symbol: String?, target: CGFloat, _ context: NoteMathContext) -> NoteMathBox {
        guard let symbol else { return NoteMathBox(width: 0.12 * em(context)) }
        let box = verticalStretch(symbol, target: target, context)
        let shift = (box.ascent - box.descent) / 2 - constant(.axisHeight, context)
        return box.raised(by: -shift).withoutGlyphIdentity()
    }

    private func fenced(left: String?, right: String?, middles: [String?], segments: [[NoteMathNode]],
                        _ context: NoteMathContext) -> NoteMathBox {
        let boxes = segments.map { layoutList($0, context) }
        let ascent = boxes.map(\.ascent).max() ?? 0
        let descent = boxes.map(\.descent).max() ?? 0
        let target = delimiterTarget(ascent: ascent, descent: descent, context)
        var row = NoteMathRow()
        row.append(delimiter(left, target: target, context))
        for (index, box) in boxes.enumerated() {
            if index > 0, index - 1 < middles.count { row.append(delimiter(middles[index - 1], target: target, context)) }
            row.append(box)
        }
        row.append(delimiter(right, target: target, context))
        return row.box
    }

    private func sizedDelimiter(_ symbol: String?, level: Int, _ context: NoteMathContext) -> NoteMathBox {
        let heights: [CGFloat] = [1.2, 1.8, 2.4, 3.0]
        let target = heights[min(max(level, 1), 4) - 1] * em(context)
        return delimiter(symbol, target: target * 0.92, context)
    }

    func verticalStretch(_ symbol: String, target: CGFloat, _ context: NoteMathContext) -> NoteMathBox {
        guard let glyph = singleGlyph(symbol) else { return character(symbol, context.with(variant: .roman)) }
        let scale = self.scale(context)
        let size = self.size(context.style)
        if font.metrics(glyph).bounds.height * scale >= target { return glyphBox(glyph, size: size, color: context.color) }
        guard let construction = font.verticalConstruction(glyph) else { return glyphBox(glyph, size: size, color: context.color) }
        for variant in construction.variants where variant.advance * scale >= target {
            return glyphBox(variant.glyph, size: size, color: context.color)
        }
        if !construction.parts.isEmpty { return assembly(construction, target: target, vertical: true, context) }
        return glyphBox(construction.variants.last?.glyph ?? glyph, size: size, color: context.color)
    }

    func horizontalStretch(_ symbol: String, target: CGFloat, _ context: NoteMathContext) -> NoteMathBox? {
        guard let glyph = singleGlyph(symbol) else { return nil }
        let scale = self.scale(context)
        let size = self.size(context.style)
        if font.metrics(glyph).advance * scale >= target { return glyphBox(glyph, size: size, color: context.color) }
        guard let construction = font.horizontalConstruction(glyph) else { return glyphBox(glyph, size: size, color: context.color) }
        for variant in construction.variants where variant.advance * scale >= target {
            return glyphBox(variant.glyph, size: size, color: context.color)
        }
        if !construction.parts.isEmpty { return assembly(construction, target: target, vertical: false, context) }
        return glyphBox(construction.variants.last?.glyph ?? glyph, size: size, color: context.color)
    }

    private func assembly(_ construction: NoteMathGlyphConstruction, target: CGFloat, vertical: Bool,
                          _ context: NoteMathContext) -> NoteMathBox {
        let scale = self.scale(context)
        let minimumOverlap = font.minConnectorOverlap * scale
        let parts = construction.parts
        let hasExtender = parts.contains(where: \.isExtender)
        var repeats = 0
        var expanded: [NoteMathGlyphPart] = []
        while true {
            expanded = parts.flatMap { $0.isExtender ? Array(repeating: $0, count: repeats) : [$0] }
            let total = expanded.reduce(0) { $0 + $1.fullAdvance * scale } - minimumOverlap * CGFloat(max(expanded.count - 1, 0))
            if total >= target || !hasExtender || repeats >= 400 { break }
            repeats += 1
        }
        guard !expanded.isEmpty else { return NoteMathBox() }
        let sum = expanded.reduce(0) { $0 + $1.fullAdvance * scale }
        let connections = expanded.count - 1
        var overlap: CGFloat = 0
        if connections > 0 {
            var maximum = CGFloat.infinity
            for index in 0..<connections {
                maximum = min(maximum, min(expanded[index].endConnector, expanded[index + 1].startConnector) * scale)
            }
            let desired = (sum - target) / CGFloat(connections)
            overlap = max(min(desired, maximum), min(minimumOverlap, maximum))
        }
        let size = self.size(context.style)
        let ctFont = font.font(size: size)
        var box = NoteMathBox()
        var position: CGFloat = 0
        for part in expanded {
            let metrics = font.metrics(part.glyph)
            if vertical {
                box.inks.append(NoteMathInk(content: .glyph(part.glyph, ctFont),
                                            origin: CGPoint(x: 0, y: position - metrics.bounds.minY * scale), color: context.color))
                box.width = max(box.width, metrics.advance * scale)
            } else {
                box.inks.append(NoteMathInk(content: .glyph(part.glyph, ctFont), origin: CGPoint(x: position, y: 0), color: context.color))
                box.ascent = max(box.ascent, metrics.bounds.maxY * scale)
                box.descent = max(box.descent, -metrics.bounds.minY * scale)
            }
            position += part.fullAdvance * scale - overlap
        }
        let total = position + overlap
        if vertical {
            box.ascent = total
            box.descent = 0
        } else {
            box.width = total
        }
        box.italicCorrection = construction.assemblyItalicCorrection * scale
        return box
    }

    private func decorated(_ decoration: NoteMathDecoration, _ content: [NoteMathNode], _ context: NoteMathContext) -> NoteMathBox {
        let value = { (name: NoteMathConstant) in self.constant(name, context) }
        switch decoration {
        case .accent(let mark):
            return accent(mark, wide: false, content, context)
        case .wideAccent(let mark):
            return accent(mark, wide: true, content, context)
        case .overline:
            let base = layoutList(content, context.with(style: context.style.crampedStyle))
            let gap = value(.overbarVerticalGap), thickness = value(.overbarRuleThickness)
            var box = NoteMathBox(width: base.width, ascent: base.ascent + gap + thickness + value(.overbarExtraAscender), descent: base.descent)
            box.draw(base, at: .zero)
            box.inks.append(NoteMathInk(content: .rule(CGSize(width: base.width, height: thickness)),
                                        origin: CGPoint(x: 0, y: base.ascent + gap), color: context.color))
            return box
        case .underline:
            let base = layoutList(content, context)
            let gap = value(.underbarVerticalGap), thickness = value(.underbarRuleThickness)
            var box = NoteMathBox(width: base.width, ascent: base.ascent, descent: base.descent + gap + thickness + value(.underbarExtraDescender))
            box.draw(base, at: .zero)
            box.inks.append(NoteMathInk(content: .rule(CGSize(width: base.width, height: thickness)),
                                        origin: CGPoint(x: 0, y: -(base.descent + gap + thickness)), color: context.color))
            return box
        case .overbrace:
            return stretchedStack("\u{23DE}", over: true, content, context)
        case .underbrace:
            return stretchedStack("\u{23DF}", over: false, content, context)
        case .overArrow(let arrow):
            if let mark = Self.overArrowMarks[arrow] { return stretchyMark(mark, above: true, content, context) }
            return stretchedStack(arrow, over: true, content, context)
        case .underArrow(let arrow):
            if let mark = Self.underArrowMarks[arrow] { return stretchyMark(mark, above: false, content, context) }
            return stretchedStack(arrow, over: false, content, context)
        }
    }

    private static let overArrowMarks: [String: String] = ["→": "\u{20D7}", "←": "\u{20D6}", "↔": "\u{20E1}"]
    private static let underArrowMarks: [String: String] = ["→": "\u{20EF}", "←": "\u{20EE}"]

    func inkExtent(_ box: NoteMathBox) -> CGRect {
        var extent = CGRect.null
        for ink in box.inks {
            var bounds: CGRect
            switch ink.content {
            case .glyph(let glyph, let ctFont):
                let scale = CTFontGetSize(ctFont) / font.unitsPerEm
                let metrics = font.metrics(glyph).bounds
                bounds = CGRect(x: metrics.minX * scale, y: metrics.minY * scale, width: metrics.width * scale, height: metrics.height * scale)
            case .rule(let size):
                bounds = CGRect(origin: .zero, size: size)
            case .line(let line):
                bounds = CTLineGetImageBounds(line, nil)
            }
            guard !bounds.isNull, !bounds.isEmpty else { continue }
            extent = extent.union(bounds.offsetBy(dx: ink.origin.x, dy: ink.origin.y))
        }
        return extent.isNull ? CGRect(x: 0, y: -box.descent, width: box.width, height: box.height) : extent
    }

    private func stretchyMark(_ mark: String, above: Bool, _ content: [NoteMathNode], _ context: NoteMathContext) -> NoteMathBox {
        let base = layoutList(content, above ? context.with(style: context.style.crampedStyle) : context)
        guard let stretched = horizontalStretch(mark, target: base.width, context) else { return base }
        let ink = inkExtent(stretched)
        let x = base.width / 2 - ink.midX
        let y = above ? max(0, base.ascent - constant(.accentBaseHeight, context)) : -base.descent
        let left = min(0, x + ink.minX)
        let right = max(base.width, x + ink.maxX)
        var box = NoteMathBox(width: right - left, ascent: max(base.ascent, y + ink.maxY), descent: max(base.descent, -(y + ink.minY)))
        box.draw(base, at: CGPoint(x: -left, y: 0))
        box.draw(stretched, at: CGPoint(x: x - left, y: y))
        return box
    }

    private func accent(_ mark: String, wide: Bool, _ content: [NoteMathNode], _ context: NoteMathContext) -> NoteMathBox {
        let inner = context.with(style: context.style.crampedStyle)
        let base = content.count == 1 ? nucleus(content[0], inner).box : layoutList(content, inner)
        guard var glyph = singleGlyph(mark) else { return base }
        let scale = self.scale(context)
        if wide, let construction = font.horizontalConstruction(glyph) {
            for variant in construction.variants {
                if variant.advance * scale <= base.width * 1.05 { glyph = variant.glyph } else { break }
            }
        }
        let accent = glyphBox(glyph, size: size(context.style), color: context.color)
        let accentAttachment = accent.accentAttachment ?? font.metrics(glyph).bounds.midX * scale
        let baseAttachment = base.accentAttachment ?? (base.width + (base.glyph != nil ? base.italicCorrection : 0)) / 2
        let shift = max(0, base.ascent - constant(.accentBaseHeight, context))
        var box = NoteMathBox(width: base.width, ascent: base.ascent, descent: base.descent)
        box.draw(base, at: .zero)
        box.draw(accent, at: CGPoint(x: baseAttachment - accentAttachment, y: shift))
        let accentTop = font.metrics(glyph).bounds.maxY * scale + shift
        box.ascent = max(base.ascent, accentTop)
        box.italicCorrection = base.italicCorrection
        return box
    }

    private func stretchedStack(_ symbol: String, over: Bool, _ content: [NoteMathNode], _ context: NoteMathContext) -> NoteMathBox {
        let base = layoutList(content, over ? context.with(style: context.style.crampedStyle) : context)
        let value = { (name: NoteMathConstant) in self.constant(name, context) }
        guard let stretched = horizontalStretch(symbol, target: base.width, context) else { return base }
        let ink = inkExtent(stretched)
        let inkBottom = ink.minY
        let inkTop = ink.maxY
        let width = max(base.width, stretched.width)
        var box = NoteMathBox(width: width, ascent: base.ascent, descent: base.descent)
        box.draw(base, at: CGPoint(x: (width - base.width) / 2, y: 0))
        let x = (width - stretched.width) / 2
        if over {
            let y = base.ascent + value(.stretchStackGapBelowMin) - inkBottom
            box.draw(stretched, at: CGPoint(x: x, y: y))
            box.ascent = y + inkTop
        } else {
            let y = -(base.descent + value(.stretchStackGapAboveMin)) - inkTop
            box.draw(stretched, at: CGPoint(x: x, y: y))
            box.descent = -(y + inkBottom)
        }
        return box
    }

    private func stacked(base: [NoteMathNode], over: [NoteMathNode]?, under: [NoteMathNode]?, _ context: NoteMathContext) -> NoteMathBox {
        let baseBox = layoutList(base, context).withoutGlyphIdentity()
        let overBox = over.map { layoutList($0, context.with(style: context.style.superscriptStyle)) }
        let underBox = under.map { layoutList($0, context.with(style: context.style.subscriptStyle)) }
        return limits(Nucleus(box: baseBox), over: overBox, under: underBox, context)
    }

    private func boxed(_ content: [NoteMathNode], _ context: NoteMathContext) -> NoteMathBox {
        let inner = layoutList(content, context)
        let padding = 0.3 * em(context), thickness = 0.04 * em(context)
        let inset = padding + thickness
        var box = NoteMathBox(width: inner.width + inset * 2, ascent: inner.ascent + inset, descent: inner.descent + inset)
        box.draw(inner, at: CGPoint(x: inset, y: 0))
        let frames = [
            CGRect(x: 0, y: -box.descent, width: box.width, height: thickness),
            CGRect(x: 0, y: box.ascent - thickness, width: box.width, height: thickness),
            CGRect(x: 0, y: -box.descent, width: thickness, height: box.height),
            CGRect(x: box.width - thickness, y: -box.descent, width: thickness, height: box.height),
        ]
        for frame in frames {
            box.inks.append(NoteMathInk(content: .rule(frame.size), origin: frame.origin, color: context.color))
        }
        return box
    }

    private struct GridShape {
        var cellStyle: NoteMathStyleLevel
        var columns: [NoteMathColumnAlignment]
        var gaps: (Int) -> CGFloat
        var outerPadding: CGFloat
        var strutAscent: CGFloat
        var strutDescent: CGFloat
        var rowGap: CGFloat
        var padsRelations: Bool
    }

    private func environment(_ environment: NoteMathEnvironment, _ context: NoteMathContext) -> NoteMathBox {
        let em = self.em(context)
        let script = context.style.isScript
        let baselineSkip = 1.2 * em
        var shape = GridShape(cellStyle: script ? context.style.level : .text, columns: environment.columns,
                              gaps: { _ in em }, outerPadding: 0, strutAscent: 0.7 * baselineSkip,
                              strutDescent: 0.3 * baselineSkip, rowGap: 0, padsRelations: false)
        switch environment.kind {
        case .matrix:
            break
        case .smallMatrix:
            shape.cellStyle = .script
            shape.gaps = { _ in em * 0.3 }
            shape.strutAscent = 0.7 * baselineSkip * 0.6
            shape.strutDescent = 0.3 * baselineSkip * 0.6
        case .cases:
            shape.strutAscent *= 1.2
            shape.strutDescent *= 1.2
        case .aligned:
            shape.cellStyle = script ? context.style.level : .display
            shape.gaps = { $0.isMultiple(of: 2) ? 0 : em }
            shape.rowGap = 0.3 * em
            shape.padsRelations = true
        case .gathered:
            shape.cellStyle = script ? context.style.level : .display
            shape.rowGap = 0.3 * em
        case .array:
            shape.outerPadding = 0.5 * em
        }
        let grid = self.grid(environment, shape: shape, context)
        guard environment.left != nil || environment.right != nil else { return grid }
        let target = delimiterTarget(ascent: grid.ascent, descent: grid.descent, context)
        var row = NoteMathRow()
        row.append(delimiter(environment.left, target: target, context))
        row.append(grid)
        row.append(delimiter(environment.right, target: target, context))
        return row.box
    }

    private func lines(_ lines: [[NoteMathNode]], _ context: NoteMathContext) -> NoteMathBox {
        let em = self.em(context)
        let environment = NoteMathEnvironment(kind: .gathered, rows: lines.map { [$0] }, columns: [.center])
        let shape = GridShape(cellStyle: context.style.level, columns: [.center], gaps: { _ in 0 }, outerPadding: 0,
                              strutAscent: 0.84 * em, strutDescent: 0.36 * em, rowGap: 0.3 * em, padsRelations: false)
        return grid(environment, shape: shape, context)
    }

    private func grid(_ environment: NoteMathEnvironment, shape: GridShape, _ context: NoteMathContext) -> NoteMathBox {
        let em = self.em(context)
        let cellContext = context.with(style: NoteMathStyle(level: shape.cellStyle, cramped: false))
        let columnCount = max(shape.columns.count, environment.rows.map(\.count).max() ?? 0, 1)
        let cells: [[NoteMathBox]] = environment.rows.map { row in
            row.enumerated().map { column, nodes in
                let padded = shape.padsRelations && !column.isMultiple(of: 2) ? [NoteMathNode.group([])] + nodes : nodes
                return layoutList(padded, cellContext)
            }
        }
        var widths = [CGFloat](repeating: 0, count: columnCount)
        for row in cells {
            for (column, cell) in row.enumerated() { widths[column] = max(widths[column], cell.width) }
        }
        var columnX: [CGFloat] = []
        var x = shape.outerPadding
        for column in 0..<columnCount {
            columnX.append(x)
            x += widths[column] + (column < columnCount - 1 ? shape.gaps(column) : 0)
        }
        let totalWidth = x + shape.outerPadding
        let ruleThickness = 0.04 * em
        let rowRules = Set(environment.rowRules)
        var baselines: [CGFloat] = []
        var ascents: [CGFloat] = []
        var descents: [CGFloat] = []
        var y: CGFloat = 0
        for (index, row) in cells.enumerated() {
            let ascent = max(shape.strutAscent, row.map(\.ascent).max() ?? 0)
            let descent = max(shape.strutDescent, row.map(\.descent).max() ?? 0)
            if index > 0 {
                y -= descents[index - 1] + ascent + shape.rowGap
                y -= CGFloat(environment.rowSpacing[index - 1] ?? 0) * em
                if rowRules.contains(index) { y -= ruleThickness }
            }
            baselines.append(y)
            ascents.append(ascent)
            descents.append(descent)
        }
        var top = ascents.first ?? 0
        var bottom = (baselines.last ?? 0) - (descents.last ?? 0)
        var box = NoteMathBox(width: totalWidth)
        for (rowIndex, row) in cells.enumerated() {
            for (column, cell) in row.enumerated() {
                let alignment = column < shape.columns.count ? shape.columns[column] : .center
                let offset: CGFloat
                switch alignment {
                case .left: offset = 0
                case .center: offset = (widths[column] - cell.width) / 2
                case .right: offset = widths[column] - cell.width
                }
                box.draw(cell, at: CGPoint(x: columnX[column] + offset, y: baselines[rowIndex]))
            }
        }
        var rules: [CGRect] = []
        for rule in environment.rowRules.sorted() {
            if rule == 0 {
                rules.append(CGRect(x: 0, y: top, width: totalWidth, height: ruleThickness))
                top += ruleThickness
            } else if rule >= cells.count {
                bottom -= ruleThickness
                rules.append(CGRect(x: 0, y: bottom, width: totalWidth, height: ruleThickness))
            } else {
                let edge = baselines[rule - 1] - descents[rule - 1]
                rules.append(CGRect(x: 0, y: edge - ruleThickness, width: totalWidth, height: ruleThickness))
            }
        }
        for boundary in environment.columnRules {
            let ruleX: CGFloat
            if boundary <= 0 {
                ruleX = 0
            } else if boundary >= columnCount {
                ruleX = totalWidth - ruleThickness
            } else {
                ruleX = columnX[boundary] - shape.gaps(boundary - 1) / 2 - ruleThickness / 2
            }
            rules.append(CGRect(x: ruleX, y: bottom, width: ruleThickness, height: top - bottom))
        }
        for rule in rules {
            box.inks.append(NoteMathInk(content: .rule(rule.size), origin: rule.origin, color: context.color))
        }
        box.ascent = top
        box.descent = -bottom
        let shift = constant(.axisHeight, context) - (top + bottom) / 2
        return box.raised(by: shift)
    }
}

enum NoteMathAlphabet {
    private static let greekLowerExtras: [UInt32: UInt32] = [0x2202: 51, 0x03F5: 52, 0x03D1: 53, 0x03F0: 54, 0x03D5: 55, 0x03F1: 56, 0x03D6: 57]
    private static let italicHoles: [UInt32: UInt32] = [0x1D455: 0x210E]
    private static let scriptHoles: [UInt32: UInt32] = [
        0x1D49D: 0x212C, 0x1D4A0: 0x2130, 0x1D4A1: 0x2131, 0x1D4A3: 0x210B, 0x1D4A4: 0x2110, 0x1D4A7: 0x2112,
        0x1D4A8: 0x2133, 0x1D4AD: 0x211B, 0x1D4BA: 0x212F, 0x1D4BC: 0x210A, 0x1D4C4: 0x2134,
    ]
    private static let frakturHoles: [UInt32: UInt32] = [0x1D506: 0x212D, 0x1D50B: 0x210C, 0x1D50C: 0x2111, 0x1D515: 0x211C, 0x1D51D: 0x2128]
    private static let doubleStruckHoles: [UInt32: UInt32] = [
        0x1D53A: 0x2102, 0x1D53F: 0x210D, 0x1D545: 0x2115, 0x1D547: 0x2119, 0x1D548: 0x211A, 0x1D549: 0x211D, 0x1D551: 0x2124,
    ]

    static func map(_ text: String, variant: NoteMathVariant) -> String {
        let scalars = text.unicodeScalars
        guard variant != .roman, scalars.count == 1, let scalar = scalars.first else { return text }
        return String(map(scalar, variant))
    }

    static func mapText(_ text: String, style: NoteMathTextStyle) -> String {
        let variant: NoteMathVariant
        switch style {
        case .roman: return text
        case .bold: variant = .bold
        case .italic: variant = .italic
        case .sansSerif: variant = .sansSerif
        case .monospace: variant = .monospace
        }
        var result = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let isLatin = (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value) || (0x30...0x39).contains(scalar.value)
            result.append(isLatin ? map(scalar, variant) : scalar)
        }
        return String(result)
    }

    static func map(_ scalar: Unicode.Scalar, _ variant: NoteMathVariant) -> Unicode.Scalar {
        let value = scalar.value
        let upper = (0x41...0x5A).contains(value)
        let lower = (0x61...0x7A).contains(value)
        let digit = (0x30...0x39).contains(value)
        let latinIndex = upper ? value - 0x41 : lower ? value - 0x61 + 26 : nil
        let greekUpper = (0x391...0x3A9).contains(value) && value != 0x3A2
        let greekLower = (0x3B1...0x3C9).contains(value) || greekLowerExtras[value] != nil
        let greekIndex: UInt32? = greekUpper ? value - 0x391 : (0x3B1...0x3C9).contains(value) ? value - 0x3B1 + 26
            : greekLowerExtras[value] ?? (value == 0x2207 ? 25 : nil)
        func latin(_ base: UInt32, holes: [UInt32: UInt32] = [:]) -> Unicode.Scalar {
            guard let latinIndex else { return scalar }
            let mapped = base + latinIndex
            return Unicode.Scalar(holes[mapped] ?? mapped) ?? scalar
        }
        func greek(_ base: UInt32) -> Unicode.Scalar {
            guard let greekIndex else { return scalar }
            return Unicode.Scalar(base + greekIndex) ?? scalar
        }
        func digits(_ base: UInt32) -> Unicode.Scalar {
            Unicode.Scalar(base + value - 0x30) ?? scalar
        }
        switch variant {
        case .roman:
            return scalar
        case .normal:
            if latinIndex != nil { return latin(0x1D434, holes: italicHoles) }
            if greekLower, value != 0x2207 { return greek(0x1D6E2) }
            if value == 0x131 { return Unicode.Scalar(0x1D6A4) ?? scalar }
            if value == 0x237 { return Unicode.Scalar(0x1D6A5) ?? scalar }
            return scalar
        case .italic:
            if latinIndex != nil { return latin(0x1D434, holes: italicHoles) }
            if greekUpper || greekLower { return greek(0x1D6E2) }
            return scalar
        case .bold:
            if latinIndex != nil { return latin(0x1D400) }
            if digit { return digits(0x1D7CE) }
            if greekIndex != nil { return greek(0x1D6A8) }
            return scalar
        case .boldItalic:
            if latinIndex != nil { return latin(0x1D468) }
            if digit { return digits(0x1D7CE) }
            if greekLower { return greek(0x1D71C) }
            if greekIndex != nil { return greek(0x1D6A8) }
            return scalar
        case .doubleStruck:
            if latinIndex != nil { return latin(0x1D538, holes: doubleStruckHoles) }
            if digit { return digits(0x1D7D8) }
            return scalar
        case .script:
            return latin(0x1D49C, holes: scriptHoles)
        case .fraktur:
            return latin(0x1D504, holes: frakturHoles)
        case .sansSerif:
            if digit { return digits(0x1D7E2) }
            return latin(0x1D5A0)
        case .monospace:
            if digit { return digits(0x1D7F6) }
            return latin(0x1D670)
        }
    }
}
