import AppKit
import ApplicationServices
import AVFoundation
import CoreServices
import CasementCore

/// Reads and requests the permissions listed in Settings → Permissions. Reading never prompts.
/// Automation and the Downloads folder are checked off the main thread, because macOS can take a
/// moment (or, when asking, wait for the user); completions run on the main thread.
/// Calendars and Reminders are requested through `CalendarService`, which owns the event store.
public enum PermissionProbe {
    /// Concurrent, because the probes are independent and one of them blocks. Asking macOS
    /// whether Casement may automate a RUNNING app does not return: measured on 2026-10-16,
    /// AEDeterminePermissionToAutomateTarget against Spotify while Spotify was open was still
    /// inside the call after thirty seconds, while the same call against Music, which was not
    /// open, returned procNotFound in under a millisecond. On a serial queue that one call
    /// parked every probe behind it, so Settings → Permissions showed "Checking…" against the
    /// Downloads folder and both automation rows for as long as the window stayed open.
    private static let queue = DispatchQueue(label: "casement.permissions", qos: .userInitiated,
                                             attributes: .concurrent)

    /// How long a probe may take before the row is given a provisional answer. A permissions row
    /// that never resolves reads as a broken app, and "Asked on first use" is both true and the
    /// thing that will actually happen. The real answer replaces it whenever it arrives, which
    /// for a blocked automation check may be never.
    static let answerWithin: TimeInterval = 2

    /// Runs `probe` off the main thread and reports on the main thread, with `provisional` sent
    /// instead if nothing has come back within `within`. `completion` may therefore run twice:
    /// once provisionally and once for real, in that order. Every caller writes the status into
    /// a row, so the second call simply corrects the first.
    /// `within` is nil when there is no deadline, which is the case while macOS is showing the
    /// user a prompt: that takes as long as the user takes and must never be cut short. Adding
    /// an infinite TimeInterval to a DispatchTime is not the way to say this; it overflows.
    static func probing(within: TimeInterval? = answerWithin, provisional: PermissionStatus,
                        _ probe: @escaping () -> PermissionStatus,
                        _ completion: @escaping (PermissionStatus) -> Void) {
        let answered = Answered()
        queue.async {
            let result = probe()
            answered.mark()
            DispatchQueue.main.async { completion(result) }
        }
        guard let within else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + within) {
            if !answered.isMarked { completion(provisional) }
        }
    }

    /// Whether the real answer has arrived. Written on the probe's thread and read on the main
    /// one, so it is behind a lock rather than a plain Bool.
    final class Answered: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func mark() { lock.lock(); value = true; lock.unlock() }
        var isMarked: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }
    /// Accessibility has no "not asked yet" state, so remember whether this session has asked.
    private static var askedForAccessibility = false

    public static var downloadsFolder: URL { CasementPaths.home.appendingPathComponent("Downloads") }

    /// The current status. Reading the Downloads folder would prompt the first time, so it is
    /// only read when `readDownloads` is true (the downloads module is on, or the user asked).
    public static func status(of kind: PermissionKind, readDownloads: Bool,
                              completion: @escaping (PermissionStatus) -> Void) {
        switch kind {
        case .accessibility:
            completion(AXIsProcessTrusted() ? .granted : askedForAccessibility ? .denied : .notDetermined)
        case .calendars:
            completion(.calendar(CalendarService.eventAccess))
        case .reminders:
            completion(.calendar(CalendarService.reminderAccess))
        case .location:
            completion(status(LocationProvider.access))
        case .camera:
            completion(CameraMirror.access)
        case .downloadsFolder:
            guard readDownloads else { return completion(.unknown) }
            readFolder(completion)
        case .automationMusic, .automationSpotify:
            automation(kind, ask: false, completion: completion)
        }
    }

    /// Ask macOS, which shows its own prompt if it hasn't asked before, then report the status.
    /// Accessibility's prompt points to System Settings, so the answer arrives later: check
    /// again when Casement becomes active.
    public static func request(_ kind: PermissionKind, completion: @escaping (PermissionStatus) -> Void) {
        switch kind {
        case .accessibility:
            askedForAccessibility = true
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            completion(AXIsProcessTrustedWithOptions([key: true] as CFDictionary) ? .granted : .denied)
        case .downloadsFolder:
            readFolder(completion)
        case .automationMusic, .automationSpotify:
            automation(kind, ask: true, completion: completion)
        case .location:
            // Asking for a position is what brings up macOS's question; the answer is the status.
            let provider = LocationProvider()
            provider.requestLocation { _ in
                withExtendedLifetime(provider) { completion(status(LocationProvider.access)) }
            }
        case .camera:
            CameraMirror.requestAccess(completion)
        case .calendars, .reminders:
            status(of: kind, readDownloads: false, completion: completion)
        }
    }

    static func status(_ access: LocationProvider.Access) -> PermissionStatus {
        switch access {
        case .granted: return .granted
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        }
    }

    /// Listing the folder is what the downloads module does; the first time, macOS asks. The
    /// listing itself can sit behind TCC, so it gets the same deadline as the automation checks.
    private static func readFolder(_ completion: @escaping (PermissionStatus) -> Void) {
        let folder = downloadsFolder
        probing(provisional: .unknown, {
            do {
                _ = try FileManager.default.contentsOfDirectory(atPath: folder.path)
                return .granted
            } catch let error as NSError {
                let posix = (error.userInfo[NSUnderlyingErrorKey] as? NSError)?.code
                return error.code == NSFileReadNoPermissionError || posix == Int(EPERM) || posix == Int(EACCES)
                    ? .denied : .unknown
            }
        }, completion)
    }

    /// Never launches the other app: macOS can only answer while it is open.
    private static func automation(_ kind: PermissionKind, ask: Bool, completion: @escaping (PermissionStatus) -> Void) {
        guard let bundleID = kind.automationTarget,
              NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else {
            return completion(.appNotInstalled)
        }
        // Asking takes as long as the user takes, so a prompt is never cut short by the deadline.
        probing(within: ask ? nil : answerWithin, provisional: .unknown, {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
            let code = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
            return PermissionStatus.automation(code)
        }, { result in
            NotificationCenter.default.post(name: .casementAutomationStatus, object: bundleID, userInfo: ["status": result])
            completion(result)
        })
    }
}

public extension Notification.Name {
    /// Every Automation answer from macOS, posted on the main thread. The object is the target
    /// app's bundle ID and `userInfo["status"]` its `PermissionStatus`. The Music and Spotify
    /// providers listen, so an Allow in Settings → Permissions takes effect at once.
    static let casementAutomationStatus = Notification.Name("CasementAutomationStatus")
}
