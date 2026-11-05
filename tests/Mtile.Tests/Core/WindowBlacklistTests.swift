// Port of tests/Wtile.Tests/Core/WindowBlacklistTests.cs
import Foundation
import XCTest
@testable import Mtile

final class WindowBlacklistTests: XCTestCase {
    private static func regex(_ pattern: String?) -> NSRegularExpression? {
        guard let pattern else { return nil }
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func rule(processName: String? = nil, className: String? = nil, title: String? = nil) -> CompiledWindowRule {
        CompiledWindowRule(processName: regex(processName), className: regex(className), title: regex(title))
    }

    func testNoRules_NothingIsBlacklisted() {
        XCTAssertFalse(WindowBlacklist.isBlacklisted([], processNames: ["chrome.exe"], className: "Chrome_WidgetWin_1", title: "My Tab"))
    }

    func testSingleFieldMatch_IsBlacklisted() {
        let rules = [Self.rule(className: "NativeHWNDHost")]
        XCTAssertTrue(WindowBlacklist.isBlacklisted(rules, processNames: ["sihost.exe"], className: "NativeHWNDHost", title: ""))
    }

    func testSingleFieldNonMatch_IsNotBlacklisted() {
        let rules = [Self.rule(className: "NativeHWNDHost")]
        XCTAssertFalse(WindowBlacklist.isBlacklisted(rules, processNames: ["chrome.exe"], className: "Chrome_WidgetWin_1", title: "My Tab"))
    }

    func testMultiFieldRule_RequiresAllSetFieldsToMatch() {
        let rules = [Self.rule(processName: "chrome", title: "Netflix")]

        XCTAssertFalse(WindowBlacklist.isBlacklisted(rules, processNames: ["chrome.exe"], className: "Chrome_WidgetWin_1", title: "Gmail"))
        XCTAssertTrue(WindowBlacklist.isBlacklisted(rules, processNames: ["chrome.exe"], className: "Chrome_WidgetWin_1", title: "Netflix - Chrome"))
    }

    func testMultipleRules_MatchesIfAnyRuleMatches() {
        let rules = [Self.rule(className: "Foo"), Self.rule(className: "Bar")]
        XCTAssertTrue(WindowBlacklist.isBlacklisted(rules, processNames: [""], className: "Bar", title: ""))
    }

    func testBlankRuleField_ActsAsWildcard() {
        let rules = [Self.rule(className: "AnyClass")]
        XCTAssertTrue(WindowBlacklist.isBlacklisted(rules, processNames: ["whatever.exe"], className: "AnyClass", title: "any title at all"))
    }

    func testMatching_IsCaseInsensitive() {
        let rules = [Self.rule(className: "nativehwndhost")]
        XCTAssertTrue(WindowBlacklist.isBlacklisted(rules, processNames: ["sihost.exe"], className: "NativeHWNDHost", title: ""))
    }

    func testProcessName_MatchesIfAnyAliasMatches() {
        let rules = [Self.rule(processName: "^chrome$")]
        XCTAssertTrue(WindowBlacklist.isBlacklisted(rules, processNames: ["Google Chrome", "chrome", "chrome.exe"], className: "", title: ""))
        XCTAssertFalse(WindowBlacklist.isBlacklisted(rules, processNames: ["Google Chrome", "Google Chrome.exe"], className: "", title: ""))
    }

    func testCompiledFromConfig_WindowsStyleProcessName_MatchesMacAliases() {
        let rules = WindowRuleCompiler.compileBlacklist([BlacklistRule(processName: "^firefox\\.exe$")])
        let aliases = WindowSnapshot.aliases(appName: "Firefox", bundleID: "org.mozilla.firefox", executableName: "firefox")

        XCTAssertTrue(WindowBlacklist.isBlacklisted(rules, processNames: aliases, className: "AXStandardWindow", title: "Mozilla Firefox"))
        XCTAssertFalse(WindowBlacklist.isBlacklisted(
            rules,
            processNames: WindowSnapshot.aliases(appName: "Safari", bundleID: "com.apple.Safari", executableName: "Safari"),
            className: "AXStandardWindow",
            title: "Firefox download page"))
    }

    func testCompiledFromConfig_BlankFieldsAreUnconstrained() {
        let rules = WindowRuleCompiler.compileBlacklist([BlacklistRule(processName: "", className: "AXDialog", title: "   ")])

        XCTAssertEqual(rules.count, 1)
        XCTAssertNil(rules[0].processName)
        XCTAssertNotNil(rules[0].className)
        XCTAssertNil(rules[0].title)
        XCTAssertTrue(WindowBlacklist.isBlacklisted(rules, processNames: ["anything"], className: "AXDialog", title: "whatever"))
    }
}