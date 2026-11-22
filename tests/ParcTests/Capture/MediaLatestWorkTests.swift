import Testing
@testable import ParcLibrary

struct MediaLatestWorkTests {
    @MainActor private final class Driver {
        let (finished, finish) = AsyncStream<Int>.makeStream()
        var releases: [AsyncStream<Void>.Continuation] = []
        var cancelled: [Int] = []
        var requests: [Int] = []
        lazy var latest = MediaLibraryLatestWork<Int> { [unowned self] work in
            let (gate, release) = AsyncStream<Void>.makeStream()
            releases.append(release)
            return Task {
                var iterator = gate.makeAsyncIterator()
                _ = await iterator.next()
                let result = try work()
                if Task.isCancelled { cancelled.append(result) }
                return result
            }
        }

        deinit { releases.forEach { $0.finish() }; finish.finish() }

        @discardableResult
        func start(_ value: Int) -> Task<Void, Never>? {
            latest.start { [weak self] in
                self?.requests.append(value)
                return (work: { value }, finish: { self?.finish.yield($0) })
            }
        }

        func release(_ worker: Int) { releases[worker].yield() }
    }

    @MainActor @Test func newerGridWorkCancelsThePreviousWorkerAndPublishesOnlyTheLatest() async throws {
        let driver = Driver()
        let previous = try #require(driver.start(1))
        let current = try #require(driver.start(2))
        driver.release(1)
        await previous.value
        await current.value
        #expect(driver.cancelled == [1])
        var finished = driver.finished.makeAsyncIterator()
        let value = await finished.next()
        #expect(value == 2 && !driver.latest.isRunning)
    }

    @MainActor @Test func explicitlyCancelingGridWorkDropsItsLateResult() async throws {
        let driver = Driver()
        let running = try #require(driver.start(1))
        driver.latest.cancel()
        await running.value
        driver.finish.finish()
        var finished = driver.finished.makeAsyncIterator()
        let value = await finished.next()
        #expect(value == nil && !driver.latest.isRunning)
    }

    @MainActor @Test func sustainedUpdatesCompleteOneGridPlanThenReadOnlyTheLatestWaitingRequest() async throws {
        let driver = Driver()
        let first = try #require(driver.start(1))
        let second = try #require(driver.start(2))
        let third = try #require(driver.start(3))
        driver.start(4)
        driver.start(5)
        #expect(driver.requests == [1, 2, 3])
        await first.value
        await second.value
        driver.release(2)
        await third.value
        #expect(driver.requests == [1, 2, 3, 5])
        driver.release(3)
        var finished = driver.finished.makeAsyncIterator()
        let inFlight = await finished.next()
        let latest = await finished.next()
        #expect(inFlight == 3 && latest == 5)
    }
}
