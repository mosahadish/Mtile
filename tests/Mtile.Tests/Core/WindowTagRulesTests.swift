// Port of tests/Wtile.Tests/Core/WindowTagRulesTests.cs
import Foundation
import XCTest
@testable import Mtile

final class WindowTagRulesTests: XCTestCase {
    private static func regex(_ pattern: String?) -> NSRegularExpression? {
        guard let pattern else { return nil }
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func rule(_ tagIndex: Int, processName: String? = nil, className: String? = nil, title: String? = nil, follow: Bool = false) -> CompiledTagRule {
        CompiledTagRule(
            match: CompiledWindowRule(processName: regex(processName), className: regex(className), title: regex(title)),
            tagIndex: tagIndex,
            follow: follow)
    }

    func testNoRules_ResolvesNothing() {
        XCTAssertNil(WindowTagRules.resolve([], processNames: ["firefox.exe"], className: "MozillaWindowClass", title: "Mozilla Firefox"))
    }

    func testSingleFieldMatch_ResolvesToThatRule() {
        let rules = [Self.rule(1, processName: "^firefox\\.exe$", follow: true)]

        guard let matched = WindowTagRules.resolve(rules, processNames: ["firefox.exe"], className: "MozillaWindowClass", title: "Mozilla Firefox") else {
            return XCTFail("expected a match")
        }
        XCTAssertEqual(matched.tagIndex, 1)
        XCTAssertTrue(matched.follow)
    }

    func testSingleFieldNonMatch_ResolvesNothing() {
        let rules = [Self.rule(1, processName: "^firefox\\.exe$")]
        XCTAssertNil(WindowTagRules.resolve(rules, processNames: ["chrome.exe"], className: "Chrome_WidgetWin_1", title: "My Tab"))
    }

    func testMultiFieldRule_RequiresAllSetFieldsToMatch() {
        let rules = [Self.rule(4, processName: "chrome", title: "Netflix")]

        XCTAssertNil(WindowTagRules.resolve(rules, processNames: ["chrome.exe"], className: "Chrome_WidgetWin_1", title: "Gmail"))
        let matched = WindowTagRules.resolve(rules, processNames: ["chrome.exe"], className: "Chrome_WidgetWin_1", title: "Netflix - Chrome")
        XCTAssertEqual(matched?.tagIndex, 4)
    }

    func testMultipleMatchingRules_FirstWins() {
        let rules = [Self.rule(2, className: "Foo"), Self.rule(5, processName: "any")]

        let matched = WindowTagRules.resolve(rules, processNames: ["any.exe"], className: "Foo", title: "")
        XCTAssertEqual(matched?.tagIndex, 2)
    }

    func testBlankRuleField_ActsAsWildcard() {
        let rules = [Self.rule(0, className: "AnyClass")]
        XCTAssertNotNil(WindowTagRules.resolve(rules, processNames: ["whatever.exe"], className: "AnyClass", title: "any title at all"))
    }

    func testCompiledFromConfig_WindowsStyleProcessName_MatchesMacAliases() {
        let rules = WindowRuleCompiler.compileTagRules([TagRule(processName: "^firefox\\.exe$", tag: 3)])
        let aliases = WindowSnapshot.aliases(appName: "Firefox", bundleID: "org.mozilla.firefox", executableName: "firefox")

        let matched = WindowTagRules.resolve(rules, processNames: aliases, className: "AXStandardWindow", title: "Mozilla Firefox")
        XCTAssertEqual(matched?.tagIndex, 2)
    }

    func testCompiledFromConfig_ConvertsOneBasedTagAndMonitor() {
        let rules = WindowRuleCompiler.compileTagRules([
            TagRule(className: "A", tag: 1, monitor: 0, follow: false),
            TagRule(className: "B", tag: 9, monitor: 2, follow: true),
        ])

        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(rules[0].tagIndex, 0)
        XCTAssertNil(rules[0].monitorIndex) // 0 = the monitor the window opened on
        XCTAssertFalse(rules[0].follow)
        XCTAssertEqual(rules[1].tagIndex, 8)
        XCTAssertEqual(rules[1].monitorIndex, 1)
        XCTAssertTrue(rules[1].follow)
    }
}