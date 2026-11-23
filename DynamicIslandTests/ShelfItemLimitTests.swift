import XCTest
@testable import Z_island

/// 暂存架容量上限的行为测试。
///
/// 只测 `trimmingToLimit` 这个纯函数：`add` 依赖单例和磁盘上的 items.json，
/// 在单元测试里拉起来会把真实暂存架写乱。
@MainActor
final class ShelfItemLimitTests: XCTestCase {

    private func makeItems(_ count: Int) -> [ShelfItem] {
        (0..<count).map { index in
            ShelfItem(kind: .text(string: "item-\(index)"), isTemporary: false)
        }
    }

    func testUnderLimitKeepsEverything() {
        let items = makeItems(5)
        let result = ShelfStateViewModel.trimmingToLimit(items, limit: 20)

        XCTAssertEqual(result.kept.count, 5)
        XCTAssertTrue(result.evicted.isEmpty)
        XCTAssertEqual(result.kept.map(\.displayName), items.map(\.displayName))
    }

    func testExactlyAtLimitIsUntouched() {
        let items = makeItems(20)
        let result = ShelfStateViewModel.trimmingToLimit(items, limit: 20)

        XCTAssertEqual(result.kept.count, 20)
        XCTAssertTrue(result.evicted.isEmpty)
    }

    func testOverLimitDropsOldestFirst() {
        let items = makeItems(23)
        let result = ShelfStateViewModel.trimmingToLimit(items, limit: 20)

        XCTAssertEqual(result.kept.count, 20)
        XCTAssertEqual(result.evicted.count, 3)

        // 最旧的三条（索引 0...2）被抬走，留下的从 item-3 开始
        XCTAssertEqual(result.evicted.map(\.displayName), ["item-0", "item-1", "item-2"])
        XCTAssertEqual(result.kept.first?.displayName, "item-3")
        XCTAssertEqual(result.kept.last?.displayName, "item-22")
    }

    func testOrderIsPreserved() {
        let items = makeItems(30)
        let result = ShelfStateViewModel.trimmingToLimit(items, limit: 4)

        XCTAssertEqual(result.kept.map(\.displayName),
                       ["item-26", "item-27", "item-28", "item-29"])
    }

    func testDefaultLimitMatchesDeclaredConstant() {
        let items = makeItems(ShelfStateViewModel.maxItemCount + 2)
        let result = ShelfStateViewModel.trimmingToLimit(items)

        XCTAssertEqual(result.kept.count, ShelfStateViewModel.maxItemCount)
        XCTAssertEqual(result.evicted.count, 2)
    }
}
