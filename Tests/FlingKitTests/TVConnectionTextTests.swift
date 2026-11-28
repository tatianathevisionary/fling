import XCTest
@testable import FlingKit

/// The remote's errors in plain words: no raw network / certificate text, and
/// nothing at all for presses that were dropped or stopped on purpose.
final class TVConnectionTextTests: XCTestCase {

    func test_forgotten_and_unpaired_tv_point_at_pair_with_tv() {
        XCTAssertEqual(TVConnectionText.message(for: ATVError.tlsHandshakeFailed("-9806")),
                       TVConnectionText.forgotten)
        XCTAssertEqual(TVConnectionText.message(for: ATVError.notPaired), TVConnectionText.notPaired)
        XCTAssertTrue(TVConnectionText.forgotten.contains("Pair with TV"))
        XCTAssertTrue(TVConnectionText.notPaired.contains("Pair with TV"))
    }

    func test_raw_details_stay_out_of_the_panel() {
        let unreachable = TVConnectionText.message(
            for: ATVError.connectionFailed("POSIXErrorCode(rawValue: 64): Host is down"))
        XCTAssertEqual(unreachable, TVConnectionText.unreachable)
        XCTAssertEqual(unreachable?.contains("POSIX"), false)
        XCTAssertEqual(TVConnectionText.message(for: ATVError.certificateFailure("openssl exited 1")),
                       TVConnectionText.certificate)
        XCTAssertEqual(TVConnectionText.message(for: ATVError.connectionTimeout), TVConnectionText.timeout)
        XCTAssertEqual(TVConnectionText.message(for: ATVError.unexpectedMessage), TVConnectionText.generic)
    }

    func test_dropped_and_stopped_commands_say_nothing() {
        XCTAssertNil(TVConnectionText.message(for: ATVError.commandDropped))
        XCTAssertNil(TVConnectionText.message(for: ATVError.superseded))
        XCTAssertNil(TVConnectionText.message(for: CancellationError()))
    }

    func test_reconnecting_is_a_grey_progress_note_and_errors_are_not() {
        XCTAssertEqual(TVConnectionText.message(for: ATVError.reconnecting), TVConnectionText.reconnecting)
        XCTAssertTrue(TVConnectionText.isProgressNote(TVConnectionText.reconnecting))
        XCTAssertFalse(TVConnectionText.isProgressNote(TVConnectionText.forgotten))
        XCTAssertFalse(TVConnectionText.isProgressNote(TVConnectionText.unreachable))
    }
}
