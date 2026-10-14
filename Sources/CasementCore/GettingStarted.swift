import Foundation

/// The window Casement opens once, the first time it runs on a Mac: a line on where the island
/// is, the one macOS permission it asks for, and the coding agents it can connect to. This is
/// the part with no AppKit in it; the window is `GettingStartedWindow` in the app.
///
/// Before it, the whole first run was `FirstRunHint`, a six second peek in the island. Nothing
/// ever asked for Accessibility, which is only requested from two Settings pages, so a user who
/// never opened Settings had an island that could not measure the space beside the notch, mirror
/// an iPhone Live Activity or tell when a window was full screen, and was never told why. And
/// nothing ever offered to connect Claude Code, Codex or Cursor: `AppModel.checkAgentHooks` only
/// re-checks hooks that are already there, so the feature Casement leads with had to be found on
/// the Coding agents page by someone who did not yet know it existed.
public enum GettingStarted {
    /// Whether the window opens at launch.
    /// - Parameters:
    ///   - hasConfig: `config.json` is there, so Casement has run on this Mac before. Someone
    ///     upgrading has one and is not new, so the window stays shut for them.
    ///   - shown: `CasementSettings.gettingStartedShown`, written as the window opens rather than
    ///     as it closes. Closing it with nothing pressed still counts as having seen it: a window
    ///     that came back every launch until it was obeyed would be worse than one that can be
    ///     opened again from Settings → About.
    public static func opensAtLaunch(hasConfig: Bool, shown: Bool) -> Bool { !hasConfig && !shown }

    /// Where the island is and how to open it, in two sentences. The same facts as
    /// `FirstRunHint`'s subtitle, which follows this window rather than playing behind it.
    /// - Parameters:
    ///   - hotkey: the open shortcut as config.json writes it; left out when there is none.
    ///   - hoverToOpen: resting the pointer opens the island; otherwise a click does.
    ///   - notched: this Mac has a notch; otherwise the island is a pill at the top of the screen.
    public static func opening(hotkey: String, hoverToOpen: Bool, notched: Bool) -> String {
        let place = notched ? "in the notch at the top of the screen" : "at the top of the screen"
        let gesture = hoverToOpen ? "Rest the pointer on it" : "Click it"
        guard let key = Hotkey.parse(hotkey) else { return "Casement lives \(place). \(gesture) to open it." }
        return "Casement lives \(place). \(gesture), or press \(key.label), to open it."
    }

    /// The agents that get a row: the ones that have run on this Mac, so there is a settings
    /// folder for Casement's hooks to go in. `.notFound` is the agent with no folder, and three
    /// rows offering to connect agents the user has not got would be three dead rows where one
    /// honest line belongs. A `.problem` agent keeps its row: its files are there, Casement just
    /// cannot read them, and the row is where it says so.
    public static func agents(_ connections: [CodingAgent: AgentConnection]) -> [CodingAgent] {
        CodingAgent.allCases.filter { agent in
            switch connections[agent] {
            case nil, .notFound?: return false
            default: return true
            }
        }
    }

    /// What the island cannot do without Accessibility. The window asks for no other permission:
    /// everything else Casement can use belongs to a feature that starts off, and macOS asks for
    /// those as they are switched on.
    ///
    /// An earlier revision ended this "Without it the island can do very little", which is not
    /// true, and overstating what a permission buys is the wrong thing to do in the one window
    /// whose job is to ask for it honestly. Without the permission the closed island keeps to
    /// `MenuBarLayoutEngine.unmeasuredWing` and loses the last two of the three readings. Media
    /// and its controls, timers, the stopwatch, notes, the shelf, the calendar, meetings, the Ask
    /// box, the iPhone bridge and answering a coding agent's requests all work without it, and the
    /// last of those is the feature Casement leads with.
    public static let accessibilityNeed =
        "Casement uses Accessibility to work out how much room it has beside the notch, to mirror a Live Activity from your iPhone, and to tell when a window is full screen. Without it the closed island keeps to a fixed width rather than the room that is free, and those last two go. Everything else works either way, answering your coding agents\u{2019} requests among it."

    /// What the grant covers, shortened from SECURITY.md and saying the same thing. People worry
    /// that Accessibility reads their typing, so the sentence that says it does not is here
    /// rather than behind a link.
    public static let accessibilityReach =
        "It reads where menu bar items are, the text of Live Activities and banners, whether a window is full screen and, only with Replace the system volume and brightness display on, the volume and brightness keys. It never reads what you type. The one thing it writes is the emoji you click, and only with Type emoji where you\u{2019}re typing on."

    /// One line for a Mac with none of the three agents on it.
    public static let noAgents =
        "None of them has run on this Mac yet. Once one has, connect it in Settings → Coding agents."

    /// What the first run does next, each time the getting started window says where it is.
    public enum Step: Equatable, Sendable {
        /// The window is in front of the user, so it is remembered as shown and does not open
        /// itself at the next launch.
        case remember
        /// The window has gone, or never arrived: the island says its piece instead.
        case peek
        /// Neither yet.
        case wait
    }

    /// Whether ordering the window front has put it in front of the user, and what follows.
    ///
    /// An earlier revision asked neither question: it took `makeKeyAndOrderFront` for an answer,
    /// wrote `gettingStartedShown` there and then, and owed the island's peek to the window's
    /// `willCloseNotification`. Casement is an accessory app, so `NSApp.activate` cannot always
    /// take the front from the app the user is working in. The window then stays a background
    /// window, macOS sweeps it off screen within a second or two without closing it, and the
    /// first run was spent on a window nobody read while the peek waited for a close that could
    /// not come. The first run showed nothing at all, where before the window existed it showed
    /// the peek every time.
    ///
    /// - Parameters:
    ///   - visible: `NSWindow.occlusionState` says some of the window can be seen. It is also
    ///     false for a fraction of a second after the window is ordered front, before AppKit has
    ///     settled where the window went, and it dips again while Stage Manager rearranges the
    ///     screen around a window that has just appeared, which is why it alone cannot say the
    ///     window has gone. `NSWindow.isVisible` is no use at all here: it stays true for a
    ///     window that has been swept off screen.
    ///   - key: the window is the key window, which is the Mac's own answer to whether it put the
    ///     window in front of the user. It is also what tells a window that has gone from a
    ///     window that is merely between placements: macOS does not sweep away the key window of
    ///     the app the user is in, so occlusion dipping while the window still holds the key is
    ///     the screen settling and not the user losing the window.
    ///   - seen: the window has already been in front of the user on this launch.
    ///   - closing: the window is closing.
    public static func step(visible: Bool, key: Bool, seen: Bool, closing: Bool) -> Step {
        if closing { return .peek }
        if visible, key { return .remember }
        return seen && !visible && !key ? .peek : .wait
    }

    /// How long the window is given to reach the front before the island says its piece instead
    /// and the window is left to open itself again at the next launch. Occlusion settles a few
    /// hundredths of a second after the window is ordered front, so this is generous.
    public static let appears: TimeInterval = 1.5
}
