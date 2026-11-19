import XCTest
@testable import HarpyDockCore

final class A825Tests: XCTestCase {
    private func liveBlocks(_ settings: Settings) -> [Int: [UInt8]] {
        var blocks = Dictionary(uniqueKeysWithValues: A825.ownedBlocks.map {
            ($0, [UInt8](repeating: 0, count: 8))
        })
        for (address, data) in A825Protocol.fragments(for: settings) {
            let block = address / 8 * 8
            for (offset, byte) in data.enumerated() {
                blocks[block]![address + offset - block] = byte
            }
        }
        return blocks
    }

    func testMemoryPacketLayout() {
        XCTAssertEqual(
            A825Protocol.memoryPacket(0x03, address: 0x0008, offset: 0, value: 0x21, lastOffset: 5),
            [0x07, 0x18, 0x03, 0x00, 0x08, 0x00, 0x21, 0x05])
        XCTAssertEqual(
            A825Protocol.memoryPacket(0x05, address: 0x0018, offset: 2, lastOffset: 7),
            [0x07, 0x18, 0x05, 0x02, 0x18, 0x00, 0x00, 0x07])
    }

    func testReadTransactionShape() {
        let transaction = A825Protocol.readFrames(address: 0x0008, length: 8)
        XCTAssertEqual(transaction.prepare.count, 9)
        XCTAssertEqual(transaction.requests.count, 8)
        XCTAssertEqual(transaction.finish.count, 2)
        XCTAssertEqual(transaction.requests.first,
                       [0x07, 0x18, 0x05, 0x00, 0x08, 0x00, 0x00, 0x07])
        XCTAssertEqual(transaction.finish.first,
                       [0x07, 0x18, 0x09, 0x00, 0x08, 0x00, 0x00, 0x07])
    }

    func testDPIEncodingMatchesChipTable() {
        XCTAssertEqual(A825.dpiCode(for: 200), 1)
        XCTAssertEqual(A825.dpiCode(for: 1200), 6)
        XCTAssertEqual(A825.dpiCode(for: 1600), 8)
        XCTAssertEqual(A825.dpiCode(for: 3200), 13)
        XCTAssertEqual(A825.dpiCode(for: 4000), 14)
        XCTAssertEqual(A825.dpiCode(for: 5600), 0)
        XCTAssertEqual(A825.dpiCode(for: 8000), 3)
        XCTAssertEqual(A825.dpiCode(for: 12800), 8)
        XCTAssertNil(A825.dpiCode(for: 2200))
    }

    func testDefaultFragments() {
        let fragments = A825Protocol.fragments(for: .defaults)
        XCTAssertEqual(fragments[0x0015], [0x68, 0xDE, 0x03])
        XCTAssertEqual(fragments[0x0008], [0x21, 0x22, 0x23, 0x24, 0x25, 0x06])
        XCTAssertEqual(fragments[0x0018], [0x18])
        XCTAssertEqual(fragments[0x0019], [0x3F])
        XCTAssertEqual(fragments[0x001A], [200])
        XCTAssertEqual(fragments[0x001E], [0])
    }

    func testRoundTripDecode() throws {
        let blocks = liveBlocks(.defaults)
        let live = try A825Protocol.decode(blocks: blocks, defaults: .defaults)
        XCTAssertEqual(live.settings, .defaults)
        XCTAssertEqual(live.settings.stages.map(\.value), [1200, 1600, 3200, 4000, 5600, 8000])
        XCTAssertEqual(live.settings.buttons, [.left, .right, .middle, .back, .forward, .dpiButton])
        XCTAssertEqual(live.settings.pollingHz, 1000)
    }

    func testAmbiguousCodeKeepsPreferredValue() throws {
        var blocks = liveBlocks(.defaults)
        blocks[0x0010]![5] = 0x6E // stage 1 = code 6 (1200 or 10400), stage 2 = code 14
        var preferred = Settings.defaults
        preferred.stages[0].value = 10400 // also code 6
        let live = try A825Protocol.decode(blocks: blocks, defaults: preferred)
        XCTAssertEqual(live.settings.stages[0].value, 10400)
        XCTAssertTrue(live.ambiguousStages.contains(0))
        XCTAssertEqual(live.settings.stages[1].value, 4000)
    }

    func testPlanIsEmptyForIdenticalState() throws {
        let plan = try A825Protocol.plan(.defaults, live: liveBlocks(.defaults))
        XCTAssertTrue(plan.isEmpty)
    }

    func testPlanWritesOnlyChangedBlockAndPreservesUnknownBytes() throws {
        var live = liveBlocks(.defaults)
        live[0x0010]![0] = 0xAA
        live[0x0010]![1] = 0xBB
        live[0x0008]![0] = 0x21

        var wanted = Settings.defaults
        wanted.stages[0].value = 800
        let plan = try A825Protocol.plan(wanted, live: live)

        XCTAssertEqual(plan.writes.count, 1)
        XCTAssertEqual(plan.writes.first?.address, 0x0010)
        XCTAssertEqual(plan.writes.first?.domains, ["DPI values"])
        XCTAssertEqual(plan.writes.first?.data[0], 0xAA)
        XCTAssertEqual(plan.writes.first?.data[1], 0xBB)
        XCTAssertEqual(plan.unchangedBlocks, [0x0008, 0x0018, 0x0020, 0x0028])
    }

    func testColorRoundTrip() throws {
        var wanted = Settings.defaults
        wanted.stages[0].color = RGB16(red8: 255, green8: 0, blue8: 128)
        let live = try A825Protocol.decode(blocks: liveBlocks(wanted), defaults: wanted)
        XCTAssertEqual(live.settings.stages[0].color, wanted.stages[0].color)
    }

    func testLightingFrame() {
        let lighting = LightingSettings(mode: .constant, brightness: 7, speed: 4, direction: 0)
        let frames = A825Protocol.lightingFrames(lighting, stages: Settings.defaults.stages)
        XCTAssertEqual(frames.count, 7)
        XCTAssertEqual(frames.last, [0x07, 0x13, 0xFF, 0xA4, 0x0B, 0x08, 0x00, 0x00])
    }

    func testOffLightingIsDark() {
        let lighting = LightingSettings(mode: .off, brightness: 15, speed: 5, direction: 1)
        let frames = A825Protocol.lightingFrames(lighting, stages: Settings.defaults.stages)
        XCTAssertEqual(Array(frames[0].suffix(4)), [0, 0, 0, 0])
        XCTAssertEqual(frames.last, [0x07, 0x13, 0xFF, 0xA5, 0x1B, 0x0F, 0x00, 0x00])
    }

    func testFireAndFinalizeFrames() {
        XCTAssertEqual(A825Protocol.fireFrame(intervalMs: 50),
                       [0x07, 0x17, 0x00, 0x32, 0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(A825Protocol.finalizeFrames(),
                       [[0x07, 0x18, 0x10, 0, 0, 0, 0, 0],
                        [0x07, 0x18, 0x00, 0, 0, 0, 0, 0],
                        [0x07, 0x20, 0, 0, 0, 0, 0, 0]])
    }

    func testInvalidLiveBlocksAreRejected() {
        var blocks = liveBlocks(.defaults)
        blocks[0x0018]![1] = 0
        XCTAssertThrowsError(try A825Protocol.decode(blocks: blocks, defaults: .defaults))
        XCTAssertThrowsError(try A825Protocol.plan(.defaults, live: [:]))
    }
}
