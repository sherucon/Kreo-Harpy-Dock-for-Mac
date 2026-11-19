import Foundation
import IOKit
import IOKit.hid

public enum HarpyIOError: LocalizedError {
    case notFound
    case busy
    case permissionDenied
    case openFailed(IOReturn)
    case ioFailed(String, IOReturn)

    public var isPermission: Bool {
        if case .permissionDenied = self { return true }
        if case .ioFailed(_, kIOReturnNotPermitted) = self { return true }
        if case .ioFailed(_, kIOReturnNotOpen) = self { return true }
        return false
    }
    case malformedReport
    case verificationFailed(address: Int, expected: [UInt8], actual: [UInt8])

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "No Instant A825 mouse with the vendor feature report was found. Check the USB cable."
        case .busy:
            return "Another Harpy process is reading or writing the mouse. Quit the other app or CLI and try again."
        case .permissionDenied:
            return "macOS requires Input Monitoring for Harpy Dock. Enable Harpy Dock in System Settings > Privacy & Security > Input Monitoring, then click Retry (or relaunch the app)."
        case .openFailed(let code):
            return "Could not open the mouse (IOKit \(String(format: "0x%08X", code))). Unplug other configuration apps and try again."
        case .ioFailed(let what, let code):
            if code == kIOReturnNotPermitted {
                return "macOS blocked HID access. Enable Harpy Dock in System Settings > Privacy & Security > Input Monitoring, then relaunch the app."
            }
            return "\(what) failed (IOKit \(String(format: "0x%08X", code)))."
        case .malformedReport:
            return "The mouse returned a malformed feature report."
        case .verificationFailed(let address, let expected, let actual):
            let e = expected.map { String(format: "%02X", $0) }.joined(separator: " ")
            let a = actual.map { String(format: "%02X", $0) }.joined(separator: " ")
            return String(format: "Read-back mismatch at 0x%04X. Wrote %@, read %@. The previous block was restored.", address, e, a)
        }
    }
}

/// Serializes HID transactions across processes. Two readers interleaving the
/// 0x18 transaction can observe (and later write) corrupted bytes.
final class DeviceAccessLock {
    static let shared = DeviceAccessLock()

    private let mutex = NSRecursiveLock()
    private var descriptor: Int32 = -1
    private var depth = 0
    private let path: String

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let dir = base.appendingPathComponent("HarpyDock", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        path = dir.appendingPathComponent("device.lock").path
    }

    func acquire() throws {
        mutex.lock()
        if depth > 0 {
            depth += 1
            mutex.unlock()
            return
        }
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else {
            mutex.unlock()
            throw HarpyIOError.busy
        }
        var attempts = 0
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            attempts += 1
            if attempts > 300 {
                close(fd)
                mutex.unlock()
                throw HarpyIOError.busy
            }
            usleep(10_000)
        }
        descriptor = fd
        depth = 1
        mutex.unlock()
    }

    func release() {
        mutex.lock()
        depth -= 1
        if depth == 0, descriptor >= 0 {
            flock(descriptor, LOCK_UN)
            close(descriptor)
            descriptor = -1
        }
        mutex.unlock()
    }
}

public final class HarpyHID: @unchecked Sendable {
    public let info: HarpyDeviceInfo

    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private var isOpen = false

    /// Called for every packet, on the calling thread. The app hops to main.
    public var onPacket: ((String) -> Void)?

    private init(manager: IOHIDManager, device: IOHIDDevice, info: HarpyDeviceInfo) {
        self.manager = manager
        self.device = device
        self.info = info
    }

    deinit {
        if isOpen { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    // MARK: Discovery

    public static func discover() -> [HarpyHID] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [kIOHIDVendorIDKey as String: A825.vendorID]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        _ = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.03, false)

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return []
        }

        var found: [HarpyHID] = []
        for device in devices {
            guard let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int,
                  vendor == A825.vendorID,
                  let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int,
                  A825.productIDs.contains(productID),
                  declaresFeatureReport7(device) else { continue }

            let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "USB Gaming Mouse"
            let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String
            let location = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int ?? 0
            let info = HarpyDeviceInfo(
                id: String(format: "%04X:%04X@%08X", vendor, productID, location),
                product: product, vendorID: vendor, productID: productID,
                serial: serial, locationID: location)
            found.append(HarpyHID(manager: manager, device: device, info: info))
        }

        if found.isEmpty {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        return found
    }

    public static func first() -> HarpyHID? { discover().first }

    private static func declaresFeatureReport7(_ device: IOHIDDevice) -> Bool {
        let maxFeature = IOHIDDeviceGetProperty(device, kIOHIDMaxFeatureReportSizeKey as CFString) as? Int ?? 0
        if let data = IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data {
            let bytes = [UInt8](data)
            if bytes.count >= 2, maxFeature >= 8 {
                for index in 0..<(bytes.count - 1)
                where bytes[index] == 0x85 && bytes[index + 1] == A825.featureReportID {
                    return true
                }
            }
        }
        return false
    }

    // MARK: Lifecycle

    public func open() throws {
        guard !isOpen else { return }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnNotPermitted {
            throw HarpyIOError.permissionDenied
        }
        if result != kIOReturnSuccess && result != kIOReturnExclusiveAccess {
            throw HarpyIOError.openFailed(result)
        }
        isOpen = true
    }

    // MARK: Raw feature I/O

    @discardableResult
    public func send(_ packet: [UInt8]) throws -> [UInt8] {
        guard packet.count == A825.reportLength, packet[0] == A825.featureReportID else {
            throw HarpyIOError.malformedReport
        }
        try open()
        try DeviceAccessLock.shared.acquire()
        defer { DeviceAccessLock.shared.release() }
        sendLog("SEND " + packet.map { String(format: "%02X", $0) }.joined(separator: " "))
        let result = packet.withUnsafeBufferPointer { buffer in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature,
                                 CFIndex(A825.featureReportID), buffer.baseAddress!,
                                 CFIndex(packet.count))
        }
        guard result == kIOReturnSuccess else {
            if result == kIOReturnNotPermitted || result == kIOReturnNotOpen {
                throw HarpyIOError.permissionDenied
            }
            throw HarpyIOError.ioFailed("SetFeature", result)
        }
        return packet
    }

    public func receive() throws -> [UInt8] {
        try open()
        try DeviceAccessLock.shared.acquire()
        defer { DeviceAccessLock.shared.release() }
        var buffer = [UInt8](repeating: 0, count: A825.reportLength)
        buffer[0] = A825.featureReportID
        var length = CFIndex(A825.reportLength)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature,
                                          CFIndex(A825.featureReportID), &buffer, &length)
        guard result == kIOReturnSuccess else {
            if result == kIOReturnNotPermitted || result == kIOReturnNotOpen {
                throw HarpyIOError.permissionDenied
            }
            throw HarpyIOError.ioFailed("GetFeature", result)
        }
        guard length >= 2 else { throw HarpyIOError.malformedReport }
        sendLog("RECV " + buffer.map { String(format: "%02X", $0) }.joined(separator: " "))
        return Array(buffer.prefix(A825.reportLength))
    }

    private func sendLog(_ line: String) { onPacket?(line) }

    // MARK: Memory transactions

    public func readMemory(address: Int, length: Int) throws -> [UInt8] {
        try DeviceAccessLock.shared.acquire()
        defer { DeviceAccessLock.shared.release() }
        let frames = A825Protocol.readFrames(address: address, length: length)
        for frame in frames.prepare {
            try send(frame)
            usleep(2_000)
        }
        var result: [UInt8] = []
        result.reserveCapacity(length)
        for frame in frames.requests {
            try send(frame)
            usleep(2_000)
            let report = try receive()
            result.append(report[1])
        }
        usleep(2_000)
        for frame in frames.finish {
            try send(frame)
            usleep(2_000)
        }
        return result
    }

    public func writeMemory(address: Int, data: [UInt8]) throws {
        guard !data.isEmpty, data.count <= 32,
              address / 32 == (address + data.count - 1) / 32 else {
            throw A825Error.invalidData("write crosses a 32-byte controller page")
        }
        try DeviceAccessLock.shared.acquire()
        defer { DeviceAccessLock.shared.release() }
        for frame in A825Protocol.writeFrames(address: address, data: data) {
            try send(frame)
            usleep(2_000)
        }
    }

    // MARK: State

    public func withDeviceLock<T>(_ body: () throws -> T) throws -> T {
        try DeviceAccessLock.shared.acquire()
        defer { DeviceAccessLock.shared.release() }
        return try body()
    }

    public func readState(defaults: Settings) throws -> LiveState {
        try DeviceAccessLock.shared.acquire()
        defer { DeviceAccessLock.shared.release() }
        var blocks: [Int: [UInt8]] = [:]
        for address in A825.ownedBlocks {
            blocks[address] = try readMemory(address: address, length: 8)
        }
        return try A825Protocol.decode(blocks: blocks, defaults: defaults)
    }

    // MARK: Apply

    public struct ApplyOutcome {
        public let writtenBlocks: [Int]
        public let changedDomains: [String]
        public let packets: Int
    }

    public func apply(_ plan: A825Protocol.WritePlan, live: [Int: [UInt8]]) throws -> ApplyOutcome {
        try DeviceAccessLock.shared.acquire()
        defer { DeviceAccessLock.shared.release() }
        var packets = 0
        do {
            for write in plan.writes {
                try writeMemory(address: write.address, data: write.data)
                packets += write.data.count + 2
            }
            if !plan.writes.isEmpty {
                for frame in A825Protocol.finalizeFrames() {
                    try send(frame)
                    usleep(2_000)
                    packets += 1
                }
            }
            for write in plan.writes {
                let actual = try readMemory(address: write.address, length: 8)
                guard actual == write.data else {
                    throw HarpyIOError.verificationFailed(address: write.address,
                                                          expected: write.data, actual: actual)
                }
            }
        } catch {
            // Best effort: put every changed block back the way it was.
            for write in plan.writes {
                if let original = live[write.address] {
                    try? writeMemory(address: write.address, data: original)
                }
            }
            throw error
        }
        return ApplyOutcome(writtenBlocks: plan.writes.map(\.address),
                            changedDomains: plan.changedDomains, packets: packets)
    }

    // MARK: Live reports

    public func sendLighting(_ lighting: LightingSettings, stages: [DPIStage]) throws {
        try DeviceAccessLock.shared.acquire()
        defer { DeviceAccessLock.shared.release() }
        for frame in A825Protocol.lightingFrames(lighting, stages: stages) {
            try send(frame)
            usleep(2_000)
        }
    }

    public func sendFireInterval(_ ms: Int) throws {
        try send(A825Protocol.fireFrame(intervalMs: ms))
        usleep(2_000)
    }
}

// MARK: - Backups

public enum BindingBackup {
    public struct Backup: Codable {
        public let date: Date
        public let product: String
        public let identifier: String
        public let serial: String?
        public let blocks: [String: String]
    }

    public static func directory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("HarpyDock/Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    public static func write(blocks: [Int: [UInt8]], info: HarpyDeviceInfo) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let hex = Dictionary(uniqueKeysWithValues: blocks.map {
            (String(format: "0x%04X", $0.key), $0.value.map { String(format: "%02X", $0) }.joined())
        })
        let backup = Backup(date: Date(), product: info.displayName,
                            identifier: info.identifier, serial: info.serial, blocks: hex)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = try directory().appendingPathComponent("backup-\(stamp).json")
        try encoder.encode(backup).write(to: url, options: .atomic)
        return url
    }
}
