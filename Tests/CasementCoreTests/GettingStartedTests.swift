import Foundation
import Testing
@testable import CasementCore

@Suite struct GettingStartedTests {
    @Test func opensOnlyOnAMacCasementHasNotRunOn() {
        #expect(GettingStarted.opensAtLaunch(hasConfig: false, shown: false))
        // The second launch: config.json is there now, whatever the setting says.
        #expect(!GettingStarted.opensAtLaunch(hasConfig: true, shown: false))
        #expect(!GettingStarted.opensAtLaunch(hasConfig: true, shown: true))
        // Both have to be false. This last pair cannot happen on a Mac, since the setting lives
        // in config.json and goes with it, so it pins the rule rather than standing for a case:
        // what a dotfiles repo that doesn't carry config.json actually gets is the window again.
        #expect(!GettingStarted.opensAtLaunch(hasConfig: false, shown: true))
    }

    /// Marked as shown as it opens, so a second launch is quiet even when the user closed it
    /// without pressing anything, and the setting survives a round trip through config.json.
    @Test func beingShownIsRememberedInConfig() {
        #expect(!CasementSettings().gettingStartedShown)
        #expect(CasementSettings.decodeLenient(Data(#"{"gettingStartedShown": true}"#.utf8)).gettingStartedShown)
        var settings = CasementSettings()
        settings.gettingStartedShown = true
        let encoded = try? JSONEncoder().encode(settings)
        let keys = encoded.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        #expect(keys?["gettingStartedShown"] as? Bool == true)
    }

    @Test func theOpeningLineSaysWhereTheIslandIsAndHowToOpenIt() {
        let hover = GettingStarted.opening(hotkey: "ctrl+option+i", hoverToOpen: true, notched: true)
        #expect(hover == "Casement lives in the notch at the top of the screen. Rest the pointer on it, or press \u{2303}\u{2325}I, to open it.")
        let click = GettingStarted.opening(hotkey: "ctrl+option+i", hoverToOpen: false, notched: true)
        #expect(click.contains("Click it, or press"))
        // No notch: the island is a pill, so nothing points at a notch that isn't there.
        let pill = GettingStarted.opening(hotkey: "", hoverToOpen: true, notched: false)
        #expect(pill == "Casement lives at the top of the screen. Rest the pointer on it to open it.")
        // No shortcut set: the sentence ends after the gesture rather than trailing "or press".
        #expect(!GettingStarted.opening(hotkey: "", hoverToOpen: false, notched: true).contains("press"))
    }

    /// The window offers only the agents that have run on this Mac. An agent with no settings
    /// folder (`notFound`) has nowhere for hooks to go, and three rows offering to connect
    /// agents the user hasn't got is three dead rows.
    @Test func onlyTheAgentsThatHaveRunOnThisMacAreOffered() {
        #expect(GettingStarted.agents([:]).isEmpty)
        #expect(GettingStarted.agents([.claudeCode: .notFound, .codex: .notFound, .cursor: .notFound]).isEmpty)
        #expect(GettingStarted.agents([.claudeCode: .notConnected, .codex: .notFound, .cursor: .connected])
                == [.claudeCode, .cursor])
        // Rows keep the order of the list, not the order the statuses were read in.
        #expect(GettingStarted.agents([.cursor: .notConnected, .claudeCode: .needsUpdate]) == [.claudeCode, .cursor])
        // Its files are there and unreadable, so the row stays: that is where it says so.
        #expect(GettingStarted.agents([.codex: .problem("Codex\u{2019}s settings file couldn\u{2019}t be read.")]) == [.codex])
    }

    /// The Accessibility words say the same thing as SECURITY.md's bullet, shorter. People
    /// worry it reads their typing, so the line denying that is in the window itself.
    @Test func theAccessibilityWordsSayWhatItReadsAndWhatItDoesNot() {
        let reach = GettingStarted.accessibilityReach
        #expect(reach.contains("never reads what you type"))
        #expect(reach.contains("where menu bar items are"))
        #expect(reach.contains("the text of Live Activities and banners"))
        #expect(reach.contains("whether a window is full screen"))
        // The two things behind a setting are named with their settings, not glossed over.
        #expect(reach.contains("only with Replace the system volume and brightness display on"))
        #expect(reach.contains("only with Type emoji where you\u{2019}re typing on"))
        let need = GettingStarted.accessibilityNeed
        #expect(need.contains("beside the notch"))
        // What the permission buys, and no more. An earlier revision ended "Without it the island
        // can do very little", which is not true: the closed island falls back to
        // `MenuBarLayoutEngine.unmeasuredWing` and loses the Live Activity and full screen
        // readings, and everything else, answering a coding agent among it, works without it.
        #expect(!need.contains("very little"))
        #expect(need.contains("Everything else works either way"))
        #expect(need.contains("coding agents"))
    }

    /// The window is given a moment to reach the front, and what it does then.
    ///
    /// Casement is an accessory app, so `NSApp.activate` cannot always take the front from the app
    /// the user is working in, and a window that stays in the background is swept off screen a
    /// second or two later without ever closing. An earlier revision read `makeKeyAndOrderFront`
    /// as the user having seen the window: it wrote `gettingStartedShown` there and owed the
    /// island's peek to `willCloseNotification`, so that first run showed neither the window nor
    /// the peek, and no second chance at either.
    @Test func theWindowCountsAsSeenOnlyWhenItIsInFrontOfTheUser() {
        // Ordered front and the Mac put it there: that is the one case that is remembered.
        #expect(GettingStarted.step(visible: true, key: true, seen: false, closing: false) == .remember)
        // Occlusion has not settled yet, a fraction of a second after being ordered front. Not
        // visible before it has ever been seen is AppKit still placing the window, not a window
        // that has gone, and reading it as gone would fire the peek behind a window about to
        // appear.
        #expect(GettingStarted.step(visible: false, key: true, seen: false, closing: false) == .wait)
        // Occlusion dips again while Stage Manager rearranges the screen around the window it has
        // just put up, a second or so after it was seen. An earlier revision read that as the
        // window having gone and committed the peek behind a window that was still on screen,
        // which is the thing the peek waits for the window to avoid. The window still holds the
        // key, and macOS does not sweep away the key window of the app the user is in.
        #expect(GettingStarted.step(visible: false, key: true, seen: true, closing: false) == .wait)
        // On screen but not key: another app holds the front, so the Mac has not put this window
        // in front of anyone. Nothing is remembered and nothing is given up on yet.
        #expect(GettingStarted.step(visible: true, key: false, seen: false, closing: false) == .wait)
        // Seen, then another app took the front and the window was swept off screen without ever
        // closing: this is what `willCloseNotification` alone missed, and it is the moment the
        // island's peek has been waiting for.
        #expect(GettingStarted.step(visible: false, key: false, seen: true, closing: false) == .peek)
        // Closing, whether it was read or not.
        #expect(GettingStarted.step(visible: true, key: true, seen: true, closing: true) == .peek)
        #expect(GettingStarted.step(visible: false, key: false, seen: false, closing: true) == .peek)
        // Back in front after being swept away: remembered again, which is the same answer.
        #expect(GettingStarted.step(visible: true, key: true, seen: true, closing: false) == .remember)
    }

    /// The window has this long to reach the front before the island says its piece instead. Long
    /// enough that occlusion, which settles within a few hundredths of a second, has answered;
    /// short enough that the peek still looks like part of the launch.
    @Test func theWindowIsGivenAMomentToReachTheFront() {
        #expect(GettingStarted.appears > 0.5)
        #expect(GettingStarted.appears < FirstRunHint.ttl)
    }

    /// House style, which the window's words share with every other user-facing string: no em
    /// dashes anywhere, and typographic apostrophes rather than straight ones.
    @Test func theWordsFollowTheHouseStyle() {
        let words = [GettingStarted.accessibilityNeed, GettingStarted.accessibilityReach, GettingStarted.noAgents,
                     GettingStarted.opening(hotkey: "ctrl+option+i", hoverToOpen: true, notched: true),
                     GettingStarted.opening(hotkey: "", hoverToOpen: false, notched: false)]
        for text in words {
            #expect(!text.contains("\u{2014}"), "\(text)")
            #expect(!text.contains("'"), "\(text)")
        }
    }

    /// A Mac with no agents gets one line, and it says where to go once there is one.
    @Test func aMacWithNoAgentsIsToldWhereToLookLater() {
        #expect(GettingStarted.noAgents.contains("Settings \u{2192} Coding agents"))
        #expect(SettingsIndexTests.pagesNamed(in: GettingStarted.noAgents) == ["Coding agents"])
    }
}
