import SwiftUI
import AppKit
import PDFKit
import HarpyDockCore

/// Renders the real SwiftUI window into a PNG using AppKit's display cache,
/// so native controls are included. Used only by the hidden --window-shot flag.
struct WindowShotView: View {
    let path: String
    let pane: Pane?
    let showApply: Bool
    @StateObject private var store: Store

    init(path: String, pane: Pane?, showApply: Bool, live: Bool) {
        self.path = path
        self.pane = pane
        self.showApply = showApply
        _store = StateObject(wrappedValue: live ? Store() : Store.preview())
    }

    var body: some View {
        Group {
            if showApply, let plan = Store.samplePlan() {
                ApplySheet(plan: plan)
                    .environmentObject(store)
                    .padding(24)
            } else {
                ContentView(initialPane: pane ?? .dpi)
                    .environmentObject(store)
            }
        }
        .frame(width: showApply ? 620 : 980, height: showApply ? 520 : 720)
        .background(WindowGrabber { window in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                guard let content = window.contentView else { exit(1) }
                content.layoutSubtreeIfNeeded()
                if capture(content, to: path) {
                    print(path)
                    exit(0)
                }
                exit(1)
            }
        })
    }

    private func capture(_ view: NSView, to path: String) -> Bool {
        let pdfData = view.dataWithPDF(inside: view.bounds)
        guard let pdf = PDFDocument(data: pdfData), let page = pdf.page(at: 0) else { return false }
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil
    }
}

struct WindowGrabber: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let window = view.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension Store {
    static func samplePlan() -> A825Protocol.WritePlan? {
        let store = preview()
        var wanted = store.settings
        wanted.stages[0].value = 800
        wanted.pollingHz = 500
        wanted.buttons[0] = .rapidFire
        guard let live = store.live else { return nil }
        return try? A825Protocol.plan(wanted, live: live.blocks)
    }

    static func preview() -> Store {
        let store = Store(preview: true)
        var blocks = Dictionary(uniqueKeysWithValues: A825.ownedBlocks.map {
            ($0, [UInt8](repeating: 0, count: 8))
        })
        for (address, data) in A825Protocol.fragments(for: .defaults) {
            let block = address / 8 * 8
            for (offset, byte) in data.enumerated() {
                blocks[block]![address + offset - block] = byte
            }
        }
        if let live = try? A825Protocol.decode(blocks: blocks, defaults: .defaults) {
            store.live = live
            store.settings = live.settings
        }
        store.connected = true
        store.statusText = "Read 6 stages, 1000 Hz"
        store.log = [
            "Connected USB Gaming Mouse 30FA:1440",
            "SEND 07 18 03 00 08 00 21 05",
            "RECV 07 00 21 05 00 00 00 00",
            "SEND 07 18 05 00 08 00 00 07",
            "RECV 07 00 21 05 00 00 00 00",
            "SEND 07 18 09 00 08 00 00 07",
        ]
        return store
    }
}
