import XCTest
@testable import ClaudeGateLib

final class DangerDetectorTests: XCTestCase {
    private func signal(for command: String) -> DangerSignal? {
        DangerDetector.check(toolName: "Bash", inputPreview: command, filePath: nil, cwd: nil)
    }

    func testFlagsPkillDashF() {
        XCTAssertNotNil(signal(for: "pkill -f node"))
    }

    func testFlagsPkillDashFBeforeSignal() {
        XCTAssertNotNil(signal(for: "pkill -f -9 node"))
    }

    func testFlagsPkillSignalBeforeDashF() {
        XCTAssertNotNil(signal(for: "pkill -9 -f node"))
    }

    func testFlagsPkillLongFormFull() {
        XCTAssertNotNil(signal(for: "pkill -9 --full node"))
    }

    func testDoesNotFlagBarePkillByName() {
        XCTAssertNil(signal(for: "pkill node"))
    }

    func testDoesNotFlagPkillWithUnrelatedFlag() {
        XCTAssertNil(signal(for: "pkill -x node"))
    }

    func testDoesNotFlagKillall() {
        XCTAssertNil(signal(for: "killall node"))
    }
}
