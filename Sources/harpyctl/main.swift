import Foundation
@preconcurrency import HarpyDockCore

func usage() {
    print("""
    harpyctl - Instant A825 (Kreo Harpy) diagnostics

      harpyctl list        list matching USB devices
      harpyctl dump        read and decode the six owned config blocks
      harpyctl probe       dump the raw eight-byte blocks
      harpyctl selftest    rewrite block 0x0008 with identical bytes and verify

    All commands are read-only except selftest, which writes back the exact
    bytes it just read. No firmware, no arbitrary addresses.
    """)
}

func preferredSettings() -> Settings {
    guard let base = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: nil, create: false) else { return .defaults }
    let url = base.appendingPathComponent("HarpyDock/settings.json")
    guard let data = try? Data(contentsOf: url),
          let saved = try? JSONDecoder().decode(Settings.self, from: data),
          saved.isValid else { return .defaults }
    return saved
}

func openDevice() throws -> HarpyHID {
    guard let device = HarpyHID.first() else { throw HarpyIOError.notFound }
    print("Device  \(device.info.displayName)  \(device.info.identifier)  serial \(device.info.serial ?? "-")")
    return device
}

func printState(_ live: LiveState) {
    let s = live.settings
    print("Polling     \(s.pollingHz) Hz")
    print("Active DPI  stage \(s.activeStage + 1)")
    print("Stages")
    for (index, stage) in s.stages.enumerated() {
        let note = live.ambiguousStages.contains(index) ? "  (wrapped code: several DPI values share it)" : ""
        let enabled = stage.enabled ? "on " : "off"
        print(String(format: "  %d  %@  %5d dpi  %@%@", index + 1, enabled, stage.value, stage.color.hex, note))
    }
    print("Buttons")
    for (index, action) in s.buttons.enumerated() {
        let note = live.unknownButtons.contains(index) ? "  (unknown code)" : ""
        print(String(format: "  %-12@ %@%@", ButtonAction.buttonNames[index] as NSString, action.label, note))
    }
    print(String(format: "Double-click %d ms", s.doubleClickMs))
    print("Raw DPI codes   \(live.rawDPICodes.map { String(format: "%X", $0) }.joined(separator: " "))")
    print("Raw buttons     \(live.rawButtonCodes.map { String(format: "%02X", $0) }.joined(separator: " "))")
}

let args = Array(CommandLine.arguments.dropFirst())
let command = args.first ?? "dump"

do {
    switch command {
    case "list":
        let devices = HarpyHID.discover()
        if devices.isEmpty { print("No matching device."); exit(1) }
        for device in devices {
            print("\(device.info.displayName)  \(device.info.identifier)  serial \(device.info.serial ?? "-")  location \(String(format: "0x%08X", device.info.locationID))")
        }
    case "dump":
        let device = try openDevice()
        let live = try device.readState(defaults: preferredSettings())
        printState(live)
    case "probe":
        let device = try openDevice()
        for address in A825.ownedBlocks {
            let bytes = try device.readMemory(address: address, length: 8)
            print(String(format: "0x%04X  %@", address, bytes.map { String(format: "%02X", $0) }.joined(separator: " ")))
        }
    case "selftest":
        let device = try openDevice()
        _ = try device.readState(defaults: preferredSettings())
        let address = 0x0008
        let (original, after) = try device.withDeviceLock { () -> ([UInt8], [UInt8]) in
            let original = try device.readMemory(address: address, length: 8)
            print("Before  " + original.map { String(format: "%02X", $0) }.joined(separator: " "))
            try device.writeMemory(address: address, data: original)
            for frame in A825Protocol.finalizeFrames() { try device.send(frame); usleep(2_000) }
            return (original, try device.readMemory(address: address, length: 8))
        }
        print("After   " + after.map { String(format: "%02X", $0) }.joined(separator: " "))
        guard after == original else { print("FAILED: read-back differs."); exit(2) }
        print("OK: identical bytes rewritten and verified. The mouse state did not change.")
    default:
        usage()
    }
} catch {
    FileHandle.standardError.write(("error: " + error.localizedDescription + "\n").data(using: .utf8)!)
    exit(1)
}
