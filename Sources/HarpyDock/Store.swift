import Foundation
import SwiftUI
import AppKit
import OSLog
@preconcurrency import HarpyDockCore

@MainActor
final class Store: ObservableObject {
    @Published var settings = Settings.defaults
    @Published var live: LiveState?
    @Published var connected = false
    @Published var busy = false
    @Published var statusText = "Not connected"
    @Published var errorText: String?
    @Published var confirmation: A825Protocol.WritePlan?
    @Published var log: [String] = []
    @Published var deviceName = "Kreo Harpy"
    @Published var deviceIdentifier = "30FA:1440"
    @Published var deviceSerial: String?
    @Published var permissionRequired = false

    private let logger = Logger(subsystem: "app.harpydock.mac", category: "device")
    private var device: HarpyHID?
    private let queue = DispatchQueue(label: "app.harpydock.hid")
    private var didConnect = false
    private let previewMode: Bool

    private var settingsURL: URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        let dir = base.appendingPathComponent("HarpyDock", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    init(preview: Bool = false) {
        previewMode = preview
        if !preview,
           let url = settingsURL,
           let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(Settings.self, from: data),
           saved.isValid {
            settings = saved
        }
    }

    var hasChanges: Bool {
        guard let live, settings.isValid else { return false }
        return (try? A825Protocol.plan(settings, live: live.blocks))?.isEmpty == false
    }

    var backupsURL: URL? { try? BindingBackup.directory() }

    // MARK: Connection

    func connectIfNeeded() {
        guard !previewMode else { return }
        guard !didConnect else { return }
        didConnect = true
        refresh()
    }

    func refresh() {
        guard !busy else { return }
        trace("refresh begin")
        if let device, connected {
            reload(using: device)
            return
        }
        guard let found = HarpyHID.first() else {
            device = nil
            connected = false
            statusText = "No compatible mouse found"
            trace("discover: no device")
            return
        }
        trace("discover: \(found.info.identifier)")
        device = found
        found.onPacket = { [weak self] line in
            DispatchQueue.main.async { self?.appendLog(line) }
        }
        connected = true
        deviceName = found.info.displayName
        deviceIdentifier = found.info.identifier
        deviceSerial = found.info.serial
        appendLog("Connected \(found.info.displayName) \(found.info.identifier)")
        logger.info("connected \(found.info.displayName, privacy: .public) \(found.info.identifier, privacy: .public)")
        reload(using: found)
    }

    func reload() {
        guard let device else { refresh(); return }
        reload(using: device)
    }

    private func reload(using device: HarpyHID) {
        busy = true
        let defaults = settings
        queue.async {
            do {
                let live = try device.readState(defaults: defaults)
                DispatchQueue.main.async {
                    self.live = live
                    self.settings = live.settings
                    self.busy = false
                    self.errorText = nil
                    self.connected = true
                    self.statusText = "Read \(live.settings.stages.count) stages, \(live.settings.pollingHz) Hz"
                    self.trace("read ok: \(live.settings.pollingHz) Hz active \(live.settings.activeStage + 1)")
                    self.logger.info("read \(live.settings.stages.count) stages \(live.settings.pollingHz) Hz")
                    if !live.ambiguousStages.isEmpty {
                        self.appendLog("Note: DPI code 8 can mean 1600 or 12800; kept the current value")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.busy = false
                    self.connected = false
                    self.device = nil
                    self.live = nil
                    let permission = (error as? HarpyIOError)?.isPermission ?? false
                    self.permissionRequired = permission
                    if !permission { self.errorText = error.localizedDescription }
                    self.statusText = permission ? "Input Monitoring required" : "Disconnected"
                    self.appendLog("ERROR " + error.localizedDescription)
                    self.logger.error("read failed: \(error.localizedDescription, privacy: .public)")
                    self.trace("read failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: Writes

    func requestApply() {
        guard let live else { errorText = "Read the mouse before applying."; return }
        guard settings.isValid else { errorText = "Some values are outside the supported range."; return }
        do {
            let plan = try A825Protocol.plan(settings, live: live.blocks)
            if plan.isEmpty {
                statusText = "No persistent changes to write"
                return
            }
            confirmation = plan
        } catch {
            errorText = error.localizedDescription
        }
    }

    func commit(_ plan: A825Protocol.WritePlan) {
        guard let device, let live else { return }
        confirmation = nil
        busy = true
        let snapshot = settings
        let liveBlocks = live.blocks
        queue.async {
            do {
                // Read, diff, back up, write, and verify under one device lock.
                let result = try device.withDeviceLock { () -> (LiveState, HarpyHID.ApplyOutcome, URL)? in
                    let current = try device.readState(defaults: snapshot)
                    for address in plan.writes.map(\.address) {
                        guard current.blocks[address] == liveBlocks[address] else {
                            throw A825Error.invalidData("The mouse changed since you reviewed the write. Reload and try again.")
                        }
                    }
                    let freshPlan = try A825Protocol.plan(snapshot, live: current.blocks)
                    guard !freshPlan.isEmpty else { return nil }
                    let backup = try BindingBackup.write(blocks: current.blocks, info: device.info)
                    let outcome = try device.apply(freshPlan, live: current.blocks)
                    let fresh = try device.readState(defaults: snapshot)
                    return (fresh, outcome, backup)
                }
                guard let (fresh, outcome, backup) = result else {
                    DispatchQueue.main.async {
                        self.busy = false
                        self.statusText = "No persistent changes to write"
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.live = fresh
                    self.settings = fresh.settings
                    self.busy = false
                    self.errorText = nil
                    self.connected = true
                    self.statusText = "Wrote \(outcome.writtenBlocks.count) block(s), verified"
                    self.appendLog("Backup " + backup.lastPathComponent)
                    self.appendLog("Verified " + outcome.changedDomains.joined(separator: ", "))
                    self.saveSettings()
                }
            } catch {
                DispatchQueue.main.async {
                    self.busy = false
                    self.errorText = error.localizedDescription
                    self.statusText = "Write failed"
                    self.appendLog("ERROR " + error.localizedDescription)
                }
            }
        }
    }

    func sendLighting() {
        guard let device else { errorText = "The mouse is not connected."; return }
        busy = true
        let lighting = settings.lighting
        let stages = settings.stages
        queue.async {
            do {
                try device.sendLighting(lighting, stages: stages)
                DispatchQueue.main.async {
                    self.busy = false
                    self.statusText = "Lighting sent (\(lighting.mode.label))"
                    self.errorText = nil
                    self.appendLog("Live lighting sent")
                    self.saveSettings()
                }
            } catch {
                DispatchQueue.main.async {
                    self.busy = false
                    self.errorText = error.localizedDescription
                    self.appendLog("ERROR " + error.localizedDescription)
                }
            }
        }
    }

    func sendFireInterval() {
        guard let device else { errorText = "The mouse is not connected."; return }
        busy = true
        let ms = settings.fireIntervalMs
        queue.async {
            do {
                try device.sendFireInterval(ms)
                DispatchQueue.main.async {
                    self.busy = false
                    self.statusText = "Rapid fire set to \(ms) ms"
                    self.errorText = nil
                    self.appendLog("Live fire interval sent: \(ms) ms")
                    self.saveSettings()
                }
            } catch {
                DispatchQueue.main.async {
                    self.busy = false
                    self.errorText = error.localizedDescription
                    self.appendLog("ERROR " + error.localizedDescription)
                }
            }
        }
    }

    // MARK: Helpers

    func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    func retryAfterPermission() {
        permissionRequired = false
        connected = false
        device = nil
        didConnect = true
        refresh()
    }

    func revert() {
        guard let live else { return }
        settings = live.settings
        statusText = "Reverted to the values read from the mouse"
    }

    func revealBackups() {
        guard let backupsURL else { return }
        NSWorkspace.shared.open(backupsURL)
    }

    private func trace(_ message: String) {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return }
        let dir = base.appendingPathComponent("HarpyDock", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("last-run.log")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber, size.intValue > 64_000 {
            try? FileManager.default.removeItem(at: url)
        }
        let line = ISO8601DateFormatter().string(from: Date()) + "  " + message + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    func appendLog(_ line: String) {
        log.append(line)
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }

    private func saveSettings() {
        guard !previewMode else { return }
        guard let url = settingsURL, let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
