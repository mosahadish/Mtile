import XCTest
@testable import Mtile

final class LaunchAgentTests: XCTestCase {
    func testPlist_StartsExecutableAtLoginWithoutKeepAlive() {
        let p = LaunchAgent.plist(executable: "/opt/Mtile", logPath: "/tmp/m.log")
        XCTAssertEqual(p["Label"] as? String, "com.hollowthorn.mtile")
        XCTAssertEqual(p["ProgramArguments"] as? [String], ["/opt/Mtile"])
        XCTAssertEqual(p["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(p["KeepAlive"] as? Bool, false)
        XCTAssertEqual(p["StandardOutPath"] as? String, "/tmp/m.log")
        XCTAssertEqual(p["StandardErrorPath"] as? String, "/tmp/m.log")
    }

    func testPlist_SerializesAsPropertyList() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: LaunchAgent.plist(executable: "/opt/Mtile", logPath: "/tmp/m.log"),
            format: .xml, options: 0)
        XCTAssertFalse(data.isEmpty)
    }

    func testMode_UserAndAdminMeanAtLogin() {
        XCTAssertEqual(LaunchOnBootMode.from("user"), .atLogin)
        XCTAssertEqual(LaunchOnBootMode.from("Admin"), .atLogin)
        XCTAssertEqual(LaunchOnBootMode.from("off"), .off)
    }
}
