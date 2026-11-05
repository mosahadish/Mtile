// Port of tests/Wtile.Tests/Layouts/LayoutRegistryTests.cs
import XCTest
@testable import Mtile

final class LayoutRegistryTests: XCTestCase {
    func testCreateDefault_RegistersBuiltinLayouts() {
        let cases: [(name: String, symbol: String)] = [
            ("master-stack", "[]="),
            ("master-stack-right", "=[]"),
            ("monocle", "[M]"),
            ("centered-master", "|M|"),
            ("vertical", "="),
            ("deck", "[D]"),
            ("dwindle", "[\\]"),
        ]
        let registry = LayoutRegistry.createDefault()
        for c in cases {
            guard let layout = registry.get(c.name) else {
                XCTFail("layout \(c.name) not registered")
                continue
            }
            XCTAssertEqual(layout.symbol, c.symbol, c.name)
            XCTAssertEqual(layout.name, c.name)
        }
        XCTAssertEqual(registry.names, cases.map { $0.name }.sorted())
    }

    func testGet_UnknownName_ReturnsNil() {
        let registry = LayoutRegistry.createDefault()
        XCTAssertNil(registry.get("does-not-exist"))
    }

    func testGet_IsCaseInsensitive() {
        let registry = LayoutRegistry.createDefault()
        XCTAssertNotNil(registry.get("MASTER-STACK"))
    }
}