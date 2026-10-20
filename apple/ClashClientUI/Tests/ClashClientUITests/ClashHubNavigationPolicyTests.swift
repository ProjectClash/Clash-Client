import XCTest
@testable import ClashClientUI

final class ClashHubNavigationPolicyTests: XCTestCase {
    func testLegacyRegularTouchUsesNativeLinks() {
        // iPadOS 15's regular shell cannot display selection-based destinations.
        XCTAssertFalse(ClashHubNavigationPolicy.usesSelection(
            presentationClass: .regularTouch,
            supportsNavigationStack: false
        ))
    }

    func testModernRegularTouchAndDesktopKeepSelectionRouting() {
        for presentationClass in [ClashPresentationClass.regularTouch, .desktop] {
            XCTAssertTrue(ClashHubNavigationPolicy.usesSelection(
                presentationClass: presentationClass,
                supportsNavigationStack: true
            ))
        }
    }

    func testCompactTouchAndTelevisionKeepNativeLinks() {
        for presentationClass in [ClashPresentationClass.compactTouch, .television] {
            for supportsNavigationStack in [false, true] {
                XCTAssertFalse(ClashHubNavigationPolicy.usesSelection(
                    presentationClass: presentationClass,
                    supportsNavigationStack: supportsNavigationStack
                ))
            }
        }
    }

    func testRuntimePolicyMatchesNavigationStackAvailability() {
        let supportsNavigationStack: Bool
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
            supportsNavigationStack = true
        } else {
            supportsNavigationStack = false
        }

        for presentationClass in ClashPresentationClass.allCases {
            XCTAssertEqual(
                ClashHubNavigationPolicy.usesSelection(for: presentationClass),
                ClashHubNavigationPolicy.usesSelection(
                    presentationClass: presentationClass,
                    supportsNavigationStack: supportsNavigationStack
                )
            )
        }
    }
}
