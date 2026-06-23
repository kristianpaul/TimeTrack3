import Cocoa
import UniformTypeIdentifiers

// ── FFI bindings to Rust ──

@_silgen_name("tt_init") func tt_init()
@_silgen_name("tt_start") func tt_start(_ desc: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>
@_silgen_name("tt_stop") func tt_stop() -> UnsafeMutablePointer<CChar>
@_silgen_name("tt_status") func tt_status() -> UnsafeMutablePointer<CChar>
@_silgen_name("tt_history") func tt_history() -> UnsafeMutablePointer<CChar>
@_silgen_name("tt_export_csv") func tt_export_csv(_ date: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>
@_silgen_name("tt_rename") func tt_rename(_ index: Int32, _ name: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>
@_silgen_name("tt_delete") func tt_delete(_ index: Int32) -> UnsafeMutablePointer<CChar>
@_silgen_name("tt_free") func tt_free(_ ptr: UnsafeMutablePointer<CChar>)

func cstrToString(_ ptr: UnsafeMutablePointer<CChar>) -> String {
    let s = String(cString: ptr)
    tt_free(ptr)
    return s
}

// ── Window Controller ──

class WindowController: NSObject, NSWindowDelegate {
    var textField: NSTextField!
    var actionButton: NSButton!
    weak var menuBar: MenuBarController!
    private var windowRef: NSWindow!

    init(menuBar: MenuBarController) {
        self.menuBar = menuBar
        super.init()
    }

    func makeWindow() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 110),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Time Track"
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.delegate = self

        // Close button visible, others hidden
        for button in [win.standardWindowButton(.miniaturizeButton),
                        win.standardWindowButton(.zoomButton)] {
            button?.isHidden = true
        }

        let contentView = win.contentView!

        let tf = NSTextField(frame: NSRect(x: 16, y: 58, width: 308, height: 28))
        tf.placeholderString = "What are you working on?"
        tf.isBezeled = true
        tf.isEditable = true
        tf.isBordered = true
        tf.focusRingType = .none
        tf.usesSingleLineMode = true
        tf.font = NSFont.systemFont(ofSize: 13)
        contentView.addSubview(tf)

        let btn = NSButton(frame: NSRect(x: 16, y: 18, width: 308, height: 28))
        btn.title = "Start"
        btn.target = self
        btn.action = #selector(handleAction)
        btn.bezelStyle = .rounded
        btn.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        btn.keyEquivalent = "\r"
        contentView.addSubview(btn)

        self.textField = tf
        self.actionButton = btn
        self.windowRef = win
    }

    func ensureWindow() {
        if windowRef == nil { makeWindow() }
    }

    func show() {
        ensureWindow()
        windowRef.center()  // Center on screen
        windowRef.makeKeyAndOrderFront(nil)
        syncWindowFromState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.textField?.becomeFirstResponder()
        }
        menuBar.refreshMenu()
    }

    func hide() { windowRef?.orderOut(nil) }
    var isVisible: Bool { windowRef?.isVisible ?? false }

    private func syncWindowFromState() {
        let statusPtr = tt_status()
        let status = cstrToString(statusPtr)

        if status.hasPrefix("tracking") {
            let parts = status.split(separator: "|")
            if parts.count >= 3 {
                actionButton.title = "Stop"
                textField.stringValue = String(parts[1])
                textField.placeholderString = nil
            }
        } else {
            actionButton.title = "Start"
            textField.stringValue = ""
            textField.placeholderString = "What are you working on?"
        }
    }

    @objc func handleAction() {
        let description = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if description.isEmpty {
            textField.becomeFirstResponder()
            return
        }

        let statusPtr = tt_status()
        let status = cstrToString(statusPtr)

        if status.hasPrefix("tracking") {
            let _ = cstrToString(tt_stop())
            syncWindowFromState()
        } else {
            let cDesc = description.cString(using: .utf8)!
            let _ = cstrToString(tt_start(cDesc))
            hide()
        }
        menuBar.refreshMenu()
    }

    func tick() {
        let statusPtr = tt_status()
        let status = cstrToString(statusPtr)

        if status.hasPrefix("tracking") {
            let parts = status.split(separator: "|")
            if parts.count >= 3 {
                menuBar.updateIcon(String(parts[2]))
            }
        } else {
            menuBar.updateIcon(nil)
            if isVisible && actionButton.title != "Start" {
                actionButton.title = "Start"
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

// ── Menu Bar Controller ──

class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var windowCtrl: WindowController!
    private var timer: Timer!

    func setup() {
        tt_init()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "⏱"
            button.action = #selector(toggleWindow)
            button.target = self
        }

        windowCtrl = WindowController(menuBar: self)

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.windowCtrl?.tick()
        }
    }

    @objc func toggleWindow() {
        let statusPtr = tt_status()
        let status = cstrToString(statusPtr)

        if status.hasPrefix("tracking") {
            let _ = cstrToString(tt_stop())
            updateIcon(nil)
            windowCtrl.actionButton.title = "Start"
            refreshMenu()
        } else {
            if windowCtrl.isVisible {
                windowCtrl.hide()
            } else {
                windowCtrl.show()
            }
        }
    }

    func refreshMenu() {
        let menu = NSMenu()

        let statusPtr = tt_status()
        let status = cstrToString(statusPtr)

        if status.hasPrefix("tracking") {
            let parts = status.split(separator: "|")
            let desc = parts.count >= 2 ? String(parts[1]) : ""
            let dur = parts.count >= 3 ? String(parts[2]) : ""

            let stopItem = NSMenuItem(title: "⏹  Stop", action: #selector(stopTracking), keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)

            let infoItem = NSMenuItem(title: "\(desc)  —  \(dur)", action: nil, keyEquivalent: "")
            infoItem.isEnabled = false
            menu.addItem(infoItem)
        } else {
            let startItem = NSMenuItem(title: "▶  Start", action: #selector(startFromMenu), keyEquivalent: "")
            startItem.target = self
            menu.addItem(startItem)
        }

        menu.addItem(NSMenuItem.separator())

        let recentItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        let subMenu = NSMenu()
        loadHistory(into: subMenu)
        recentItem.submenu = subMenu
        menu.addItem(recentItem)

        menu.addItem(NSMenuItem.separator())

        let exportItem = NSMenuItem(title: "Export CSV...", action: #selector(exportCSV), keyEquivalent: "e")
        exportItem.target = self
        menu.addItem(exportItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func loadHistory(into menu: NSMenu) {
        let ptr = tt_history()
        let text = cstrToString(ptr)

        if text.isEmpty {
            let item = NSMenuItem(title: "No records yet", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return
        }

        for (index, line) in text.split(separator: "\n").enumerated() {
            let parts = line.split(separator: "|")
            if parts.count >= 3 {
                let desc = String(parts[0])
                let start = String(parts[1])
                let dur = String(parts[2])

                // Each recent item is a submenu with actions
                let item = NSMenuItem(title: "\(desc)  (\(start) → \(dur))", action: nil, keyEquivalent: "")
                let subMenu = NSMenu()

                let restartItem = NSMenuItem(title: "▶ Restart", action: #selector(restartTask(_:)), keyEquivalent: "")
                restartItem.target = self
                restartItem.representedObject = desc
                subMenu.addItem(restartItem)

                let editItem = NSMenuItem(title: "✏️  Rename...", action: #selector(renameTask(_:)), keyEquivalent: "")
                editItem.target = self
                editItem.representedObject = index
                subMenu.addItem(editItem)

                let deleteItem = NSMenuItem(title: "🗑  Delete", action: #selector(deleteTask(_:)), keyEquivalent: "d")
                deleteItem.target = self
                deleteItem.representedObject = index
                subMenu.addItem(deleteItem)

                item.submenu = subMenu
                menu.addItem(item)
            }
        }
    }

    func updateIcon(_ duration: String?) {
        guard let button = statusItem.button else { return }
        button.title = duration.map { "⏱ \($0)" } ?? "⏱"
    }

    @objc func startFromMenu() {
        windowCtrl.show()
    }

    @objc func stopTracking() {
        let _ = cstrToString(tt_stop())
        updateIcon(nil)
        refreshMenu()
        if windowCtrl.isVisible { windowCtrl.actionButton.title = "Start" }
    }

    @objc func restartTask(_ sender: Any) {
        if let item = sender as? NSMenuItem,
           let desc = item.representedObject as? String {
            let cDesc = desc.cString(using: .utf8)!
            let _ = cstrToString(tt_start(cDesc))
            refreshMenu()
        }
    }

    @objc func renameTask(_ sender: Any) {
        if let item = sender as? NSMenuItem,
           let value = item.representedObject as? Int {
            let index = value

            // Get current description from history
            let ptr = tt_history()
            let text = cstrToString(ptr)
            let lines = text.split(separator: "\n").map { String($0) }
            guard index < lines.count else { return }

            let parts = lines[index].split(separator: "|")
            guard parts.count >= 1 else { return }
            let currentDesc = String(parts[0])

            // Show rename dialog
            let alert = NSAlert()
            alert.messageText = "Rename task"
            alert.informativeText = "Enter new name:"
            alert.alertStyle = .informational

            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
            field.stringValue = currentDesc
            field.isBezeled = true
            field.isEditable = true
            field.isBordered = true
            alert.accessoryView = field

            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertFirstButtonReturn {
                let newDesc = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !newDesc.isEmpty {
                    let _ = cstrToString(tt_rename(Int32(index), newDesc.cString(using: .utf8)!))
                    refreshMenu()
                }
            }
        }
    }

    @objc func deleteTask(_ sender: Any) {
        if let item = sender as? NSMenuItem,
           let index = item.representedObject as? Int {
            let alert = NSAlert()
            alert.messageText = "Delete task"
            alert.informativeText = "This cannot be undone."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                let _ = cstrToString(tt_delete(Int32(index)))
                refreshMenu()
            }
        }
    }

    @objc func exportCSV() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType(filenameExtension: "csv")!]
        savePanel.canCreateDirectories = true

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())
        savePanel.nameFieldStringValue = "timetrack_\(dateStr).csv"
        savePanel.directoryURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)

        if savePanel.runModal() == .OK, let url = savePanel.url {
            let ptr = tt_export_csv(dateStr.cString(using: .utf8)!)
            let csv = cstrToString(ptr)

            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// ── App Entry ──

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()
        menuBar.setup()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()