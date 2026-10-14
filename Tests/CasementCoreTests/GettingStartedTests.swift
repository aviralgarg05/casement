import Foundation
import Testing
@testable import CasementCore

@Suite struct GettingStartedTests {
    @Test func opensOnlyOnAMacCasementHasNotRunOn() {
        #expect(GettingStarted.opensAtLaunch(hasConfig: false, shown: false))
        // The second launch: config.json is there now, whatever the setting says.
        #expect(!GettingStarted.opensAtLaunch(hasConfig: true, shown: false))
        #expect(!GettingStarted.opensAtLaunch(hasConfig: true, shown: true))
        // config.json deleted by hand, or a dotfiles repo that doesn't carry it, after the
        // window was shown: the setting is what remembers, so it stays shut.
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
        #expect(GettingStarted.accessibilityNeed.contains("beside the notch"))
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
