import Foundation
import Testing
@testable import ParcCore

struct EaselStoreStylePersistenceTests {
    @MainActor @Test
    func textStylesAndTheirUnicodeTextSurviveADurableReload() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            let styles = EaselTextStyle.Family.allCases.flatMap { family in
                EaselTextStyle.Size.allCases.map { EaselTextStyle(family: family, size: $0) }
            }
            try session.perform("Add styles") { document in
                document.items = styles.map { EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "A\n👩🏽‍💻", textStyle: $0) }
            }
            let fresh = try EaselStore(directory: directory).load(session.document.id)
            #expect(fresh.document.items.map(\.resolvedTextStyle) == styles, "All twenty styles survive durable reload")
            #expect(fresh.document.items.map(\.text) == session.document.items.map(\.text), "Style persistence preserves Unicode and line breaks")
        }
    }

    @MainActor @Test
    func olderTextUsesTheOriginalDefaultStyle() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            let styles = EaselTextStyle.Family.allCases.flatMap { family in
                EaselTextStyle.Size.allCases.map { EaselTextStyle(family: family, size: $0) }
            }
            try session.perform("Add styles") { document in
                document.items = styles.map { EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "A\n👩🏽‍💻", textStyle: $0) }
            }
            let url = EaselStoreTestsSupport.file(directory, session.document.id)
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
            var items = json["items"] as! [[String: Any]]
            for index in items.indices { items[index].removeValue(forKey: "textStyle") }
            json["items"] = items
            try JSONSerialization.data(withJSONObject: json).write(to: url)
            let legacy = try EaselStore(directory: directory).load(session.document.id)
            #expect(legacy.document.items.allSatisfy { $0.textStyle == nil && $0.resolvedTextStyle == EaselTextStyle() }, "Existing v1 documents retain clean/body without a migration write")
        }
    }

    @MainActor @Test
    func unknownTextStylesAreRefusedOnLoad() throws {
        try EaselStoreTestsSupport.withDirectory { directory in
            let session = try EaselStore(directory: directory).create()
            let styles = EaselTextStyle.Family.allCases.flatMap { family in
                EaselTextStyle.Size.allCases.map { EaselTextStyle(family: family, size: $0) }
            }
            try session.perform("Add styles") { document in
                document.items = styles.map { EaselItem(kind: .text, frame: EaselStoreTestsSupport.frame, text: "A\n👩🏽‍💻", textStyle: $0) }
            }
            let url = EaselStoreTestsSupport.file(directory, session.document.id)
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
            var items = json["items"] as! [[String: Any]]
            for index in items.indices { items[index].removeValue(forKey: "textStyle") }
            json["items"] = items
            try JSONSerialization.data(withJSONObject: json).write(to: url)
            items[0]["textStyle"] = ["family": "unknown", "size": "body"]
            json["items"] = items
            try JSONSerialization.data(withJSONObject: json).write(to: url)
            EaselStoreTestsSupport.expectThrows("unknown styles are preserved as a load error, never silently normalized") { _ = try EaselStore(directory: directory).load(session.document.id) }
        }
    }
}
