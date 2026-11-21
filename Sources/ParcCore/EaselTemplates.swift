import Foundation

package enum EaselTemplate: String, CaseIterable, Identifiable {
    case brainstorm, retro, kanban, flowchart, weeklyPlan, mindMap, moodboard

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .brainstorm: return "Brainstorm"
        case .retro: return "Retro"
        case .kanban: return "Kanban"
        case .flowchart: return "Flowchart"
        case .weeklyPlan: return "Weekly Plan"
        case .mindMap: return "Mind Map"
        case .moodboard: return "Moodboard"
        }
    }

    package var blurb: String {
        switch self {
        case .brainstorm: return "One big question, lots of stickies"
        case .retro: return "What went well, what to fix, what to try"
        case .kanban: return "To do, doing, done"
        case .flowchart: return "Start, steps and a yes-or-no fork"
        case .weeklyPlan: return "Goals up top, a column per weekday"
        case .mindMap: return "A topic with branches to grow"
        case .moodboard: return "Pictures, colors and words in one place"
        }
    }

    package var keywords: [String] {
        switch self {
        case .brainstorm: return ["ideas", "storm", "workshop"]
        case .retro: return ["retrospective", "review", "sprint"]
        case .kanban: return ["board", "tasks", "todo", "columns"]
        case .flowchart: return ["diagram", "process", "flow", "decision"]
        case .weeklyPlan: return ["week", "planner", "schedule", "calendar"]
        case .mindMap: return ["mind", "map", "branches", "topic"]
        case .moodboard: return ["mood", "inspiration", "pictures", "colours"]
        }
    }
}

package struct EaselTemplateDrawing: Equatable {
    package var items: [EaselItem]
    package var bounds: EaselRect
}

package enum EaselTemplates {
    package static let margin = EaselPoint(x: 48, y: 56)

    package static func drawing(_ template: EaselTemplate) -> EaselTemplateDrawing {
        var builder = Builder()
        switch template {
        case .brainstorm: builder.brainstorm()
        case .retro: builder.retro()
        case .kanban: builder.kanban()
        case .flowchart: builder.flowchart()
        case .weeklyPlan: builder.weeklyPlan()
        case .mindMap: builder.mindMap()
        case .moodboard: builder.moodboard()
        }
        let items = builder.items
        let bounds = EaselArrange.union(items.map(\.frame)) ?? EaselRect(x: 0, y: 0, width: 0, height: 0)
        return EaselTemplateDrawing(items: items, bounds: bounds)
    }

    package static func placed(_ template: EaselTemplate, centeredAt center: EaselPoint, within visible: EaselRect? = nil,
                       firstZIndex: Int) -> EaselTemplateDrawing {
        let base = drawing(template)
        var x = center.x - base.bounds.width / 2, y = center.y - base.bounds.height / 2
        if let visible {
            if base.bounds.width > visible.width - 2 * margin.x { x = visible.x + margin.x }
            if base.bounds.height > visible.height - 2 * margin.y { y = visible.y + margin.y }
        }
        x = max(margin.x, x).rounded()
        y = max(margin.y, y).rounded()
        let dx = x - base.bounds.x, dy = y - base.bounds.y
        let order = Dictionary(base.items.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let items = base.items.map { source -> EaselItem in
            var item = source
            item.frame.x += dx
            item.frame.y += dy
            item.zIndex = firstZIndex + (order[source.id] ?? 0)
            return item
        }
        return EaselTemplateDrawing(items: items, bounds: EaselRect(x: x, y: y, width: base.bounds.width, height: base.bounds.height))
    }

    private struct Builder {
        var items: [EaselItem] = []

        static func sticky(_ color: NoteColor) -> String { EaselPalette.stored(.note(color), role: .sticky) }
        static func fill(_ color: NoteColor) -> String { EaselPalette.stored(.note(color), role: .fill) }
        static func ink(_ color: NoteColor) -> String { EaselPalette.stored(.note(color), role: .ink) }

        @discardableResult
        mutating func add(_ item: EaselItem) -> EaselItem {
            items.append(item)
            return item
        }

        @discardableResult
        mutating func title(_ text: String, x: Double, y: Double, width: Double = 520) -> EaselItem {
            var style = EaselTextStyle()
            style.size = .h1
            return add(EaselItem(kind: .text, frame: EaselRect(x: x, y: y, width: width, height: 64), text: text, textStyle: style))
        }

        @discardableResult
        mutating func label(_ text: String, x: Double, y: Double, width: Double, size: EaselTextStyle.Size = .h2) -> EaselItem {
            var style = EaselTextStyle()
            style.size = size
            return add(EaselItem(kind: .text, frame: EaselRect(x: x, y: y, width: width, height: size == .body ? 28 : 40),
                                 text: text, textStyle: style))
        }

        @discardableResult
        mutating func sticky(_ text: String, x: Double, y: Double, color: NoteColor, wide: Bool = false) -> EaselItem {
            let width = wide ? EaselBoardObjects.stickyWideWidth : EaselBoardObjects.stickySide
            var item = EaselItem(kind: .sticky, frame: EaselRect(x: x, y: y, width: width, height: EaselBoardObjects.stickySide), text: text)
            item.fill = Self.sticky(color)
            return add(item)
        }

        @discardableResult
        mutating func section(_ text: String, x: Double, y: Double, width: Double, height: Double, color: NoteColor? = nil) -> EaselItem {
            var item = EaselItem(kind: .section, frame: EaselRect(x: x, y: y, width: width, height: height), text: text)
            if let color { item.fill = Self.fill(color) }
            return add(item)
        }

        @discardableResult
        mutating func shape(_ shape: EaselShape, _ text: String, x: Double, y: Double, width: Double, height: Double,
                            color: NoteColor, dash: EaselStrokeDash? = nil) -> EaselItem {
            var item = EaselItem(kind: shape == .ellipse ? .circle : .rectangle,
                                 frame: EaselRect(x: x, y: y, width: width, height: height), text: text)
            if shape != .ellipse && shape != .rectangle { item.shape = shape }
            item.fill = Self.fill(color)
            item.color = Self.ink(color)
            item.strokeDash = dash
            return add(item)
        }

        mutating func connect(_ start: EaselItem, _ startSide: EaselConnection.Side, to end: EaselItem, _ endSide: EaselConnection.Side,
                              label: String = "", routing: EaselConnectorRouting = .elbow) {
            let a = EaselConnectorAttachment.magnet(startSide, on: start)
            let b = EaselConnectorAttachment.magnet(endSide, on: end)
            let geometry = EaselToolGeometry.lineItemGeometry(from: a, to: b)
            var item = EaselItem(kind: .arrow, frame: geometry.frame, text: label, points: geometry.points)
            if routing != .straight { item.routing = routing }
            item.startConnection = EaselConnection(itemID: start.id, side: startSide)
            item.endConnection = EaselConnection(itemID: end.id, side: endSide)
            add(item)
        }

        mutating func brainstorm() {
            title("Brainstorm", x: 0, y: 0)
            shape(.ellipse, "What are we solving?", x: 320, y: 340, width: 300, height: 180, color: .purple)
            let colors: [NoteColor] = [.yellow, .pink, .blue, .green, .yellow, .orange, .blue, .pink]
            let prompts = ["Wild idea", "What if…", "Quick win", "Ask a user", "Borrow from elsewhere", "Flip it around",
                           "Make it smaller", "Dream big"]
            let spots: [(Double, Double)] = [(0, 100), (360, 90), (720, 100), (720, 340), (720, 590), (360, 580), (0, 590), (0, 340)]
            for (index, spot) in spots.enumerated() {
                sticky(prompts[index], x: spot.0, y: spot.1 + 20, color: colors[index])
            }
        }

        mutating func retro() {
            title("Retro", x: 0, y: 0)
            let columns: [(String, NoteColor, [String])] = [
                ("Went well", .green, ["Shipped on time", "Great teamwork"]),
                ("To improve", .orange, ["Too many meetings", "Unclear owners"]),
                ("Try next", .blue, ["Daily check-in", "Demo every Friday"]),
            ]
            for (index, column) in columns.enumerated() {
                let x = Double(index) * 312
                section(column.0, x: x, y: 112, width: 284, height: 560, color: column.1)
                for (row, text) in column.2.enumerated() {
                    sticky(text, x: x + 32, y: 152 + Double(row) * 252, color: column.1)
                }
            }
        }

        mutating func kanban() {
            title("Kanban", x: 0, y: 0)
            let columns: [(String, [String])] = [
                ("To do", ["Write the brief", "Book the room", "Gather feedback"]),
                ("Doing", ["Sketch ideas", "Draft the plan"]),
                ("Done", ["Kick off"]),
            ]
            let colors: [NoteColor] = [.yellow, .blue, .green]
            for (index, column) in columns.enumerated() {
                let x = Double(index) * 312
                section(column.0, x: x, y: 112, width: 284, height: 808)
                for (row, text) in column.1.enumerated() {
                    sticky(text, x: x + 32, y: 152 + Double(row) * 252, color: colors[index])
                }
            }
        }

        mutating func flowchart() {
            title("Flowchart", x: 0, y: 0)
            let start = shape(.roundedRectangle, "Start", x: 80, y: 112, width: 200, height: 72, color: .green)
            let step = shape(.rectangle, "Do the thing", x: 80, y: 264, width: 200, height: 96, color: .blue)
            let check = shape(.diamond, "Did it work?", x: 60, y: 440, width: 240, height: 160, color: .yellow)
            let fix = shape(.rectangle, "Tweak it", x: 420, y: 472, width: 200, height: 96, color: .orange)
            let done = shape(.roundedRectangle, "Done", x: 80, y: 680, width: 200, height: 72, color: .purple)
            connect(start, .bottom, to: step, .top)
            connect(step, .bottom, to: check, .top)
            connect(check, .right, to: fix, .left, label: "No")
            connect(fix, .top, to: step, .right)
            connect(check, .bottom, to: done, .top, label: "Yes")
        }

        mutating func weeklyPlan() {
            title("Weekly Plan", x: 0, y: 0)
            sticky("This week’s goals", x: 0, y: 96, color: .purple, wide: true)
            let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
            let colors: [NoteColor] = [.yellow, .orange, .pink, .blue, .green]
            for (index, day) in days.enumerated() {
                let x = Double(index) * 284
                section(day, x: x, y: 384, width: 260, height: 520)
                sticky("Plan", x: x + 20, y: 420, color: colors[index])
            }
            label("Notes for next week", x: 0, y: 936, width: 400)
        }

        mutating func mindMap() {
            var topic = EaselItem(kind: .circle, frame: EaselRect(x: 380, y: 300, width: 240, height: 140), text: "Main topic")
            topic.fill = Self.fill(.purple)
            topic.color = Self.ink(.purple)
            topic.mindMap = EaselMindMapLink()
            add(topic)
            let branches: [(String, Double, NoteColor, EaselMindMapLink.Side?)] = [
                ("Idea", 80, .blue, .left), ("Question", 80, .green, nil), ("Next step", 330, .orange, .left),
                ("Resource", 330, .pink, nil), ("Example", 580, .yellow, .left), ("Open loop", 580, .red, nil),
            ]
            for branch in branches {
                var node = shape(.roundedRectangle, branch.0, x: branch.3 == .left ? 0 : 760, y: branch.1, width: 200, height: 80, color: branch.2)
                items.removeLast()
                node.mindMap = EaselMindMapLink(parent: topic.id, side: branch.3)
                add(node)
            }
            let laidOut = EaselMindMap.tidied(EaselDocument(id: UUID(), title: "Mind Map", createdAt: Date(timeIntervalSinceReferenceDate: 0),
                                                            modifiedAt: Date(timeIntervalSinceReferenceDate: 0), items: items))
            items = laidOut.items.filter { $0.kind == .arrow } + laidOut.items.filter { $0.kind != .arrow }
        }

        mutating func moodboard() {
            title("Moodboard", x: 0, y: 0)
            section("Pictures", x: 0, y: 112, width: 720, height: 520)
            let frames: [(Double, Double, Double, Double)] = [(32, 152, 320, 220), (376, 152, 312, 300), (32, 396, 320, 204), (376, 476, 312, 124)]
            for frame in frames {
                shape(.roundedRectangle, "Drop a picture", x: frame.0, y: frame.1, width: frame.2, height: frame.3, color: .gray, dash: .dashed)
            }
            section("Colors", x: 752, y: 112, width: 296, height: 248)
            let swatches: [NoteColor] = [.pink, .orange, .yellow, .green, .blue, .purple]
            for (index, color) in swatches.enumerated() {
                let x = 784 + Double(index % 3) * 84, y = 152 + Double(index / 3) * 92
                var swatch = EaselItem(kind: .circle, frame: EaselRect(x: x, y: y, width: 64, height: 64))
                swatch.fill = Self.sticky(color)
                swatch.strokeWidth = 0
                add(swatch)
            }
            section("Words", x: 752, y: 384, width: 296, height: 248)
            sticky("Cozy, bright, playful", x: 790, y: 404, color: .yellow)
        }
    }
}
