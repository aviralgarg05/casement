import AppKit
import CasementCore
import CasementSystem
import SwiftUI

/// The window Casement opens once, the first time it runs on a Mac, and again whenever it is
/// asked for in Settings → About. What it is for is in `GettingStarted`, in CasementCore.
///
/// A window rather than island cards, for two reasons that are about what the two steps need
/// rather than about taste. Asking for Accessibility opens a macOS dialogue and then sends the
/// user to System Settings, so there has to be somewhere to come back to and read the answer.
/// And choosing which agents to connect needs buttons, a status per agent and a confirmation
/// sheet showing the exact change. A six second peek in the island carries neither.
///
/// Three parts on one window rather than a wizard with steps. There are only two things to ask
/// for, both of them optional, and putting them on separate pages would make each feel like a
/// gate rather than an offer.
@MainActor
enum GettingStartedWindow {
    /// Wide enough for an agent row's mark, name, status and button on one line, and for the
    /// Accessibility paragraph to run three or four lines rather than ten. The height follows
    /// the content: a Mac with no agents gets a shorter window, not three empty rows.
    static let width: CGFloat = 480

    static func make(model: AppModel) -> NSWindow {
        let host = NSHostingController(rootView: GettingStartedView(model: model))
        let w = NSWindow(contentViewController: host)
        w.title = "Getting started"
        // No minimise and no resize: it is read once and closed, and its height is its content's.
        w.styleMask = [.titled, .closable]
        w.tabbingMode = .disallowed
        // Kept after closing, so reopening it from Settings → About shows the same window with
        // the statuses it has already read rather than making a second one.
        w.isReleasedWhenClosed = false
        w.center()
        return w
    }
}

/// What the window shows: where the island is, Accessibility, and the coding agents on this Mac.
///
/// Not modal. Granting Accessibility means a trip to System Settings and back, and a modal
/// window would hold the rest of Casement shut while the user is away. Closing it changes
/// nothing on the Mac and is said so at the foot of the window, with where to find it again.
struct GettingStartedView: View {
    @Bindable var model: AppModel
    /// nil until the agents' files have been read, so an empty window never flashes the line
    /// about having no agents on a Mac that has three.
    @ViewState private var connections: [CodingAgent: AgentConnection]?
    @ViewState private var notes: [CodingAgent: String] = [:]
    @ViewState private var pending: PendingConnection?
    @ViewState private var access: PermissionStatus?
    @ViewState private var host = HostWindow.Box()

    private var wait: Int { Int(model.settings.approvalWait) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            accessibility
            Divider()
            agents
            Divider()
            footer
        }
        .padding(20)
        .frame(width: GettingStartedWindow.width)
        .background(HostWindow(box: host))
        .onAppear(perform: refresh)
        // The answer to Accessibility arrives after a trip to System Settings, and an agent can
        // be connected or disconnected by hand while this window sits open. Closing an NSWindow
        // never calls `onDisappear`, and this window is kept so it can be opened again, so the
        // window's own visibility is what says whether anything still needs reading.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if host.window?.isVisible == true { refresh() }
        }
        .sheet(item: $pending) { p in
            AgentConnectSheet(plan: p.plan) {
                apply(p.plan)
            } onCancel: {
                pending = nil
            }
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            CasementTile(size: 44)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to Casement").font(.title3.bold())
                Text(GettingStarted.opening(hotkey: model.settings.hotkey, hoverToOpen: model.settings.hoverToOpen,
                                            notched: Self.notched))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var accessibility: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Accessibility").font(.headline)
                StatusDot(colour: accessColour)
                Text(PermissionKind.accessibility.statusLabel(access))
                    .font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let access, access != .granted, let title = PermissionKind.accessibility.buttonTitle(access) {
                    Button(title) { ask(access) }
                }
            }
            Text(GettingStarted.accessibilityNeed)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text(GettingStarted.accessibilityReach)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var agents: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Coding agents").font(.headline)
            Text("Casement can show what Claude Code, Codex and Cursor are doing and let you answer their requests from the notch.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let connections {
                let offered = GettingStarted.agents(connections)
                if offered.isEmpty {
                    Text(GettingStarted.noAgents)
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(offered) { agent in
                        GettingStartedAgentRow(agent: agent, connection: connections[agent] ?? .notConnected,
                                               note: notes[agent]) {
                            connect(agent)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Nothing here is required. You can open this again from Settings → About.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Button("Done") { host.window?.performClose(nil) }
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Reading what is there

    /// Whether this Mac has a notch, for the line about where the island lives. Snapshots draw
    /// the notched wording whatever display they render on.
    private static var notched: Bool {
        NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
    }

    private func refresh() {
        PermissionProbe.status(of: .accessibility, readDownloads: false) { update($0) }
        var found: [CodingAgent: AgentConnection] = [:]
        for agent in CodingAgent.allCases {
            found[agent] = AgentHookSetup.connection(agent, home: CasementPaths.home,
                                                     executable: CodingAgentsSettings.executable, wait: wait)
        }
        connections = found
    }

    /// A permission granted while this window was open lets switched-on features start now
    /// rather than at the next launch, as the Permissions page does it.
    private func update(_ status: PermissionStatus) {
        let was = access
        access = status
        model.recheckAccessibility()
        if status == .granted, was != nil, was != .granted {
            NotificationCenter.default.post(name: .casementSettingsChanged, object: nil)
        }
    }

    private var accessColour: Color {
        switch access {
        case .granted: return .green
        case .denied, .restricted: return .orange
        default: return Color.secondary.opacity(0.5)
        }
    }

    /// macOS shows its own Accessibility question once per launch and never again, so after
    /// that the only way through is System Settings. `PermissionStatus.action` already knows
    /// which of the two this is, and `buttonTitle` has already said so on the button.
    private func ask(_ status: PermissionStatus) {
        switch status.action {
        case .request: PermissionProbe.request(.accessibility) { update($0) }
        default: NSWorkspace.shared.open(PermissionKind.accessibility.settingsURL)
        }
    }

    // MARK: Connecting

    private func connect(_ agent: CodingAgent) {
        notes[agent] = nil
        switch AgentConnect.plan(agent, wait: wait) {
        case .confirm(let plan): pending = PendingConnection(plan: plan)
        case .upToDate: refresh()
        case .moving: break
        case .note(let note): notes[agent] = note
        }
    }

    private func apply(_ plan: AgentHookPlan) {
        pending = nil
        do {
            try AgentHookSetup.apply(plan)
            // Connecting is said by the dot turning green. Codex is the one agent with a step
            // left to do, and it has to be said here because it happens in Codex, not here.
            if plan.agent == .codex {
                notes[.codex] = "Connected. In Codex, type /hooks once and trust Casement\u{2019}s."
            }
        } catch {
            notes[plan.agent] = AgentConnection.problemText(for: error, agent: plan.agent)
        }
        refresh()
    }
}

/// One agent in the getting started window: its mark, where it stands, and the one button that
/// connects or updates it. Disconnecting belongs on the Coding agents page, not here: this
/// window is for someone who has connected nothing yet.
private struct GettingStartedAgentRow: View {
    let agent: CodingAgent
    let connection: AgentConnection
    let note: String?
    let connect: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AgentMark(agent: agent)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.title)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if note == nil { StatusDot(colour: colour) }
                    Text(note ?? detail)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let title = buttonTitle { Button(title, action: connect) }
        }
    }

    private var detail: String {
        if case .problem(let why) = connection { return why }
        return connection.label
    }

    private var buttonTitle: String? {
        switch connection {
        case .notConnected: return "Connect\u{2026}"
        case .needsUpdate: return "Update\u{2026}"
        default: return nil
        }
    }

    private var colour: Color {
        switch connection {
        case .connected: return .green
        case .needsUpdate, .problem: return .orange
        default: return Color.secondary.opacity(0.5)
        }
    }
}
