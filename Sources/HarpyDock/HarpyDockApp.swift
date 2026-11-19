import SwiftUI
import AppKit
@preconcurrency import HarpyDockCore

@main
struct HarpyDockApp: App {
    @StateObject private var store = Store()
    private let shotPath: String?
    private let shotPane: Pane?
    private let shotApply: Bool
    private let shotLive: Bool

    init() {
        if !CommandLine.arguments.contains("--window-shot"),
           let bundleID = Bundle.main.bundleIdentifier,
           let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
               .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            other.activate(options: [.activateAllWindows])
            exit(0)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--window-shot"),
           index + 1 < CommandLine.arguments.count {
            shotPath = CommandLine.arguments[index + 1]
            let name = index + 2 < CommandLine.arguments.count ? CommandLine.arguments[index + 2] : "dpi"
            shotApply = name == "apply"
            shotLive = name == "live"
            shotPane = Pane(rawValue: name)
        } else {
            shotPath = nil
            shotPane = nil
            shotApply = false
            shotLive = false
        }
    }

    var body: some Scene {
        WindowGroup {
            if let shotPath {
                WindowShotView(path: shotPath, pane: shotPane, showApply: shotApply, live: shotLive)
            } else {
                ContentView()
                    .environmentObject(store)
                    .frame(minWidth: 900, idealWidth: 980, minHeight: 640, idealHeight: 720)
            }
        }
        .defaultSize(width: 980, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

// MARK: - Panes

enum Pane: String, CaseIterable, Identifiable {
    case dpi, buttons, lighting, advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dpi: return "DPI & Rate"
        case .buttons: return "Buttons"
        case .lighting: return "Lighting"
        case .advanced: return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .dpi: return "scope"
        case .buttons: return "computermouse"
        case .lighting: return "lightbulb"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

// MARK: - Root view

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @State private var pane: Pane

    init(initialPane: Pane = .dpi) {
        _pane = State(initialValue: initialPane)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.permissionRequired {
                permissionBanner
            } else if !store.connected {
                disconnectedBanner
            }
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 190)
                Divider()
                ScrollView {
                    detail
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider()
            footer
        }
        .alert("Harpy Dock", isPresented: Binding(
            get: { store.errorText != nil },
            set: { if !$0 { store.errorText = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorText = nil }
        } message: {
            Text(store.errorText ?? "")
        }
        .sheet(item: $store.confirmation) { plan in
            ApplySheet(plan: plan).environmentObject(store)
        }
        .onAppear { store.connectIfNeeded() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "computermouse.fill")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Harpy Dock").font(.title3.weight(.semibold))
                Text("Kreo Harpy · Instant A825 · \(store.deviceIdentifier)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusPill
            Button {
                store.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(store.busy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(store.connected ? Color.green : Color.secondary.opacity(0.6))
                .frame(width: 7, height: 7)
            Text(store.connected ? "Connected" : "Not connected")
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
    }

    private var disconnectedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("No mouse is connected. Values below are the last profile and cannot be written.")
                .font(.callout)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    private var permissionBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Input Monitoring is required")
                    .font(.callout.weight(.semibold))
                Text("Enable Harpy Dock in System Settings > Privacy & Security > Input Monitoring, then click Retry (or relaunch).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") { store.openInputMonitoringSettings() }
            Button("Retry") { store.retryAfterPermission() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.10))
    }

    private var sidebar: some View {
        VStack(spacing: 2) {
            ForEach(Pane.allCases) { item in
                Button {
                    pane = item
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.icon)
                            .frame(width: 16)
                        Text(item.title)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(pane == item ? Color.accentColor.opacity(0.13) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(pane == item ? Color.accentColor : Color.primary)
            }
            Spacer()
        }
        .padding(8)
    }

    @ViewBuilder
    private var detail: some View {
        switch pane {
        case .dpi: DPIPane()
        case .buttons: ButtonsPane()
        case .lighting: LightingPane()
        case .advanced: AdvancedPane()
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if store.busy {
                ProgressView().controlSize(.small)
            }
            Text(store.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button("Revert") { store.revert() }
                .disabled(store.busy || store.live == nil)
            Button("Apply persistent settings") { store.requestApply() }
                .buttonStyle(.borderedProminent)
                .disabled(store.busy || !store.connected || !store.hasChanges)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Shared UI

struct PaneHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.weight(.semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct NoteRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - DPI

struct DPIPane: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PaneHeader(
                title: "DPI stages",
                subtitle: "Six hardware stages. The circle selects the active stage; the color is that stage's indicator LED."
            )

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                        GridRow {
                            Color.clear.frame(width: 18, height: 1)
                            Text("On").frame(width: 36, alignment: .center)
                            Text("Stage").frame(width: 42, alignment: .leading)
                            Text("Sensitivity").frame(width: 120, alignment: .leading)
                            Text("Color").frame(width: 50, alignment: .leading)
                            Text("Code").frame(width: 40, alignment: .leading)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        ForEach(0..<6, id: \.self) { index in
                            GridRow {
                                Button {
                                    store.settings.activeStage = index
                                } label: {
                                    Text(store.settings.activeStage == index ? "◉" : "○")
                                        .font(.system(size: 14))
                                        .foregroundStyle(store.settings.activeStage == index
                                                         ? Color.accentColor : Color.secondary)
                                }
                                .buttonStyle(.plain)
                                .frame(width: 18)
                                .accessibilityLabel("Make stage \(index + 1) active")

                                Toggle("", isOn: enabledBinding(index))
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()
                                    .frame(width: 36, alignment: .leading)
                                    .accessibilityLabel("Stage \(index + 1) enabled")

                                Text("\(index + 1)")
                                    .monospacedDigit()
                                    .frame(width: 42, alignment: .leading)

                                Picker("", selection: dpiBinding(index)) {
                                    ForEach(A825.supportedDPI, id: \.self) { value in
                                        Text(verbatim: "\(value) DPI").tag(value)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 120)
                                .accessibilityLabel("Stage \(index + 1) DPI")

                                ColorPicker("", selection: colorBinding(index))
                                    .labelsHidden()
                                    .frame(width: 50)
                                    .accessibilityLabel("Stage \(index + 1) color")

                                Text(codeText(index))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .leading)
                            }
                        }
                    }

                    if !ambiguous.isEmpty {
                        let list = ambiguous.map(String.init)
                        let stages = list.count == 1 ? list[0] : list.dropLast().joined(separator: ", ") + " and " + list.last!
                        NoteRow(systemImage: "questionmark.circle",
                                text: "Stage \(stages) \(list.count == 1 ? "uses" : "use") a wrapped sensor code. The chip stores four bits, so the same code can mean two DPI values; the current value was kept.")
                    }
                }
                .padding(8)
            } label: {
                Text("Hardware stages").font(.headline)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("USB report rate", selection: pollingBinding) {
                        ForEach(A825.pollingRates, id: \.self) { rate in
                            Text("\(rate) Hz").tag(rate)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 360, alignment: .leading)
                    .accessibilityLabel("USB report rate")
                    NoteRow(systemImage: "bolt",
                            text: "The mouse stores the polling divisor. Higher rates use more USB bandwidth.")
                }
                .padding(8)
            } label: {
                Text("USB report rate").font(.headline)
            }

            NoteRow(systemImage: "checkmark.shield",
                    text: "These values live in the mouse's configuration memory. Nothing is written until you press Apply and confirm.")
        }
    }

    private var ambiguous: [Int] {
        Array(store.live?.ambiguousStages ?? []).sorted().map { $0 + 1 }
    }

    private func codeText(_ index: Int) -> String {
        guard let code = store.live?.rawDPICodes[index] else { return "–" }
        return String(format: "%X", code)
    }

    private func dpiBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { store.settings.stages[index].value },
            set: { store.settings.stages[index].value = $0 }
        )
    }

    private func enabledBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { store.settings.stages[index].enabled },
            set: { newValue in
                if !newValue && store.settings.stages.filter({ $0.enabled }).count == 1 {
                    store.statusText = "At least one DPI stage must stay enabled"
                    return
                }
                store.settings.stages[index].enabled = newValue
            }
        )
    }

    private func colorBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: { store.settings.stages[index].color.swiftUIColor },
            set: { store.settings.stages[index].color = RGB16($0) }
        )
    }

    private var pollingBinding: Binding<Int> {
        Binding(
            get: { store.settings.pollingHz },
            set: { store.settings.pollingHz = $0 }
        )
    }
}

// MARK: - Buttons

struct ButtonsPane: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PaneHeader(
                title: "Button mapping",
                subtitle: "Six hardware buttons. Keyboard, media, and macro assignments are not part of this version."
            )

            GroupBox {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    ForEach(0..<6, id: \.self) { index in
                        GridRow {
                            Text(ButtonAction.buttonNames[index])
                                .frame(width: 90, alignment: .leading)
                            Picker("", selection: buttonBinding(index)) {
                                ForEach(ButtonAction.allCases) { action in
                                    Text(action.label).tag(action)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 210, alignment: .leading)
                            .accessibilityLabel("\(ButtonAction.buttonNames[index]) action")

                            if store.live?.unknownButtons.contains(index) == true {
                                Text("unknown code")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .padding(8)
            } label: {
                Text("Assignments").font(.headline)
            }

            NoteRow(systemImage: "info.circle",
                    text: "The DPI button accepts the native DPI actions. Rapid fire uses the interval on the Advanced pane.")
            NoteRow(systemImage: "exclamationmark.triangle",
                    text: "The controller may keep the old button table until the mouse is unplugged for about ten seconds. Persistent bytes are verified, but the firmware reload is outside the app's control.")
        }
    }

    private func buttonBinding(_ index: Int) -> Binding<ButtonAction> {
        Binding(
            get: { store.settings.buttons[index] },
            set: { store.settings.buttons[index] = $0 }
        )
    }
}

// MARK: - Lighting

struct LightingPane: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PaneHeader(
                title: "Lighting",
                subtitle: "Effects are live reports. The mouse forgets them when it loses power, so send them again after reconnecting."
            )

            GroupBox {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                    GridRow {
                        Text("Mode").frame(width: 88, alignment: .leading)
                        Picker("", selection: modeBinding) {
                            ForEach(LightingMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 210)
                        .accessibilityLabel("Lighting mode")
                    }

                    GridRow {
                        Text("Color").frame(width: 88, alignment: .leading)
                        if store.settings.lighting.mode.supportsColor {
                            ColorPicker("", selection: lightingColorBinding)
                                .labelsHidden()
                            .accessibilityLabel("Lighting color")
                            Text(store.settings.lighting.color.hex)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(store.settings.lighting.mode == .off
                                 ? "All zones off"
                                 : "Uses the six stage colors")
                                .foregroundStyle(.secondary)
                        }
                    }

                    GridRow {
                        Text("Brightness").frame(width: 88, alignment: .leading)
                        Slider(value: brightnessBinding, in: 1...15, step: 1)
                            .frame(width: 220)
                            .accessibilityLabel("Brightness")
                        Text("\(store.settings.lighting.brightness) / 15")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    GridRow {
                        Text("Speed").frame(width: 88, alignment: .leading)
                        Slider(value: speedBinding, in: 0...5, step: 1)
                            .frame(width: 220)
                            .accessibilityLabel("Speed")
                        Text("\(store.settings.lighting.speed) / 5")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    GridRow {
                        Text("Direction").frame(width: 88, alignment: .leading)
                        Picker("", selection: directionBinding) {
                            Text("Left").tag(0)
                            Text("Right").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 140)
                        .accessibilityLabel("Direction")
                    }
                }
                .padding(8)
            } label: {
                Text("Effect").font(.headline)
            }

            HStack(spacing: 10) {
                Button {
                    store.sendLighting()
                } label: {
                    Label("Send lighting to mouse", systemImage: "lightbulb")
                }
                .buttonStyle(.bordered)
                .disabled(store.busy || !store.connected)

                Text("Live only · not stored in the mouse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            NoteRow(systemImage: "paintpalette",
                    text: "Stage colors in the DPI pane are stored separately and are used by stage-color effects.")
        }
    }

    private var modeBinding: Binding<LightingMode> {
        Binding(
            get: { store.settings.lighting.mode },
            set: { store.settings.lighting.mode = $0 }
        )
    }

    private var lightingColorBinding: Binding<Color> {
        Binding(
            get: { store.settings.lighting.color.swiftUIColor },
            set: { store.settings.lighting.color = RGB16($0) }
        )
    }

    private var brightnessBinding: Binding<Double> {
        Binding(
            get: { Double(store.settings.lighting.brightness) },
            set: { store.settings.lighting.brightness = Int($0) }
        )
    }

    private var speedBinding: Binding<Double> {
        Binding(
            get: { Double(store.settings.lighting.speed) },
            set: { store.settings.lighting.speed = Int($0) }
        )
    }

    private var directionBinding: Binding<Int> {
        Binding(
            get: { store.settings.lighting.direction },
            set: { store.settings.lighting.direction = $0 }
        )
    }
}

// MARK: - Advanced

struct AdvancedPane: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PaneHeader(
                title: "Advanced",
                subtitle: "Rapid-fire timing, double-click timing, backups, and the raw feature-report log."
            )

            GroupBox {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                    GridRow {
                        Text("Rapid fire").frame(width: 100, alignment: .leading)
                        Stepper(value: fireBinding, in: 10...1000, step: 10) {
                            Text("\(store.settings.fireIntervalMs) ms")
                                .monospacedDigit()
                                .frame(width: 70, alignment: .leading)
                        }
                        Button("Send") { store.sendFireInterval() }
                            .disabled(store.busy || !store.connected)
                            .accessibilityLabel("Send rapid fire interval")
                        Text("live").font(.caption).foregroundStyle(.secondary)
                    }

                    GridRow {
                        Text("Double click").frame(width: 100, alignment: .leading)
                        Stepper(value: doubleClickBinding, in: 100...255, step: 5) {
                            Text("\(store.settings.doubleClickMs) ms")
                                .monospacedDigit()
                                .frame(width: 70, alignment: .leading)
                        }
                        Text("stored").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(8)
            } label: {
                Text("Timing").font(.headline)
            }

            GroupBox {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow { Text("Product").foregroundStyle(.secondary); Text(store.deviceName) }
                    GridRow { Text("USB ID").foregroundStyle(.secondary); Text(store.deviceIdentifier).monospaced() }
                    GridRow { Text("Serial").foregroundStyle(.secondary); Text(store.deviceSerial ?? "–").monospaced() }
                    GridRow { Text("Backups").foregroundStyle(.secondary)
                        Button("Show backups in Finder") { store.revealBackups() } }
                }
                .padding(8)
            } label: {
                Text("Device").font(.headline)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    NoteRow(systemImage: "lock.shield",
                            text: "Only six documented configuration blocks (0x0008, 0x0010, 0x0018, 0x0020, 0x0028) are ever written. Firmware is never touched, and no arbitrary address is exposed.")
                    NoteRow(systemImage: "externaldrive.badge.checkmark",
                            text: "Before every write the current block is saved to Application Support. Every written block is read back and compared.")
                }
                .padding(8)
            } label: {
                Text("Safety").font(.headline)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Packet log").font(.headline)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            if store.log.isEmpty {
                                Text("No packets yet.")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(Array(store.log.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 10, design: .monospaced))
                                    .textSelection(.enabled)
                                    .id(index)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: 170)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .underPageBackgroundColor))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.08)))
                    .onChange(of: store.log.count) { _ in
                        if !store.log.isEmpty {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo(store.log.count - 1, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }

    private var fireBinding: Binding<Int> {
        Binding(
            get: { store.settings.fireIntervalMs },
            set: { store.settings.fireIntervalMs = $0 }
        )
    }

    private var doubleClickBinding: Binding<Int> {
        Binding(
            get: { store.settings.doubleClickMs },
            set: { store.settings.doubleClickMs = $0 }
        )
    }
}

// MARK: - Apply sheet

struct ApplySheet: View {
    let plan: A825Protocol.WritePlan
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Write to mouse?").font(.title3.weight(.semibold))
                Text("Only the blocks below change. A backup is saved first, and every block is read back to verify.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(plan.writes) { write in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(String(format: "0x%04X", write.address))
                                    .font(.system(.body, design: .monospaced).weight(.semibold))
                                Text(write.domains.joined(separator: " · "))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            let old = store.live?.blocks[write.address] ?? []
                            if old.count == write.data.count {
                                ForEach(Array(zip(old, write.data).enumerated()).filter { $0.element.0 != $0.element.1 }, id: \.offset) { byte in
                                    Text(String(format: "byte %02X:  %02X  →  %02X", byte.offset, byte.element.0, byte.element.1))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text("new  " + write.data.map { String(format: "%02X", $0) }.joined(separator: " "))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)

            NoteRow(systemImage: "cable.connector",
                    text: "Do not unplug the mouse while the write is in progress. If a block fails verification, the app restores the bytes it read first.")

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Write \(plan.writes.count) block\(plan.writes.count == 1 ? "" : "s")") {
                    store.commit(plan)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}

// MARK: - Color bridging

extension RGB16 {
    var swiftUIColor: Color {
        Color(.sRGB,
              red: Double(red8) / 255,
              green: Double(green8) / 255,
              blue: Double(blue8) / 255,
              opacity: 1)
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        func channel(_ value: CGFloat) -> UInt8 {
            UInt8(max(0, min(255, Int((value * 255).rounded()))))
        }
        self.init(red8: channel(ns.redComponent),
                  green8: channel(ns.greenComponent),
                  blue8: channel(ns.blueComponent))
    }
}
