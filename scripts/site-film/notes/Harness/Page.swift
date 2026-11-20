import AppKit

@MainActor enum ArticlePage {
    static func draw(in card: NSRect) {
        NSColor.white.setFill(); card.fill()
        let ink = hex(0x202122), soft = hex(0x54595D), rule = hex(0xA2A9B1, 0.6), link = hex(0x3366CC)
        let column = min(760, card.width - 96)
        let left = card.minX + max(48, (card.width - column - 260) / 2)
        var y = card.minY + 44
        func text(_ string: String, _ font: NSFont, _ color: NSColor, at x: CGFloat, width: CGFloat, spacing: CGFloat = 0) -> CGFloat {
            let style = NSMutableParagraphStyle(); style.lineSpacing = spacing
            let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
            let bounds = attributed.boundingRect(with: NSSize(width: width, height: 2000), options: [.usesLineFragmentOrigin, .usesFontLeading])
            attributed.draw(with: NSRect(x: x, y: y, width: width, height: ceil(bounds.height)), options: [.usesLineFragmentOrigin, .usesFontLeading])
            return ceil(bounds.height)
        }
        let serif = NSFont(name: "Georgia", size: 30) ?? .systemFont(ofSize: 30)
        y += text("Urban park", serif, ink, at: left, width: column)
        y += 8
        rule.setFill(); NSRect(x: left, y: y, width: column + 260, height: 1).fill()
        y += 10
        y += text("From the free encyclopedia", .systemFont(ofSize: 12.5), soft, at: left, width: column)
        y += 18
        let infoX = left + column + 24, infoWidth: CGFloat = 236
        let infoTop = y
        let body = NSFont.systemFont(ofSize: 14.5)
        let paragraphs = [
            "An urban park or metropolitan park, also known as a municipal park or a public park, is a park in cities and other incorporated places that offers recreation and green space to residents of, and visitors to, the municipality.",
            "The design, operation, and maintenance are usually done by government agencies, typically on the local level, but may occasionally be contracted out to a park conservancy, \"friends of\" group, or private sector company.",
            "Common features of municipal parks include playgrounds, gardens, hiking, running and fitness trails or paths, bridle paths, sports fields and courts, public restrooms, boat ramps, and picnic facilities, depending on the budget and natural features available.",
        ]
        for paragraph in paragraphs {
            y += text(paragraph, body, ink, at: left, width: column - 8, spacing: 4)
            y += 14
        }
        y += 6
        y += text("History", NSFont(name: "Georgia", size: 22) ?? .systemFont(ofSize: 22), ink, at: left, width: column)
        y += 6
        rule.setFill(); NSRect(x: left, y: y, width: column - 8, height: 1).fill()
        y += 12
        let history = [
            "Parks in cities grew out of the landscaped grounds of large estates and the common grazing land of towns. As cities expanded in the nineteenth century, reformers argued that every neighbourhood deserved fresh air and open lawns within walking distance.",
            "Many of the best-known city parks were laid out in that period, with winding carriage drives, meadows framed by groves of trees, and lakes made from former marshland.",
        ]
        for paragraph in history {
            y += text(paragraph, body, ink, at: left, width: column - 8, spacing: 4)
            y += 14
        }
        let saved = y
        y = infoTop
        let infoBox = NSRect(x: infoX, y: infoTop, width: infoWidth, height: 330)
        hex(0xF8F9FA).setFill(); infoBox.fill()
        hex(0xC8CCD1).setStroke(); NSBezierPath(rect: infoBox.insetBy(dx: 0.5, dy: 0.5)).stroke()
        let art = NSRect(x: infoX + 10, y: infoTop + 10, width: infoWidth - 20, height: 160)
        drawPark(in: art)
        y = art.maxY + 10
        y += text("A summer afternoon in a city park", .systemFont(ofSize: 12), soft, at: infoX + 12, width: infoWidth - 24)
        y += 12
        for (key, value) in [("Type", "Public green space"), ("Managed by", "Municipal parks department"), ("Open", "Dawn to dusk"), ("Features", "Lawns, trails, playgrounds")] {
            _ = text(key, .boldSystemFont(ofSize: 12), ink, at: infoX + 12, width: 80)
            y += text(value, .systemFont(ofSize: 12), link, at: infoX + 96, width: infoWidth - 108) + 8
        }
        _ = saved
    }

    static func drawPark(in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        NSGradient(starting: hex(0xBFE3F7), ending: hex(0xEAF6FC))!.draw(in: rect, angle: 90)
        let ground = NSRect(x: rect.minX, y: rect.minY + rect.height * 0.58, width: rect.width, height: rect.height * 0.42)
        NSGradient(starting: hex(0x7FBF6A), ending: hex(0x5FA351))!.draw(in: ground, angle: 90)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + rect.width * 0.42, y: rect.maxY))
        path.curve(to: NSPoint(x: rect.minX + rect.width * 0.55, y: ground.minY),
                   controlPoint1: NSPoint(x: rect.minX + rect.width * 0.62, y: rect.maxY - 30),
                   controlPoint2: NSPoint(x: rect.minX + rect.width * 0.40, y: ground.minY + 22))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.58, y: ground.minY))
        path.curve(to: NSPoint(x: rect.minX + rect.width * 0.62, y: rect.maxY),
                   controlPoint1: NSPoint(x: rect.minX + rect.width * 0.48, y: ground.minY + 24),
                   controlPoint2: NSPoint(x: rect.minX + rect.width * 0.80, y: rect.maxY - 34))
        path.close()
        hex(0xE9DFC7).setFill(); path.fill()
        let trees: [(CGFloat, CGFloat, CGFloat, UInt32)] = [(0.08, 0.50, 30, 0x3E8E4A), (0.22, 0.46, 38, 0x4A9A55), (0.36, 0.52, 26, 0x357F42),
                                                            (0.72, 0.47, 36, 0x418F4C), (0.88, 0.51, 30, 0x2F7A3D), (0.98, 0.45, 34, 0x4C9C58)]
        for (fx, fy, radius, color) in trees {
            let center = NSPoint(x: rect.minX + rect.width * fx, y: rect.minY + rect.height * fy)
            hex(0x6B4F32).setFill()
            NSRect(x: center.x - 2.5, y: center.y, width: 5, height: radius * 0.9).fill()
            hex(color).setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius * 1.1, width: radius * 2, height: radius * 1.7)).fill()
        }
        hex(0xFFFFFF, 0.85).setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.minX + rect.width * 0.55, y: rect.minY + 14, width: 46, height: 14)).fill()
        NSBezierPath(ovalIn: NSRect(x: rect.minX + rect.width * 0.62, y: rect.minY + 8, width: 34, height: 14)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
