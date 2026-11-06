import AppKit
import SwiftUI
import Combine
import bloxKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {

    private enum Decision: Sendable {
        case pass, drop
    }

    private var statusItem: NSStatusItem?
    private var panel: CanvasPanel?
    private var settings: AppSettings?
    private var settingsWindow: SettingsWindowController?
    private var iconWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    private var pressActive = false
    private var pressAnchor: NSRect = .zero
    private var pressStartY: CGFloat = 0
    private var lastDragY: CGFloat = 0
    private var downOpen = false
    private var dragDidOpen = false
    private var dragOpenedPast = false
    private var suppressClick = false
    private var pollTask: Task<Void, Never>?
    private var salvageTask: Task<Void, Never>?
    private var stateTimer: Timer?
    private var lastIconRect: NSRect = .zero
    private var lastPanelVisible = false
    private var lastOccluded = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let store = BlocStore()
        let settings = AppSettings()
        self.settings = settings
        settingsWindow = SettingsWindowController(settings: settings)
        let sizeURL = Storage.windowSizeURL(beside: Storage.defaultURL())
        let savedSize = Storage.loadWindowSize(from: sizeURL)
            ?? CGSize(width: BlockLayout.panelWidth, height: BlockLayout.panelHeight)
        let panel = CanvasPanel(store: store, settings: settings, initialSize: savedSize, sizeURL: sizeURL)
        panel.releaseAction = { [weak self] in self?.onPanelReleased() }
        self.panel = panel

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let logo = NSImage(contentsOf: Bundle.module.url(forResource: "blox-logo", withExtension: "png") ?? URL(fileURLWithPath: "/nonexistent"))
            ?? NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "blox")
        logo?.size = NSSize(width: 18, height: 18)
        logo?.isTemplate = true
        item.button?.image = logo
        Trace.log("logo=\(logo.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "nil") template=\(logo?.isTemplate ?? false)")
        item.button?.target = self
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.action = #selector(statusAction)
        statusItem = item
        iconWindow = item.button?.window
        Trace.log("icon rect=\(itemFrame())")

        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let decision: Decision = MainActor.assumeIsolated {
                self?.decide(event) ?? .pass
            }
            if decision == .drop {
                return nil
            }
            return event
        }

        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closeIfOutsideClick()
            }
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel?.isVisible == true, !self.pressActive else { return }
                Trace.log("app resigned active")
                self.panel?.closeNow()
            }
        }

        store.$blocks
            .map { $0.contains(where: \.isAlertingReminder) }
            .removeDuplicates()
            .sink { [weak self] alerting in
                MainActor.assumeIsolated {
                    self?.statusItem?.button?.contentTintColor = alerting ? .systemRed : nil
                }
            }
            .store(in: &cancellables)

        stateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.logStateChanges()
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self else { return }
            Trace.log("icon rect later=\(self.itemFrame())")
        }
        Trace.log("launched")
    }

    private func logStateChanges() {
        let rect = itemFrame()
        let visible = panel?.isVisible ?? false
        let occluded = !(panel?.occlusionState.contains(.visible) ?? false)
        guard rect != lastIconRect || visible != lastPanelVisible || occluded != lastOccluded else { return }
        lastIconRect = rect
        lastPanelVisible = visible
        lastOccluded = occluded
        Trace.log("state icon=\(rect) panelVisible=\(visible) occluded=\(occluded) level=\(panel?.level.rawValue ?? 0)")
    }

    private func decide(_ event: NSEvent) -> Decision {
        switch event.type {
        case .leftMouseDown:
            Trace.log("mouseDown win=\(event.window.map { $0 === iconWindow ? "icon" : String(describing: type(of: $0)) } ?? "nil") loc=\(Int(event.locationInWindow.x)),\(Int(event.locationInWindow.y))")
            guard isIconPress(event) else { return .pass }
            guard !event.modifierFlags.contains(.command) else { return .pass }
            beginPressSession(pointerY: screenY(of: event))
            statusItem?.button?.highlight(true)
            return .drop
        case .leftMouseDragged:
            guard pressActive else { return .pass }
            applyDrag(pointerY: screenY(of: event))
            return .drop
        case .leftMouseUp:
            guard pressActive else { return .pass }
            finishPress()
            return .drop
        default:
            return .pass
        }
    }

    private func isIconPress(_ event: NSEvent) -> Bool {
        if event.window === iconWindow { return true }
        guard event.window == nil else { return false }
        let frame = itemFrame()
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: event.locationInWindow.x, y: $0.frame.maxY - 1)) }) ?? NSScreen.main else {
            return false
        }
        let topRow = NSRect(x: frame.minX - 6, y: screen.frame.maxY - 40, width: frame.width + 12, height: 40)
        return topRow.contains(event.locationInWindow)
    }

    private func screenY(of event: NSEvent) -> CGFloat {
        if let window = event.window {
            return window.frame.origin.y + event.locationInWindow.y
        }
        return event.locationInWindow.y
    }

    private func beginPressSession(pointerY: CGFloat) {
        endPressSession()
        pressActive = true
        pressAnchor = itemFrame()
        panel?.prepareAnchor(pressAnchor)
        pressStartY = pointerY
        lastDragY = pointerY
        downOpen = panel?.isVisible ?? false
        dragDidOpen = false
        dragOpenedPast = false
        suppressClick = false
        Trace.log("begin press downOpen=\(downOpen) start=\(Int(pressStartY))")
        if !downOpen {
            startUnrollPolling()
        }
        salvageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, self.pressActive else { return }
            Trace.log("salvage end drag=\(self.dragDidOpen) past=\(self.dragOpenedPast)")
            self.finishPress()
        }
    }

    private func applyDrag(pointerY: CGFloat) {
        let dy = pressStartY - pointerY
        guard dy > 8 else { return }
        if !dragDidOpen {
            Trace.log("drag start dy=\(Int(dy)) downOpen=\(downOpen)")
        }
        dragDidOpen = true
        dragOpenedPast = !downOpen ? dy >= BlockLayout.unrollThreshold : (panel?.movedDown() ?? 0) >= BlockLayout.unrollThreshold
        if !downOpen {
            panel?.showUnroll(height: min(BlockLayout.panelHeight, max(48, dy * 1.3)))
        } else {
            let delta = lastDragY - pointerY
            if delta > 0 {
                panel?.moveDown(by: min(delta, 40))
            }
        }
        lastDragY = pointerY
    }

    private func finishPress() {
        endPressSession()
        if dragDidOpen && !downOpen {
            suppressClick = true
            panel?.settle(open: dragOpenedPast)
        } else if dragDidOpen && downOpen {
            suppressClick = true
            if (panel?.movedDown() ?? 0) >= BlockLayout.unrollThreshold {
                Trace.log("drag open state dismiss")
                panel?.closeNow()
            } else {
                panel?.settle(open: true)
            }
        } else {
            toggleByState()
        }
    }

    private func endPressSession() {
        pressActive = false
        pollTask?.cancel()
        pollTask = nil
        salvageTask?.cancel()
        salvageTask = nil
        statusItem?.button?.highlight(false)
    }

    private func startUnrollPolling() {
        pollTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            var ticks = 0
            while let self, !Task.isCancelled, self.pressActive, !self.downOpen {
                ticks += 1
                if ticks > 240 { break }
                self.applyDrag(pointerY: NSEvent.mouseLocation.y)
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func closeIfOutsideClick() {
        guard let panel, panel.isVisible, !pressActive else { return }
        let mouse = NSEvent.mouseLocation
        if !panel.frame.contains(mouse) {
            Trace.log("outside click close at \(Int(mouse.x)),\(Int(mouse.y))")
            panel.closeNow()
        }
    }

    private func onPanelReleased() {
        guard pressActive, dragDidOpen else { return }
        Trace.log("panel mouseUp during drag")
        finishPress()
    }

    @objc private func statusAction() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showStatusMenu()
            return
        }
        Trace.log("statusAction visible=\(panel?.isVisible ?? false) suppress=\(suppressClick) press=\(pressActive)")
        if suppressClick {
            suppressClick = false
            return
        }
        if pressActive {
            finishPress()
            return
        }
        toggleByState()
    }

    private func showStatusMenu() {
        guard let button = statusItem?.button else { return }
        let strings = settings?.strings ?? Strings(language: .english)
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: strings.settingsMenu, action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: strings.quitApp, action: #selector(quitApplication), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        Trace.log("status menu")
        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openSettings() {
        panel?.closeNow()
        settingsWindow?.show()
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func toggleByState() {
        if panel?.isVisible == true {
            panel?.closeNow()
        } else {
            panel?.openFull(anchor: itemFrame())
        }
    }

    private func itemFrame() -> NSRect {
        statusItem?.button?.window?.frame ?? NSRect(x: 0, y: 0, width: 24, height: 24)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { true }

}

final class CanvasPanel: NSPanel {
    var releaseAction: (() -> Void)?
    private var anchorX: CGFloat = 0
    private var anchorTopPoint = NSPoint.zero
    private var resizeStartFrame: NSRect?
    private let sizeURL: URL
    private var panelSize: CGSize

    init(store: BlocStore, settings: AppSettings, initialSize: CGSize, sizeURL: URL) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let clamped = CGSize(
            width: min(max(BlockLayout.minWindowWidth, initialSize.width), screen.width - 16),
            height: min(max(BlockLayout.minWindowHeight, initialSize.height), screen.height - 24)
        )
        self.sizeURL = sizeURL
        self.panelSize = clamped
        super.init(
            contentRect: NSRect(origin: .zero, size: clamped),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = NSView(frame: NSRect(origin: .zero, size: clamped))
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        container.layer?.cornerRadius = 12
        container.autoresizingMask = [.width, .height]
        let root = CanvasScreen(
            store: store,
            onResize: { [weak self] translation in self?.interactiveResize(translation: translation) },
            onResizeEnded: { [weak self] in self?.endInteractiveResize() }
        )
        .environmentObject(settings)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        contentView = container
    }

    override var canBecomeKey: Bool { true }

    var settledSize: CGSize { panelSize }

    func prepareAnchor(_ iconFrame: NSRect) {
        updateAnchor(iconFrame)
    }

    func moveDown(by delta: CGFloat) {
        let floorY = fullFrame().origin.y - 200
        let targetY = max(floorY, frame.origin.y - delta)
        if targetY < frame.origin.y {
            setFrameOrigin(NSPoint(x: frame.origin.x, y: targetY))
        }
    }

    func movedDown() -> CGFloat {
        max(0, fullFrame().origin.y - frame.origin.y)
    }

    func openFull(anchor: NSRect) {
        updateAnchor(anchor)
        setFrame(fullFrame(), display: true)
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        clearKeyFocus()
        Trace.log("openFull frame=\(fullFrame())")
    }

    func showUnroll(height: CGFloat) {
        Trace.log("showUnroll h=\(Int(height))")
        if !isVisible {
            alphaValue = 1
            orderFrontRegardless()
        }
        setFrame(
            NSRect(origin: NSPoint(x: anchorX, y: anchorTopPoint.y - height), size: CGSize(width: panelSize.width, height: height)),
            display: true
        )
    }

    func settle(open: Bool) {
        if open {
            setFrame(fullFrame(), display: true)
            makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            clearKeyFocus()
            Trace.log("settle open")
        } else {
            orderOut(nil)
            Trace.log("settle retract")
        }
    }

    func closeNow() {
        Trace.log("closeNow")
        orderOut(nil)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        releaseAction?()
    }

    override func cancelOperation(_ sender: Any?) {
        closeNow()
    }

    private func clearKeyFocus() {
        makeFirstResponder(nil)
    }

    private func updateAnchor(_ iconFrame: NSRect) {
        let screen = NSScreen.screens.first { $0.frame.contains(iconFrame.origin) } ?? NSScreen.main
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        anchorX = max(
            screenFrame.minX + 8,
            min(screenFrame.midX - panelSize.width / 2, screenFrame.maxX - panelSize.width - 8)
        )
        anchorTopPoint = NSPoint(x: anchorX, y: iconFrame.minY)
    }

    private func fullFrame() -> NSRect {
        NSRect(origin: NSPoint(x: anchorX, y: anchorTopPoint.y - panelSize.height), size: panelSize)
    }

    private func interactiveResize(translation: CGSize) {
        if resizeStartFrame == nil { resizeStartFrame = frame }
        guard let start = resizeStartFrame else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(start) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(
            max(BlockLayout.minWindowWidth, start.width + translation.width),
            max(BlockLayout.minWindowWidth, bounds.width)
        )
        let height = min(
            max(BlockLayout.minWindowHeight, start.height + translation.height),
            max(BlockLayout.minWindowHeight, start.maxY - bounds.minY)
        )
        let resized = NSRect(x: bounds.midX - width / 2, y: start.maxY - height, width: width, height: height)
        panelSize = resized.size
        setFrame(resized, display: true)
    }

    private func endInteractiveResize() {
        guard resizeStartFrame != nil else { return }
        resizeStartFrame = nil
        Storage.writeWindowSize(panelSize, to: sizeURL)
        Trace.log("resize panel=\(Int(panelSize.width))x\(Int(panelSize.height))")
    }
}
