import XCTest
import SwiftUI
@testable import Z_island

/// 「减弱动态效果」接入的行为测试。
///
/// 不去改系统设置：`Motion.overrideReduced` 让这里能直接模拟两种状态，
/// 验证 UI 里所有动画点拿到的到底是动画还是 nil。
final class MotionTests: XCTestCase {

    override func tearDown() {
        Motion.overrideReduced = nil
        super.tearDown()
    }

    func testFollowsSystemWhenNotOverridden() {
        Motion.overrideReduced = nil
        XCTAssertEqual(Motion.isReduced,
                       NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func testRespectedReturnsNilWhenReduced() {
        Motion.overrideReduced = true
        XCTAssertTrue(Motion.isReduced)
        XCTAssertNil(Motion.respected(.smooth))
        XCTAssertNil(Motion.respected(.spring(response: 0.36, dampingFraction: 0.86)))
        XCTAssertNil(Motion.respected(.bouncy.speed(1.2)))
    }

    func testRespectedPassesThroughWhenNotReduced() {
        Motion.overrideReduced = false
        XCTAssertFalse(Motion.isReduced)
        XCTAssertNotNil(Motion.respected(.smooth))
        XCTAssertNotNil(Motion.respected(.spring(response: 0.36, dampingFraction: 0.86)))
    }

    func testNilStaysNilInBothStates() {
        for reduced in [true, false] {
            Motion.overrideReduced = reduced
            XCTAssertNil(Motion.respected(nil), "reduced=\(reduced)")
        }
    }
}
