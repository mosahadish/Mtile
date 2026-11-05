import XCTest
@testable import Mtile

final class AppCatalogTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AppCatalogTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeFile(_ relative: String, executable: Bool) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
    }

    private func makeDir(_ relative: String) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(relative), withIntermediateDirectories: true)
    }

    private func path(_ relative: String) -> String { root.appendingPathComponent(relative).path }

    func testPathExecutables_OnlyExecutableFilesAreListed() throws {
        try makeFile("bin/tool", executable: true)
        try makeFile("bin/readme.txt", executable: false)
        try makeDir("bin/subdir")

        let entries = AppCatalog.build(pathVariable: "\(path("bin")):\(path("missing"))", appRoots: [])
        XCTAssertEqual(entries, [LauncherEntry(displayName: "tool", launchTarget: path("bin/tool"))])
    }

    func testApplications_AreFoundRecursivelyButNotInsideBundles() throws {
        try makeDir("Apps/Safari.app/Contents/Helpers/Inner.app")
        try makeDir("Apps/Utilities/Terminal.app")
        try makeDir("Apps/Edge Apps.localized/Microsoft Teams (PWA).app")

        let names = AppCatalog.build(pathVariable: nil, appRoots: [path("Apps"), path("NoSuchRoot")]).map(\.displayName)
        XCTAssertEqual(names, ["Microsoft Teams (PWA)", "Safari", "Terminal"])
    }

    func testBuild_DeduplicatesCaseInsensitivelyAndSortsByName() throws {
        try makeFile("bin/zsh", executable: true)
        try makeDir("Apps/alpha.app")
        try makeDir("Apps/Beta.app")

        let entries = AppCatalog.build(pathVariable: "\(path("bin")):\(path("bin"))", appRoots: [path("Apps")])
        XCTAssertEqual(entries.map(\.displayName), ["alpha", "Beta", "zsh"])
        XCTAssertEqual(entries.last?.launchTarget, path("bin/zsh"))
    }

    func testFilter_RanksByScoreThenName() {
        let entries = ["Firefox", "Finder", "Safari", "FaceTime"].map { LauncherEntry(displayName: $0, launchTarget: "/x/\($0)") }

        XCTAssertEqual(AppCatalog.filter(entries, query: "").map(\.displayName), ["FaceTime", "Finder", "Firefox", "Safari"])
        XCTAssertEqual(AppCatalog.filter(entries, query: "fi").map(\.displayName), ["Finder", "Firefox", "FaceTime", "Safari"])
        XCTAssertEqual(AppCatalog.filter(entries, query: "zz"), [])
    }
}
