import Foundation
import Testing
@testable import CasementCore
@testable import CasementSystem

/// What the getting started window offers, over real settings folders rather than hand-written
/// statuses: the window reads each agent with `AgentHookSetup.connection` and hands the lot to
/// `GettingStarted.agents`, which is the pair tested here. `home` is a temporary folder, so none
/// of this looks at the real `~/.claude`, `~/.codex` or `~/.cursor`.
@Suite struct GettingStartedAgentsTests {
    func tempHome() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("casement-getting-started-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func offered(_ home: URL, wait: Int = 300) -> [CodingAgent] {
        var connections: [CodingAgent: AgentConnection] = [:]
        for agent in CodingAgent.allCases {
            connections[agent] = AgentHookSetup.connection(agent, home: home, executable: "casementctl", wait: wait)
        }
        return GettingStarted.agents(connections)
    }

    @Test func aMacWithNoAgentsGetsNoRows() throws {
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(offered(home).isEmpty)
    }

    @Test func onlyTheAgentsWithASettingsFolderAreOffered() throws {
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        for agent in [CodingAgent.claudeCode, .cursor] {
            try FileManager.default.createDirectory(at: agent.configDirectory(home: home), withIntermediateDirectories: true)
        }
        #expect(offered(home) == [.claudeCode, .cursor])
    }

    /// Connecting from the window is the same plan and the same write as the Coding agents page
    /// makes, so the row that offered it reads as connected straight afterwards and the window
    /// has nothing left to offer for it.
    @Test func connectingFromTheWindowLeavesTheAgentConnected() throws {
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: CodingAgent.codex.configDirectory(home: home), withIntermediateDirectories: true)
        #expect(AgentHookSetup.connection(.codex, home: home, executable: "casementctl", wait: 300) == .notConnected)

        try AgentHookSetup.apply(AgentHookSetup.plan(.codex, home: home, executable: "casementctl", wait: 300))

        #expect(offered(home) == [.codex])
        #expect(AgentHookSetup.connection(.codex, home: home, executable: "casementctl", wait: 300) == .connected)
    }

    /// An agent whose files can't be read keeps its row: that row is where the reason is said.
    @Test func anAgentWithUnreadableSettingsKeepsItsRow() throws {
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let cursor = CodingAgent.cursor.configDirectory(home: home)
        try FileManager.default.createDirectory(at: cursor, withIntermediateDirectories: true)
        try Data("{ \"hooks\": ".utf8).write(to: cursor.appendingPathComponent("hooks.json"))

        #expect(offered(home) == [.cursor])
        guard case .problem(let why) = AgentHookSetup.connection(.cursor, home: home, executable: "casementctl", wait: 300) else {
            Issue.record("an unreadable hooks.json should read as a problem")
            return
        }
        #expect(why.contains("Cursor"))
    }
}
