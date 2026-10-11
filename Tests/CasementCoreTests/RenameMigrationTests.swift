import Foundation
import Testing
@testable import CasementCore

/// The one-shot move that carries an Islet install's data over to Casement. Every person
/// upgrading runs this exactly once, it is a `moveItem` rather than a copy, and it happens before
/// anything reads the data, so there is no second chance and nothing downstream to notice a
/// mistake. It had no tests at all until these.
@Suite struct RenameMigrationTests {
    private func tempRoot() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("casement-rename-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Writes a file at `path` under `root`, making the folders above it.
    private func seed(_ root: URL, _ path: String, _ contents: String) -> URL {
        let url = root.appendingPathComponent(path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func bothDirectoriesMoveWithTheirContents() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = seed(root, "old-config/config.json", "{\"a\":1}")
        _ = seed(root, "old-support/shelf.json", "[]")
        _ = seed(root, "old-support/nested/lyrics/song.txt", "words")

        let moved = CasementPaths.carryOver([
            (root.appendingPathComponent("old-config"), root.appendingPathComponent("new-config"), "settings"),
            (root.appendingPathComponent("old-support"), root.appendingPathComponent("new-support"), "app data"),
        ])

        #expect(moved == ["settings", "app data"])
        let fm = FileManager.default
        #expect(try String(contentsOf: root.appendingPathComponent("new-config/config.json"), encoding: .utf8) == "{\"a\":1}")
        #expect(try String(contentsOf: root.appendingPathComponent("new-support/shelf.json"), encoding: .utf8) == "[]")
        // Nested content comes too: the shelf, the lyrics cache and the rest live below the top.
        #expect(try String(contentsOf: root.appendingPathComponent("new-support/nested/lyrics/song.txt"), encoding: .utf8) == "words")
        // A move, not a copy, so nothing is left behind to diverge from what was carried over.
        #expect(!fm.fileExists(atPath: root.appendingPathComponent("old-config").path))
        #expect(!fm.fileExists(atPath: root.appendingPathComponent("old-support").path))
    }

    /// The case that would lose data if it went the other way. Newer Casement data must win.
    @Test func anExistingDestinationIsLeftAloneAndSoIsTheOldData() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = seed(root, "old-config/config.json", "old")
        _ = seed(root, "new-config/config.json", "new")

        let moved = CasementPaths.carryOver([
            (root.appendingPathComponent("old-config"), root.appendingPathComponent("new-config"), "settings"),
        ])

        #expect(moved.isEmpty, "nothing should be reported as carried over")
        #expect(try String(contentsOf: root.appendingPathComponent("new-config/config.json"), encoding: .utf8) == "new")
        // The old data stays put rather than being deleted, so it can still be recovered by hand.
        #expect(try String(contentsOf: root.appendingPathComponent("old-config/config.json"), encoding: .utf8) == "old")
    }

    @Test func aMissingSourceIsSkippedAndTheOtherStillMoves() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = seed(root, "old-support/shelf.json", "[]")

        let moved = CasementPaths.carryOver([
            (root.appendingPathComponent("never-existed"), root.appendingPathComponent("new-config"), "settings"),
            (root.appendingPathComponent("old-support"), root.appendingPathComponent("new-support"), "app data"),
        ])

        #expect(moved == ["app data"])
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("new-config").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("new-support/shelf.json").path))
    }

    /// A fresh install has nothing to carry over, which is the common case and must be silent.
    @Test func nothingToDoIsNotAnError() {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(CasementPaths.carryOver([
            (root.appendingPathComponent("a"), root.appendingPathComponent("b"), "settings"),
        ]).isEmpty)
    }

    /// Running twice must not undo the first run: after the move the source is gone, so the second
    /// pass finds nothing. This is what makes the move safe to call on every launch.
    @Test func runningTwiceChangesNothingTheSecondTime() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = seed(root, "old-config/config.json", "once")
        let pairs = [(root.appendingPathComponent("old-config"), root.appendingPathComponent("new-config"), "settings")]

        #expect(CasementPaths.carryOver(pairs) == ["settings"])
        #expect(CasementPaths.carryOver(pairs).isEmpty)
        #expect(try String(contentsOf: root.appendingPathComponent("new-config/config.json"), encoding: .utf8) == "once")
    }

    /// The folders above the destination are made as needed: a first run has no
    /// ~/Library/Application Support/Casement, and on some setups no ~/.config either.
    @Test func foldersAboveTheDestinationAreMade() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = seed(root, "old/config.json", "x")

        let deep = root.appendingPathComponent("a/b/c/casement")
        #expect(CasementPaths.carryOver([(root.appendingPathComponent("old"), deep, "settings")]) == ["settings"])
        #expect(try String(contentsOf: deep.appendingPathComponent("config.json"), encoding: .utf8) == "x")
    }

    /// A move that cannot be made is not worth refusing to launch over. Here the destination's
    /// parent is a file, so `createDirectory` and `moveItem` both fail; the old data stays.
    @Test func aFailedMoveIsReportedAsNotMovedRatherThanThrowing() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = seed(root, "old/config.json", "x")
        _ = seed(root, "blocker", "I am a file, not a folder")

        let moved = CasementPaths.carryOver([
            (root.appendingPathComponent("old"), root.appendingPathComponent("blocker/casement"), "settings"),
        ])

        #expect(moved.isEmpty)
        #expect(try String(contentsOf: root.appendingPathComponent("old/config.json"), encoding: .utf8) == "x")
    }

    /// The real entry point must never reach into the home directory from a sandboxed run. This
    /// asserts the guard exists by reading it, rather than by setting the variable, which would
    /// leak into every other test running beside this one.
    @Test func theRealEntryPointIsGuardedBySupportDirOverride() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()           // CasementCoreTests
            .deletingLastPathComponent()           // Tests
            .deletingLastPathComponent()           // package root
            .appendingPathComponent("Sources/CasementCore/Settings.swift"), encoding: .utf8)
        let fn = try #require(source.range(of: "public static func migrateFromPreviousName()"))
        let body = source[fn.lowerBound...].prefix(400)
        #expect(body.contains("CASEMENT_SUPPORT_DIR"), "the real migration must stay guarded")
    }
}
