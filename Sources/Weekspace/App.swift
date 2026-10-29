import SwiftUI
import AppKit

extension Notification.Name {
    static let newPlanTask = Notification.Name("Weekspace.newTask")
    static let openPlanSettings = Notification.Name("Weekspace.settings")
}

@MainActor final class DesktopPanel: NSPanel { override var canBecomeKey:Bool {true};override var canBecomeMain:Bool {false} }

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var shared: AppDelegate?
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var desktopWindow: NSPanel?
    var store: PlanStore!
    var timer: Timer?
    var expandedFrame: NSRect?
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        store = PlanStore(demo: CommandLine.arguments.contains("--demo"))
        NSApp.setActivationPolicy(.regular)
        let view = MainView(store: store)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1460, height: 900),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "周间 · Weekspace"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .white
        window.minSize = NSSize(width: 1100, height: 690)
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.delegate = self
        let frameName = store.demo ? "WeekspaceDemo" : "WeekspaceMain"
        if !window.setFrameUsingName(frameName) { window.center() }
        window.setFrameAutosaveName(frameName)
        buildMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "周间")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示周间", action: #selector(show), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "显示 / 隐藏桌面小面板", action: #selector(toggleDesktop), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "添加任务", action: #selector(newTask), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出周间", action: #selector(quit), keyEquivalent: ""))
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.rollover(); if let store = self?.store {Task {await store.refreshQuote()}} }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(woke), name: NSNotification.Name.NSSystemClockDidChange, object: nil)
        show()
    }
    func buildMenu() {
        let main = NSMenu()
        let root = NSMenuItem(); let app = NSMenu()
        app.addItem(NSMenuItem(title: "关于周间", action: #selector(about), keyEquivalent: ""))
        app.addItem(NSMenuItem(title: "设置…", action: #selector(settings), keyEquivalent: ","))
        app.addItem(.separator()); app.addItem(NSMenuItem(title: "隐藏周间", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        app.addItem(NSMenuItem(title: "退出周间", action: #selector(quit), keyEquivalent: "q"))
        for item in app.items where item.title != "隐藏周间" { item.target = self }
        root.submenu = app; main.addItem(root)
        let file = NSMenuItem(); file.title = "文件"; let fileMenu = NSMenu(title: "文件")
        let add = NSMenuItem(title: "详细新建任务", action: #selector(newTask), keyEquivalent: "n"); add.target = self; fileMenu.addItem(add)
        file.submenu = fileMenu; main.addItem(file)
        let edit = NSMenuItem(); edit.title = "编辑"; let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu; main.addItem(edit); NSApp.mainMenu = main
    }
    @objc func toggleDesktop() {
        if let panel = desktopWindow {
            if panel.isVisible {panel.orderOut(nil);show()} else {panel.orderFrontRegardless();window.orderOut(nil)}
            return
        }
        let panel = DesktopPanel(contentRect:NSRect(x:0,y:0,width:380,height:620), styleMask:[.borderless,.resizable],backing:.buffered,defer:false)
        panel.title = "周间 · 桌面视图"
        panel.isReleasedWhenClosed = false;panel.isOpaque = false;panel.backgroundColor = .clear;panel.hasShadow = true
        panel.isMovableByWindowBackground = true;panel.minSize = NSSize(width:350,height:520)
        panel.level = NSWindow.Level(rawValue:Int(CGWindowLevelForKey(.desktopIconWindow))+1)
        panel.collectionBehavior = [.canJoinAllSpaces,.stationary,.fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView:DesktopPlannerView(store:store).clipShape(RoundedRectangle(cornerRadius:18)))
        if !panel.setFrameUsingName("WeekspaceDesktop") {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1440,height:900)
            panel.setFrameOrigin(NSPoint(x:screen.maxX-410,y:screen.maxY-650))
        }
        panel.setFrameAutosaveName("WeekspaceDesktop");desktopWindow = panel;panel.orderFrontRegardless();window.orderOut(nil)
    }
    func setCompact(_ compact: Bool) {
        if compact {
            expandedFrame = window.frame
            window.minSize = NSSize(width: 540, height: 690)
            var frame = window.frame; frame.size = NSSize(width: 570, height: 760)
            window.setFrame(frame, display: true, animate: true)
        } else {
            window.minSize = NSSize(width: 1100, height: 690)
            if let frame = expandedFrame { window.setFrame(frame, display: true, animate: true) }
        }
    }
    func setPinned(_ pinned: Bool) { window.level = pinned ? .floating : .normal }
    @objc func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); store.rollover() }
    @objc func newTask() { show(); NotificationCenter.default.post(name: .newPlanTask, object: nil) }
    @objc func settings() { show(); NotificationCenter.default.post(name: .openPlanSettings, object: nil) }
    @objc func quit() { store.save(); NSApp.terminate(nil) }
    @objc func woke() { store.rollover(); Task {await store.refreshQuote()} }
    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "周间 · Weekspace", .applicationVersion: "0.2.1", .credits: NSAttributedString(string: "给重要的事，留点时间。\n本地周计划 · 固定课表 · 每日归档")])
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); return false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    func applicationWillTerminate(_ notification: Notification) { store?.save() }
}

@main struct Launcher {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-test") {
            do { try runModelTests(); try runV2Tests() } catch { print("FAIL \(error.localizedDescription)"); exit(1) }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
