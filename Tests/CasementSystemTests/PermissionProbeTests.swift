import Foundation
import Testing
@testable import CasementCore
@testable import CasementSystem

/// Settings → Permissions showed "Checking…" against the Downloads folder and both automation
/// rows and never resolved. Asking macOS whether Casement may automate a running app does not
/// return: against Spotify, open at the time, AEDeterminePermissionToAutomateTarget was still
/// inside the call after thirty seconds, while the same call against Music, which was closed,
/// returned procNotFound in under a millisecond. Every probe shared one serial queue, so that
/// single call parked the rest behind it.
@Suite struct PermissionProbeTests {
    /// Runs `body` on the main runloop, which the probe reports on, for up to `seconds`.
    func spin(_ seconds: TimeInterval, until done: @escaping () -> Bool) {
        let end = Date().addingTimeInterval(seconds)
        while !done(), Date() < end {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    @Test func aProbeThatNeverAnswersStillGivesTheRowSomethingToSay() async throws {
        let seen = Locked<[PermissionStatus]>([])
        PermissionProbe.probing(within: 0.2, provisional: .unknown, {
            Thread.sleep(forTimeInterval: 30)      // the blocked AE call, in miniature
            return .granted
        }, { seen.append($0) })
        spin(3) { !seen.value.isEmpty }
        #expect(seen.value == [.unknown], "the row must stop saying Checking without waiting for a call that may never return")
    }

    @Test func theRealAnswerReplacesTheProvisionalOne() async throws {
        let seen = Locked<[PermissionStatus]>([])
        PermissionProbe.probing(within: 0.1, provisional: .unknown, {
            Thread.sleep(forTimeInterval: 0.5)
            return .denied
        }, { seen.append($0) })
        spin(4) { seen.value.count >= 2 }
        #expect(seen.value == [.unknown, .denied], "provisional first, then the truth")
    }

    @Test func aProbeThatAnswersInTimeIsReportedOnlyOnce() async throws {
        let seen = Locked<[PermissionStatus]>([])
        PermissionProbe.probing(within: 2, provisional: .unknown, { .granted }, { seen.append($0) })
        spin(1) { !seen.value.isEmpty }
        // Past the deadline, to be sure nothing follows it.
        spin(2.5) { false }
        #expect(seen.value == [.granted], "a probe that answered must not be contradicted by its own deadline")
    }

    @Test func oneBlockedProbeDoesNotHoldUpAnother() async throws {
        let fast = Locked<[PermissionStatus]>([])
        PermissionProbe.probing(within: 60, provisional: .unknown, {
            Thread.sleep(forTimeInterval: 30)      // the Spotify call
            return .granted
        }, { _ in })
        PermissionProbe.probing(within: 60, provisional: .unknown, { .denied }, { fast.append($0) })
        spin(3) { !fast.value.isEmpty }
        #expect(fast.value == [.denied], "the queue has to be concurrent: on a serial one this waits thirty seconds")
    }

    @Test func askingHasNoDeadline() async throws {
        let seen = Locked<[PermissionStatus]>([])
        PermissionProbe.probing(within: nil, provisional: .unknown, {
            Thread.sleep(forTimeInterval: 0.4)
            return .granted
        }, { seen.append($0) })
        spin(3) { !seen.value.isEmpty }
        #expect(seen.value == [.granted], "a prompt waits for the user, so nothing may answer in their place")
    }
}

/// A box the probe reports into from the main thread and the test reads while spinning it.
final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
    func mutate(_ change: (inout T) -> Void) { lock.lock(); change(&stored); lock.unlock() }
}

extension Locked where T == [PermissionStatus] {
    func append(_ status: PermissionStatus) { mutate { $0.append(status) } }
}
