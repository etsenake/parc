import CoreServices
import Foundation
import Testing
@testable import Parc

struct ExternalMediaWatchEventTests {
    private final class Batches: @unchecked Sendable {
        private let lock = NSLock()
        private var received: [ExternalMediaWatcher.Batch] = []
        func add(_ batch: ExternalMediaWatcher.Batch) {
            lock.lock()
            defer { lock.unlock() }
            received.append(batch)
        }
        var all: [ExternalMediaWatcher.Batch] {
            lock.lock()
            defer { lock.unlock() }
            return received
        }
    }

    @Test func folderEventsCanonicalizeAndCoalesceOnlyDirectMediaChildren() throws {
        let batches = Batches()
        let sink = ExternalMediaWatcher.Sink(aliases: ["/fixture/selected": "/Volumes/Photos"], handler: { batches.add($0) })
        let events = [
            "/fixture/selected/photo.png", "/fixture/selected/photo.png",
            "/fixture/selected/nested/movie.mov", "/fixture/selected/notes.txt",
            "/not-selected/other.png", "/fixture/selected/video.mov",
        ]
        let flags = Array(repeating: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified), count: events.count)
        flags.withUnsafeBufferPointer { sink.receive(events, $0) }
        let batch = try #require(batches.all.first)
        guard case .paths(let paths) = batch else { Issue.record("Expected file updates"); return }
        #expect(paths == ["/Volumes/Photos/photo.png", "/Volumes/Photos/video.mov"])
    }

    @Test(arguments: [
        FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped),
        FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged),
        FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed),
    ])
    func losingTheWatchedRootOrEventsRequestsARescan(_ flag: FSEventStreamEventFlags) throws {
        let batches = Batches()
        let root = "/Volumes/Photos"
        let sink = ExternalMediaWatcher.Sink(aliases: [root: root], handler: { batches.add($0) })
        [flag].withUnsafeBufferPointer { sink.receive([root], $0) }
        let batch = try #require(batches.all.first)
        guard case .rescan = batch else { Issue.record("Expected a rescan for the changed root"); return }
    }
}

struct ExternalMediaCloudPresenterTests {
    private final class Driver: @unchecked Sendable {
        private let lock = NSLock()
        private var jobs: [(delay: TimeInterval, run: @Sendable () -> Void)] = []
        private var presenters: [String: any NSFilePresenter] = [:]
        private var reports: [Set<String>] = []

        private func locked<T>(_ work: () -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return work()
        }

        private func schedule(_ delay: TimeInterval, _ job: @escaping @Sendable () -> Void) {
            locked { jobs.append((delay, job)) }
        }

        private func add(_ presenter: any NSFilePresenter) {
            guard let path = presenter.presentedItemURL?.path else { return }
            locked { presenters[path] = presenter }
        }

        private func remove(_ presenter: any NSFilePresenter) {
            guard let path = presenter.presentedItemURL?.path else { return }
            locked {
                if presenters[path] === presenter { presenters[path] = nil }
            }
        }

        func source() -> ExternalMediaCloudStatus {
            ExternalMediaCloudStatus(handler: { [weak self] paths in self?.report(paths) },
                registry: .init(add: { [weak self] in self?.add($0) }, remove: { [weak self] in self?.remove($0) }),
                schedule: { [weak self] in self?.schedule($0, $1) })
        }

        private func report(_ paths: Set<String>) { locked { reports.append(paths) } }
        var batches: [Set<String>] { locked { reports } }
        var installed: Set<String> { locked { Set(presenters.keys) } }
        func presenter(_ path: String) -> (any NSFilePresenter)? { locked { presenters[path] } }

        func advance(_ delay: TimeInterval = 0) {
            let ready = locked {
                let ready = jobs.filter { $0.delay == delay }
                jobs.removeAll { $0.delay == delay }
                return ready
            }
            ready.forEach { $0.run() }
        }
    }

    @Test func repeatedPresentationKeepsOnePresenterPerFolder() throws {
        let driver = Driver(), source = driver.source()
        let folder = "/fixture/Synced"
        source.present([folder])
        driver.advance()
        let first = try #require(driver.presenter(folder))
        source.present([folder])
        driver.advance()
        #expect(driver.installed == [folder] && driver.presenter(folder) === first)
    }

    @Test func cloudReportsBatchOnlyDirectMediaChildren() throws {
        let driver = Driver(), source = driver.source()
        let folder = "/fixture/Synced"
        source.present([folder])
        driver.advance()
        let presenter = try #require(driver.presenter(folder))
        presenter.presentedSubitemDidChange?(at: URL(fileURLWithPath: folder + "/capture.png"))
        presenter.presentedSubitemDidChange?(at: URL(fileURLWithPath: folder + "/nested/hidden.png"))
        presenter.presentedSubitemDidChange?(at: URL(fileURLWithPath: folder + "/notes.txt"))
        presenter.presentedSubitemDidChange?(at: URL(fileURLWithPath: folder + "/video.mov"))
        driver.advance()
        #expect(driver.batches.isEmpty)
        driver.advance(0.3)
        #expect(driver.batches == [[folder + "/capture.png", folder + "/video.mov"]])
    }

    @Test func removingAFolderReleasesItsPresenter() {
        let driver = Driver(), source = driver.source()
        let folder = "/fixture/Synced"
        source.present([folder])
        driver.advance()
        source.present([])
        driver.advance()
        #expect(driver.installed.isEmpty)
    }

    @Test func retiringTheCloudSourceUnregistersAllItsPresenters() {
        let driver = Driver()
        var source: ExternalMediaCloudStatus? = driver.source()
        source?.present(["/fixture/First", "/fixture/Second"])
        driver.advance()
        #expect(driver.installed.count == 2)
        source = nil
        driver.advance()
        #expect(driver.installed.isEmpty)
    }
}
