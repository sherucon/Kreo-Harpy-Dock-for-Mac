import Foundation

// MARK: - Chip constants

public enum A825 {
    public static let vendorID = 0x30FA
    public static let productIDs: Set<Int> = [0x1440, 0x1E01, 0x1340]
    public static let featureReportID: UInt8 = 0x07
    public static let reportLength = 8

    public static let supportedDPI = [
        200, 400, 600, 800, 1000, 1200, 1400, 1600, 1800, 2000,
        2400, 3200, 4000, 4800, 5600, 6400, 7200, 8000, 8800,
        9600, 10400, 11200, 12800,
    ]

    public static let pollingRates = [125, 250, 500, 1000]

    /// The six persistent blocks this app is allowed to touch.
    public static let ownedBlocks = [0x0008, 0x0010, 0x0018, 0x0020, 0x0028]

    /// Sensor scale code: 1..8, A..F, 0..8 (code 9 is skipped).
    public static func dpiCode(for value: Int) -> UInt8? {
        guard let index = supportedDPI.firstIndex(of: value) else { return nil }
        return UInt8((index + 1 + (index >= 8 ? 1 : 0)) & 0x0F)
    }

    public static let codeToDPI: [UInt8: Int] = {
        var map: [UInt8: Int] = [:]
        for (index, value) in supportedDPI.enumerated() {
            let code = UInt8((index + 1 + (index >= 8 ? 1 : 0)) & 0x0F)
            if map[code] == nil { map[code] = value }
        }
        return map
    }()

    /// Sensor scale codes wrap every 16, so codes 1...8 can each mean two DPI values.
    public static let ambiguousCodes: Set<UInt8> = {
        var seen: [UInt8: Int] = [:]
        var ambiguous = Set<UInt8>()
        for (index, _) in supportedDPI.enumerated() {
            let code = UInt8((index + 1 + (index >= 8 ? 1 : 0)) & 0x0F)
            if seen[code] != nil { ambiguous.insert(code) } else { seen[code] = index }
        }
        return ambiguous
    }()

    public static func dpiValue(forCode code: UInt8, preferred: Int? = nil) -> Int? {
        if ambiguousCodes.contains(code), let preferred, dpiCode(for: preferred) == code {
            return preferred
        }
        return codeToDPI[code]
    }

    public static func pollingDivisor(for hz: Int) -> UInt8? {
        switch hz {
        case 125: return 7
        case 250: return 3
        case 500: return 1
        case 1000: return 0
        default: return nil
        }
    }

    public static func pollingRate(forDivisor divisor: UInt8) -> Int? {
        switch divisor {
        case 7: return 125
        case 3: return 250
        case 1: return 500
        case 0: return 1000
        default: return nil
        }
    }
}

// MARK: - Colors (4-bit per channel)

public struct RGB16: Codable, Equatable, Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = min(15, r)
        self.g = min(15, g)
        self.b = min(15, b)
    }

    public init(red8: UInt8, green8: UInt8, blue8: UInt8) {
        self.init(r: 15 - red8 / 16, g: 15 - green8 / 16, b: 15 - blue8 / 16)
    }

    public static let black = RGB16(r: 0, g: 0, b: 0)

    /// Quantized midpoint, 0...255, matching the chip's 4-bit channels.
    public var red8: UInt8 { r * 16 + 8 }
    public var green8: UInt8 { g * 16 + 8 }
    public var blue8: UInt8 { b * 16 + 8 }

    public var hex: String {
        String(format: "#%02X%02X%02X", red8, green8, blue8)
    }
}

// MARK: - Buttons

public enum ButtonAction: UInt8, CaseIterable, Codable, Identifiable, Sendable {
    case left = 0x21
    case right = 0x23
    case middle = 0x22
    case back = 0x24
    case forward = 0x25
    case dpiButton = 0x06
    case dpiUp = 0x26
    case dpiDown = 0x2C
    case doubleClick = 0x28
    case rapidFire = 0x29
    case profileNext = 0x2D
    case lightingNext = 0x35
    case disabled = 0x3F

    public var id: UInt8 { rawValue }

    public var label: String {
        switch self {
        case .dpiButton: return "DPI button (native)"
        case .left: return "Left click"
        case .right: return "Right click"
        case .middle: return "Middle click"
        case .back: return "Back"
        case .forward: return "Forward"
        case .dpiUp: return "DPI up"
        case .dpiDown: return "DPI down"
        case .doubleClick: return "Double click"
        case .rapidFire: return "Rapid fire"
        case .profileNext: return "Next profile"
        case .lightingNext: return "Next lighting mode"
        case .disabled: return "Disabled"
        }
    }

    public static let buttonNames = ["Left", "Right", "Wheel", "Back", "Forward", "DPI button"]
}

// MARK: - Lighting

public enum LightingMode: UInt8, CaseIterable, Codable, Identifiable, Sendable {
    case dpiBreathing = 0x08
    case cycleBreathing = 0x01
    case constant = 0x0A
    case flowingWater = 0x03
    case monoWater = 0x13 // 0x03 with a single color
    case cometTail = 0x04
    case neon = 0x06
    case ambilight = 0x07
    case flashing = 0xB8
    case starTrek = 0xB9
    case ripple = 0xBA
    case enraptured = 0xBB
    case response = 0x9A // 0xBA, reactive variant
    case off = 0x0B

    public var id: UInt8 { rawValue }

    /// Code sent in the animation frame.
    public var code: UInt8 {
        switch self {
        case .dpiBreathing: return 0x08
        case .cycleBreathing: return 0x01
        case .constant: return 0x0A
        case .flowingWater: return 0x03
        case .monoWater: return 0x03
        case .cometTail: return 0x04
        case .neon: return 0x06
        case .ambilight: return 0x07
        case .flashing: return 0xB8
        case .starTrek: return 0xB9
        case .ripple: return 0xBA
        case .enraptured: return 0xBB
        case .response: return 0xBA
        case .off: return 0x0A
        }
    }

    public var supportsColor: Bool {
        switch self {
        case .monoWater, .cometTail, .flashing, .starTrek, .ripple, .enraptured, .response:
            return true
        default:
            return false
        }
    }

    public var usesStageColors: Bool {
        !supportsColor && self != .off
    }

    public var label: String {
        switch self {
        case .dpiBreathing: return "DPI Breathing"
        case .cycleBreathing: return "Cycle Breathing"
        case .constant: return "Constant"
        case .flowingWater: return "Flowing Water"
        case .monoWater: return "Mono Water"
        case .cometTail: return "Comet Tail"
        case .neon: return "Neon"
        case .ambilight: return "Ambilight"
        case .flashing: return "Flashing"
        case .starTrek: return "Star Trek"
        case .ripple: return "Ripple"
        case .enraptured: return "Enraptured"
        case .response: return "Response"
        case .off: return "Off"
        }
    }
}

public struct LightingSettings: Codable, Equatable, Sendable {
    public var mode: LightingMode
    public var color: RGB16
    public var brightness: Int   // 1...15
    public var speed: Int        // 0...5
    public var direction: Int    // 0 = left, 1 = right

    public init(mode: LightingMode = .ambilight, color: RGB16 = RGB16(r: 15, g: 0, b: 15),
                brightness: Int = 7, speed: Int = 4, direction: Int = 0) {
        self.mode = mode
        self.color = color
        self.brightness = min(15, max(1, brightness))
        self.speed = min(5, max(0, speed))
        self.direction = min(1, max(0, direction))
    }
}

// MARK: - Settings

public struct DPIStage: Codable, Equatable, Sendable {
    public var value: Int
    public var enabled: Bool
    public var color: RGB16

    public init(value: Int, enabled: Bool = true, color: RGB16) {
        self.value = value
        self.enabled = enabled
        self.color = color
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var stages: [DPIStage]
    public var activeStage: Int
    public var pollingHz: Int
    public var buttons: [ButtonAction]
    public var doubleClickMs: Int
    public var lighting: LightingSettings
    public var fireIntervalMs: Int

    public init(stages: [DPIStage], activeStage: Int, pollingHz: Int,
                buttons: [ButtonAction], doubleClickMs: Int,
                lighting: LightingSettings, fireIntervalMs: Int) {
        self.stages = stages
        self.activeStage = activeStage
        self.pollingHz = pollingHz
        self.buttons = buttons
        self.doubleClickMs = doubleClickMs
        self.lighting = lighting
        self.fireIntervalMs = fireIntervalMs
    }

    public static let defaults = Settings(
        stages: [
            DPIStage(value: 1200, color: RGB16(r: 15, g: 15, b: 2)),
            DPIStage(value: 1600, color: RGB16(r: 1, g: 10, b: 15)),
            DPIStage(value: 3200, color: RGB16(r: 15, g: 0, b: 11)),
            DPIStage(value: 4000, color: RGB16(r: 0, g: 14, b: 2)),
            DPIStage(value: 5600, color: RGB16(r: 15, g: 0, b: 0)),
            DPIStage(value: 8000, color: RGB16(r: 0, g: 14, b: 14)),
        ],
        activeStage: 0,
        pollingHz: 1000,
        buttons: [.left, .right, .middle, .back, .forward, .dpiButton],
        doubleClickMs: 200,
        lighting: LightingSettings(),
        fireIntervalMs: 50
    )

    public var isValid: Bool {
        stages.count == 6
            && stages.allSatisfy { A825.supportedDPI.contains($0.value) }
            && stages.contains { $0.enabled }
            && (0..<6).contains(activeStage)
            && A825.pollingRates.contains(pollingHz)
            && buttons.count == 6
            && (100...255).contains(doubleClickMs)
            && (10...1000).contains(fireIntervalMs)
    }
}

// MARK: - Live state

public struct LiveState: Sendable {
    public var settings: Settings
    public var blocks: [Int: [UInt8]]
    public var ambiguousStages: Set<Int>
    public var unknownButtons: Set<Int>
    public var rawButtonCodes: [UInt8]
    public var rawDPICodes: [UInt8]
}

// MARK: - Device info

public struct HarpyDeviceInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let product: String
    public let vendorID: Int
    public let productID: Int
    public let serial: String?
    public let locationID: Int

    public var displayName: String { product.isEmpty ? "USB Gaming Mouse" : product }
    public var identifier: String { String(format: "%04X:%04X", vendorID, productID) }
}

public enum A825Error: LocalizedError {
    case invalidData(String)
    case unsupportedDevice

    public var errorDescription: String? {
        switch self {
        case .invalidData(let why): return "Unexpected data from the mouse: \(why)"
        case .unsupportedDevice: return "No compatible Instant A825 mouse was found."
        }
    }
}

// MARK: - Protocol encoding

public enum A825Protocol {
    public static func memoryPacket(_ op: UInt8, address: Int, offset: UInt8 = 0,
                                    value: UInt8 = 0, lastOffset: UInt8 = 0) -> [UInt8] {
        [A825.featureReportID, 0x18, op, offset,
         UInt8(address & 0xFF), UInt8((address >> 8) & 0xFF), value, lastOffset]
    }

    public static func readFrames(address: Int, length: Int) -> (prepare: [[UInt8]], requests: [[UInt8]], finish: [[UInt8]]) {
        let last = UInt8(length - 1)
        let prepare = (0..<length).map { memoryPacket(0x03, address: address, offset: UInt8($0), lastOffset: last) }
            + [memoryPacket(0x00, address: address)]
        let requests = (0..<length).map { memoryPacket(0x05, address: address, offset: UInt8($0), lastOffset: last) }
        let finish = [memoryPacket(0x09, address: address, lastOffset: last),
                      memoryPacket(0x00, address: address)]
        return (prepare, requests, finish)
    }

    public static func writeFrames(address: Int, data: [UInt8]) -> [[UInt8]] {
        let last = UInt8(data.count - 1)
        var frames = data.enumerated().map { index, byte in
            memoryPacket(0x03, address: address, offset: UInt8(index), value: byte, lastOffset: last)
        }
        frames.append(memoryPacket(0x09, address: address, lastOffset: last))
        frames.append(memoryPacket(0x00, address: address))
        return frames
    }

    public static func finalizeFrames() -> [[UInt8]] {
        [memoryPacket(0x10, address: 0), memoryPacket(0x00, address: 0),
         [A825.featureReportID, 0x20, 0, 0, 0, 0, 0, 0]]
    }

    public static func fireFrame(intervalMs: Int) -> [UInt8] {
        let ms = UInt16(min(1000, max(10, intervalMs)))
        return [A825.featureReportID, 0x17, UInt8(ms >> 8), UInt8(ms & 0xFF), 0, 0, 0, 0]
    }

    // MARK: Fragments

    public static func fragments(for settings: Settings) -> [Int: [UInt8]] {
        var out: [Int: [UInt8]] = [:]

        let order = [0, 2, 1, 3, 4, 5]
        var registers = [UInt8](repeating: ButtonAction.disabled.rawValue, count: 6)
        for register in 0..<6 { registers[register] = settings.buttons[order[register]].rawValue }
        out[0x0008] = registers

        let nibbles = settings.stages.map { A825.dpiCode(for: $0.value) ?? 0 }
        out[0x0015] = [(nibbles[0] << 4) | nibbles[1],
                       (nibbles[2] << 4) | nibbles[3],
                       (nibbles[4] << 4) | nibbles[5]]

        out[0x0018] = [UInt8(0x18 + settings.activeStage)]
        var mask: UInt8 = 0
        for (index, stage) in settings.stages.enumerated() where stage.enabled { mask |= 1 << UInt8(index) }
        out[0x0019] = [mask]
        out[0x001A] = [UInt8(min(255, max(100, settings.doubleClickMs)))]
        out[0x001E] = [A825.pollingDivisor(for: settings.pollingHz) ?? 0]

        var sequence: [UInt8] = []
        for stage in settings.stages {
            sequence.append(15 - stage.color.g)
            sequence.append(15 - stage.color.r)
            sequence.append(15 - stage.color.b)
        }
        var packed = [UInt8]()
        for index in 0..<9 {
            packed.append((sequence[index * 2] << 4) | sequence[index * 2 + 1])
        }
        out[0x0020] = Array(packed[0..<8])
        out[0x0028] = [packed[8]]

        return out
    }

    public static func blockAddresses(for settings: Settings) -> [Int] {
        Set(fragments(for: settings).keys.map { $0 / 8 * 8 }).sorted()
    }

    public static func domain(for address: Int) -> String {
        switch address {
        case 0x08: return "Buttons"
        case 0x15...0x17: return "DPI values"
        case 0x18...0x1E: return "DPI state"
        case 0x20, 0x28: return "Stage colors"
        default: return "Config"
        }
    }

    // MARK: Decode

    public static func decode(blocks: [Int: [UInt8]], defaults: Settings) throws -> LiveState {
        var settings = defaults
        var ambiguous = Set<Int>()
        var unknownButtons = Set<Int>()

        guard let buttonBlock = blocks[0x0008], buttonBlock.count >= 6 else {
            throw A825Error.invalidData("missing button block 0x0008")
        }
        let order = [0, 2, 1, 3, 4, 5]
        var rawCodes = [UInt8](repeating: 0, count: 6)
        for register in 0..<6 {
            let code = buttonBlock[register]
            rawCodes[order[register]] = code
            if let action = ButtonAction(rawValue: code) {
                settings.buttons[order[register]] = action
            } else {
                settings.buttons[order[register]] = .disabled
                unknownButtons.insert(order[register])
            }
        }

        guard let dpiBlock = blocks[0x0010], dpiBlock.count >= 8 else {
            throw A825Error.invalidData("missing DPI block 0x0010")
        }
        let dpiCodes: [UInt8] = [
            dpiBlock[5] >> 4, dpiBlock[5] & 0x0F,
            dpiBlock[6] >> 4, dpiBlock[6] & 0x0F,
            dpiBlock[7] >> 4, dpiBlock[7] & 0x0F,
        ]
        for index in 0..<6 {
            let code = dpiCodes[index]
            if A825.ambiguousCodes.contains(code) { ambiguous.insert(index) }
            if let value = A825.dpiValue(forCode: code, preferred: defaults.stages[index].value) {
                settings.stages[index].value = value
            }
        }

        guard let stateBlock = blocks[0x0018], stateBlock.count >= 7 else {
            throw A825Error.invalidData("missing state block 0x0018")
        }
        guard stateBlock[1] != 0 else {
            throw A825Error.invalidData("DPI enable mask is zero")
        }
        let mask = Int(stateBlock[1])
        for index in 0..<6 {
            settings.stages[index].enabled = (mask & (1 << index)) != 0
        }
        if (0x18...0x1D).contains(stateBlock[0]) {
            settings.activeStage = Int(stateBlock[0] - 0x18)
        }
        if (100...255).contains(Int(stateBlock[2])) {
            settings.doubleClickMs = Int(stateBlock[2])
        }
        if let rate = A825.pollingRate(forDivisor: stateBlock[6]) {
            settings.pollingHz = rate
        }

        if let high = blocks[0x0020], let low = blocks[0x0028], high.count >= 8, low.count >= 1 {
            let raw = Array(high[0..<8]) + [low[0]]
            var flat = [UInt8]()
            for byte in raw { flat.append(byte >> 4); flat.append(byte & 0x0F) }
            for stage in 0..<6 {
                let g = 15 - flat[stage * 3]
                let r = 15 - flat[stage * 3 + 1]
                let b = 15 - flat[stage * 3 + 2]
                settings.stages[stage].color = RGB16(r: r, g: g, b: b)
            }
        }

        return LiveState(settings: settings, blocks: blocks, ambiguousStages: ambiguous,
                         unknownButtons: unknownButtons, rawButtonCodes: rawCodes,
                         rawDPICodes: dpiCodes)
    }

    // MARK: Plan

    public struct PlannedWrite: Identifiable, Sendable {
        public let address: Int
        public let data: [UInt8]
        public let domains: [String]
        public var id: Int { address }
    }

    public struct WritePlan: Identifiable, Sendable {
        public let id = UUID()
        public let writes: [PlannedWrite]
        public let unchangedBlocks: [Int]
        public let changedDomains: [String]

        public var isEmpty: Bool { writes.isEmpty }
    }

    public static func plan(_ settings: Settings, live: [Int: [UInt8]]) throws -> WritePlan {
        let fragments = fragments(for: settings)
        let addresses = Set(fragments.keys.map { $0 / 8 * 8 }).sorted()
        var writes: [PlannedWrite] = []
        var unchanged: [Int] = []
        var changedDomains = Set<String>()

        for blockStart in addresses {
            guard let liveBlock = live[blockStart], liveBlock.count == 8 else {
                throw A825Error.invalidData(String(format: "missing live block 0x%04X", blockStart))
            }
            var merged = liveBlock
            var domains = Set<String>()
            for (address, data) in fragments {
                guard address / 8 * 8 == blockStart else { continue }
                domains.insert(domain(for: address))
                for (offset, byte) in data.enumerated() {
                    let absolute = address + offset
                    merged[absolute - blockStart] = byte
                }
            }
            if merged != liveBlock {
                writes.append(PlannedWrite(address: blockStart, data: merged,
                                           domains: domains.sorted()))
                changedDomains.formUnion(domains)
            } else {
                unchanged.append(blockStart)
            }
        }

        return WritePlan(writes: writes, unchangedBlocks: unchanged,
                         changedDomains: changedDomains.sorted())
    }

    // MARK: Live lighting

    public static func lightingFrames(_ lighting: LightingSettings, stages: [DPIStage]) -> [[UInt8]] {
        let mode = lighting.mode
        let colors: [RGB16]
        if mode == .off {
            colors = Array(repeating: .black, count: 6)
        } else if mode.supportsColor {
            colors = Array(repeating: lighting.color, count: 6)
        } else {
            colors = stages.map(\.color)
        }

        var frames: [[UInt8]] = []
        for (slot, color) in colors.enumerated() {
            let zone = UInt8(slot * 2)
            frames.append([
                A825.featureReportID, 0x14,
                (zone << 4) | (15 - color.g),
                ((15 - color.r) << 4) | (15 - color.b),
                0, 0, 0, 0,
            ])
        }

        let code = mode.code
        let speed = UInt8(min(5, max(0, lighting.speed)))
        let direction = UInt8(min(1, max(0, lighting.direction)))
        let brightness = mode == .off ? 0 : min(15, max(1, lighting.brightness))
        frames.append([
            A825.featureReportID, 0x13, 0xFF,
            ((code << 4) & 0xF0) | speed,
            (direction << 4) | 0x0B,
            UInt8(15 - brightness),
            code & 0xF0,
            0x00,
        ])
        return frames
    }
}
