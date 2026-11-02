import AppKit
import CoreGraphics
import Carbon

final class InputMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var onKey: ((Int, Bool, Bool, Bool) -> Void)?
    var onModifier: ((Int, UInt64) -> Void)?
    var onModifierReset: ((UInt64) -> Void)?
    var onPointer: ((EffectiveInputKind, Double, Double, Bool) -> Void)?
    var active: Bool { tap != nil && CGEvent.tapIsEnabled(tap: tap!) }
    private(set) var keyboardCallbacks = 0

    func start() -> Bool {
        if active { return true }
        stop()
        guard CGPreflightListenEventAccess() else { return false }
        onModifierReset?(CGEventSource.flagsState(.combinedSessionState).rawValue)
        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<InputMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                monitor.onModifierReset?(CGEventSource.flagsState(.combinedSessionState).rawValue)
                if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            } else if type == .flagsChanged {
                monitor.onModifier?(Int(event.getIntegerValueField(.keyboardEventKeycode)), event.flags.rawValue)
            } else if type == .keyDown {
                monitor.keyboardCallbacks &+= 1
                // No Unicode strings, key names, target applications or raw events are retained.
                monitor.onKey?(
                    Int(event.getIntegerValueField(.keyboardEventKeycode)),
                    event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                    event.flags.contains(.maskCommand),
                    event.flags.contains(.maskControl)
                )
            } else if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type) {
                monitor.onPointer?(.click, 0, 0, false)
            } else if [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(type) {
                monitor.onPointer?(.movement, Double(event.getIntegerValueField(.mouseEventDeltaX)), Double(event.getIntegerValueField(.mouseEventDeltaY)), false)
            } else if type == .scrollWheel {
                let x = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), y = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
                let dx = x != 0 ? Double(x) : Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)) * 10
                let dy = y != 0 ? Double(y) : Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)) * 10
                monitor.onPointer?(.scroll, dx, dy, event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { stop(); return false }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap = tap { CFMachPortInvalidate(tap) }
        source = nil; tap = nil
    }
    deinit { stop() }
}

final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class SizeControlView: NSView {
    let slider: NSSlider
    private let percentLabel = NSTextField(labelWithString: "100%")
    init(value: CGFloat, target: AnyObject, action: Selector) {
        slider = NSSlider(value: Double(value * 100), minValue: 50, maxValue: 180, target: target, action: action)
        super.init(frame: NSRect(x: 0, y: 0, width: 266, height: 75))
        let label = NSTextField(labelWithString: "相对推荐大小")
        label.frame = NSRect(x: 16, y: 46, width: 160, height: 18)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        addSubview(label)
        percentLabel.frame = NSRect(x: 191, y: 45, width: 59, height: 20)
        percentLabel.alignment = .right
        percentLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        addSubview(percentLabel)
        slider.frame = NSRect(x: 14, y: 12, width: 238, height: 24)
        slider.isContinuous = true
        slider.setAccessibilityLabel("桌宠大小，相对当前屏幕推荐大小，百分比")
        addSubview(slider)
        update(value)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func update(_ value: CGFloat) {
        slider.doubleValue = Double(value * 100)
        percentLabel.stringValue = "\(Int((value * 100).rounded()))%"
    }
}

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let defaults: UserDefaults
    let model: CounterModel
    let wardrobe: WardrobeModel
    let monitor = InputMonitor()
    let pointerFilter = PointerInputFilter()
    let modifierFilter = ModifierPressFilter()
    var countingRule: InputCountingRule { InputCountingRule(rawValue: defaults.string(forKey: "inputCountingRule") ?? "") ?? .keyAndMouseButtons }
    let rest: RestReminderModel
    let reminderBook: ReminderBookModel
    let feedback = FeedbackModel()
    var panel: CompanionPanel!
    var pet: PetView!
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var timer: Timer?
    var testWindow: NSWindow?
    var testView: TryTypingView?
    var lastSaved = Date.distantPast
    var dirty = false
    var tickNumber = 0
    var desktopVisible = true
    var permanentlyClickThrough = false
    var relativeSize: CGFloat = 1
    var sizeControl: SizeControlView?
    var isApplyingLayout = false
    var layoutWorkItem: DispatchWorkItem?
    var gripScreen: NSScreen?
    var resizeFeedbackWork: DispatchWorkItem?
    var visibilityWork: DispatchWorkItem?
    var isQuitting = false
    var wardrobeWindow: WardrobeWindowController?
    var pendingOutfitFeedback: PetReaction?
    var localInputMonitor: Any?
    var sessionInactive = false
    var machineSleeping = false
    var pendingRestReminder = false
    var reminderWindow: ReminderWindowController?
    var reminderPresenter: ScheduledReminderPresenter?
    var activeScheduledReminder: UUID?
    var reminderBadge = false
    var monitoringSuspended: Bool { model.isPaused || sessionInactive || machineSleeping }

    override convenience init() { self.init(settings: .standard) }

    init(settings: UserDefaults) {
        defaults = settings
        let loaded: CounterModel
        if let data = settings.data(forKey: "counter"), let saved = try? JSONDecoder().decode(SavedCounter.self, from: data) { loaded = CounterModel(saved: saved) }
        else { loaded = CounterModel() }
        model = loaded
        let savedWardrobe = settings.data(forKey: "wardrobe").flatMap { try? JSONDecoder().decode(SavedWardrobe.self, from: $0) }
        wardrobe = WardrobeModel(total: loaded.lifetimeCount, saved: savedWardrobe)
        let savedRest = settings.data(forKey: "restSession").flatMap { try? JSONDecoder().decode(SavedRestSession.self, from: $0) }
        rest = RestReminderModel(saved: savedRest)
        let savedReminders = settings.data(forKey: "scheduledReminders").flatMap { try? JSONDecoder().decode(SavedReminderBook.self, from: $0) }
        reminderBook = ReminderBookModel(saved: savedReminders)
        super.init()
        relativeSize = ScreenSizing.preference(CGFloat(defaults.double(forKey: "relativeSize")))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .aqua)
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出敲敲", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self; appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
        panel = CompanionPanel(contentRect: NSRect(origin: .zero, size: PetView.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "敲敲 · 桌面小搭子"
        panel.acceptsMouseMovedEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        pet = PetView(model: model, feedback: feedback, wardrobe: wardrobe)
        // Decode the small sprite set and prepare the selected costume before
        // input monitoring starts. No first-key disk reads or path rasterization.
        CelAssets.preload()
        if let outfit = wardrobe.selected { OutfitLayers.preload(outfit) }
        panel.contentView = pet
        placePanel()
        panel.delegate = self
        pet.onMenu = { [weak self] in self?.showMenu() }
        pet.onConnectInput = { [weak self] in self?.explainInputConnection() }
        pet.onMove = { [weak self] in self?.savePosition() }
        pet.onResize = { [weak self] scale, finished in self?.resizeFromGrip(scale: scale, finished: finished) }
        monitor.onKey = { [weak self] code, repeated, command, control in
            self?.accept(code: code, repeated: repeated, command: command, control: control)
        }
        monitor.onModifier = { [weak self] code, flags in self?.acceptModifier(code: code, flags: flags) }
        monitor.onModifierReset = { [weak self] flags in self?.modifierFilter.reset(flags: flags) }
        monitor.onPointer = { [weak self] kind, dx, dy, momentum in self?.acceptPointer(kind, dx: dx, dy: dy, momentum: momentum) }
        installLocalInputMonitor()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "敲敲桌宠")
        menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        panel.orderFrontRegardless()
        _ = monitor.start()
        if !monitor.active { feedback.react(.blocked) }
        refresh()
        feedback.observe(mood: model.mood(), at: Date())
        timer = Timer(timeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in self?.pulse() }
        timer?.tolerance = 0.003
        RunLoop.main.add(timer!, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sessionResigned), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sessionBecameActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        processScheduledReminders(at: Date())
        writeMonitorReport()
        // A stopped counter must explain the required connection on first use.
        // The system consent is requested only after the user chooses 去开启.
        let connectionHelpKey = "inputConnectionExplained.\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")"
        if !monitor.active, !defaults.bool(forKey: connectionHelpKey), !CommandLine.arguments.contains("--try-typing") {
            defaults.set(true, forKey: connectionHelpKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.explainInputConnection() }
        }
        if CommandLine.arguments.contains("--try-typing") { showTestWindow() }
    }

    func accept(code: Int, repeated: Bool = false, command: Bool = false, control: Bool = false) {
        // Secure Event Input is deliberately respected, including in the local trial window.
        guard !IsSecureEventInputEnabled() else { return }
        guard !monitoringSuspended, CounterModel.isEffectiveKey(code) else { return }
        let now = Date(), previous = model.mood()
        let counted = model.recordKeyboardInput(keyCode: code, isRepeat: repeated, at: now)
        rest.activity(at: now); dirty = true
        if CounterModel.isTypingKey(code) && !command && !control { feedback.key(code: code, repeated: repeated, counted: counted, previousMood: previous, at: now) }
        else { feedback.activity(kind: .keyboard, counted: counted, previousMood: previous, at: now) }
        pet.now = now; pet.needsDisplay = true
        if counted { didCountInput(at: now) }
    }

    func acceptModifier(code: Int, flags: UInt64) {
        guard !monitoringSuspended, !IsSecureEventInputEnabled() else { return }
        guard modifierFilter.pressed(code: code, flags: flags) else { return }
        accept(code: code)
    }

    func acceptPointer(_ kind: EffectiveInputKind, dx: Double, dy: Double, momentum: Bool) {
        guard !monitoringSuspended else { return }
        let now = Date(), decision = pointerFilter.process(kind, dx: dx, dy: dy, momentum: momentum, at: now)
        guard decision.active || decision.counted, !IsSecureEventInputEnabled() else { return }
        let previous = model.mood(at: now)
        model.noteActivity(at: now); rest.activity(at: now); dirty = true
        let counted = decision.counted && countingRule.includesPointer(kind) && model.recordEffectiveInput(at: now)
        feedback.activity(kind: kind, counted: counted, previousMood: previous, at: now)
        pet.now = now; pet.needsDisplay = true
        if counted { didCountInput(at: now) }
    }

    func didCountInput(at now: Date) {
        let change = wardrobe.synchronize(total: model.lifetimeCount, at: now)
        if change.newUnlocks > 0 { pendingOutfitFeedback = wardrobe.automatic ? .outfitUnlocked : .wardrobeStored }
        else if change.equippedChanged { pendingOutfitFeedback = .dressed }
        if change.newUnlocks > 0 || change.equippedChanged {
            // Keep persistence and wardrobe-window work outside the input callback.
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let outfit = self.wardrobe.selected { OutfitLayers.preload(outfit) }
                self.save(); self.wardrobeWindow?.refresh()
            }
        }
        testView?.count = model.todayCount
        // Accessibility/status text is refreshed by the one-second heartbeat;
        // the visible counter is drawn directly from the updated model.
    }

    func installLocalInputMonitor() {
        modifierFilter.reset(flags: CGEventSource.flagsState(.combinedSessionState).rawValue)
        let mask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]
        localInputMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self = self, !self.monitor.active, !self.monitoringSuspended else { return event }
            switch event.type {
            case .keyDown: self.accept(code: Int(event.keyCode), repeated: event.isARepeat, command: event.modifierFlags.contains(.command), control: event.modifierFlags.contains(.control))
            case .flagsChanged: self.acceptModifier(code: Int(event.keyCode), flags: event.cgEvent?.flags.rawValue ?? UInt64(event.modifierFlags.rawValue))
            case .leftMouseDown, .rightMouseDown, .otherMouseDown: self.acceptPointer(.click, dx: 0, dy: 0, momentum: false)
            case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: self.acceptPointer(.movement, dx: event.deltaX, dy: event.deltaY, momentum: false)
            case .scrollWheel: self.acceptPointer(.scroll, dx: event.scrollingDeltaX * (event.hasPreciseScrollingDeltas ? 1 : 10), dy: event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 10), momentum: !event.momentumPhase.isEmpty)
            default: break
            }
            return event
        }
    }

    func pulse() {
        tickNumber += 1
        let now = Date()
        feedback.observe(mood: model.mood(at: now), at: now)
        if let pending = pendingOutfitFeedback, feedback.interaction == .none,
           (feedback.visibleSpeech(at: now)?.reaction.priority ?? 0) <= pending.priority {
            feedback.react(pending, at: now); pendingOutfitFeedback = nil
        }
        if pendingRestReminder, activeScheduledReminder == nil, !monitoringSuspended, feedback.interaction == .none,
           (feedback.visibleSpeech(at: now)?.reaction.priority ?? 0) <= PetReaction.rest.priority,
           rest.reminderDue(at: now) {
            feedback.react(.rest, at: now); rest.markReminded(at: now)
            pendingRestReminder = false; dirty = true; refresh()
        }
        if tickNumber % 24 == 0 {
            processScheduledReminders(at: now)
            let oldWork = rest.activeSeconds
            pendingRestReminder = rest.reminderDue(at: now)
            if rest.activeSeconds != oldWork { dirty = true }
            let oldDay = model.day
            model.tick(at: now)
            if oldDay != model.day { dirty = true; feedback.react(.newDay, at: now) }
            if !monitor.active && !monitoringSuspended && CGPreflightListenEventAccess(), monitor.start() { feedback.react(.connected, at: now) }
            if monitor.active && !CGPreflightListenEventAccess() { monitor.stop(); feedback.react(.blocked, at: now) }
            refresh()
            if wardrobeWindow?.window?.isVisible == true { wardrobeWindow?.refresh() }
            if dirty && now.timeIntervalSince(lastSaved) >= 5 { save() }
            writeMonitorReport()
        }
        guard panel.isVisible else { return }
        // A small, tightly bounded panel avoids the cursor-entry race caused by toggling
        // ignoresMouseEvents on a timer. Full click-through is an explicit menu option.
        panel.ignoresMouseEvents = permanentlyClickThrough
        if permanentlyClickThrough { feedback.hovered = false }
        else { pet.updatePointer(NSEvent.mouseLocation) }
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let active = feedback.isAnimating(at: now) || feedback.hovered || now.timeIntervalSince(wardrobe.changedAt) < 1.8
        // The timer already sets the 24 fps cadence. A second elapsed-time gate
        // dropped whole frames whenever a tick arrived a fraction early.
        if reducedMotion ? tickNumber % 3 == 0 : (active || tickNumber % 2 == 0) {
            pet.now = now
            pet.needsDisplay = true
        }
    }

    func refresh() {
        let oldInputHelp = pet.needsInputHelp
        pet.now = Date()
        pet.globalAvailable = monitor.active && !model.isPaused
        pet.secureInput = IsSecureEventInputEnabled()
        if oldInputHelp != pet.needsInputHelp { panel.invalidateCursorRects(for: pet) }
        let speech = feedback.visibleSpeech(at: pet.now)?.text ?? ""
        pet.setAccessibilityValue("\(pet.counterText)，\(feedback.pose(mood: model.mood(), at: pet.now)?.rawValue ?? "awake")，\(speech)，\(monitor.active ? "全局监听已连接" : "仅本应用内计数")，大小 \(Int((relativeSize * 100).rounded()))%，\(Int(panel.frame.width.rounded())) × \(Int(panel.frame.height.rounded()))，装扮 \(wardrobe.selected?.name ?? "原样")，已解锁 \(wardrobe.unlockedCount)/100，长期累计 \(model.lifetimeCount)，活跃工作约 \(Int(rest.activeSeconds / 60)) 分钟")
        pet.needsDisplay = true
    }

    /// Explicit developer diagnostics only; contains counts and state, no text
    /// entered by the user, application names, trajectories or reminder titles.
    func writeMonitorReport() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--monitor-report"), args.count > index + 1 else { return }
        let report: [String: Any] = [
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "permissionGranted": CGPreflightListenEventAccess(), "tapActive": monitor.active,
            "secureInput": IsSecureEventInputEnabled(), "suspended": monitoringSuspended,
            "keyboardCallbacks": monitor.keyboardCallbacks, "countingRule": countingRule.rawValue, "todayCount": model.todayCount,
            "lifetimeCount": model.lifetimeCount, "timestamp": Date().timeIntervalSince1970
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: args[index + 1]), options: .atomic)
        }
    }

    func placePanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let v = screen.visibleFrame
        let fallback = NSPoint(x: v.maxX - PetView.size.width - 24, y: v.minY + 24)
        if let position = defaults.string(forKey: "position") { panel.setFrameOrigin(NSPointFromString(position)) }
        else { panel.setFrameOrigin(fallback) }
        applySizing()
    }

    func currentScreen(preferPointer: Bool = false) -> NSScreen? {
        let screens = NSScreen.screens
        guard let index = ScreenSizing.screenIndex(for: panel.frame, screens: screens.map(\.frame), pointer: preferPointer ? NSEvent.mouseLocation : nil) else { return nil }
        return screens[index]
    }

    func applySizing(on target: NSScreen? = nil, anchor: ScreenSizing.Anchor = .bottomRight) {
        guard !isApplyingLayout, let screen = target ?? currentScreen() else { return }
        let area = screen.visibleFrame
        guard area.width > 0, area.height > 0 else { return }
        isApplyingLayout = true
        defer { isApplyingLayout = false }
        let frame = ScreenSizing.frame(from: panel.frame, in: area, preference: relativeSize, anchor: anchor)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        // Keep one logical drawing space for artwork, text, hit targets and menu anchors.
        pet.frame = NSRect(origin: .zero, size: frame.size)
        pet.bounds = NSRect(origin: .zero, size: PetView.size)
        panel.invalidateCursorRects(for: pet)
        pet.needsDisplay = true
        reminderPresenter?.reposition(near: panel.frame)
    }

    func scheduleScreenAdaptation() {
        guard !isApplyingLayout else { return }
        layoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.pet.isInteracting else { return }
            let oldSize = self.panel.frame.size
            self.applySizing()
            if abs(oldSize.width - self.panel.frame.width) > 1 || abs(oldSize.height - self.panel.frame.height) > 1 { self.feedback.react(.screenChanged) }
            self.defaults.set(NSStringFromPoint(self.panel.frame.origin), forKey: "position")
            self.refresh()
        }
        layoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func savePosition() {
        // Defer cross-screen scaling until mouse-up so the pet cannot jump under a drag.
        applySizing(on: currentScreen(preferPointer: true))
        defaults.set(NSStringFromPoint(panel.frame.origin), forKey: "position")
        refresh()
    }

    func setRelativeSize(_ value: CGFloat, anchor: ScreenSizing.Anchor = .bottomRight) {
        feedback.react(.resizing)
        relativeSize = ScreenSizing.preference(value)
        applySizing(anchor: anchor)
        defaults.set(Double(relativeSize), forKey: "relativeSize")
        defaults.set(NSStringFromPoint(panel.frame.origin), forKey: "position")
        sizeControl?.update(relativeSize)
        refresh()
        resizeFeedbackWork?.cancel()
        let done = DispatchWorkItem { [weak self] in self?.feedback.react(.resized); self?.refresh() }
        resizeFeedbackWork = done
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: done)
    }

    func resizeFromGrip(scale: CGFloat, finished: Bool) {
        if gripScreen == nil { gripScreen = currentScreen() }
        guard let screen = gripScreen else { return }
        if !finished {
            relativeSize = ScreenSizing.preference(scale / ScreenSizing.recommendedScale(for: screen.visibleFrame.size))
        }
        // If mouse-up arrives without movement, keep the existing preference.
        applySizing(on: screen, anchor: .topLeft)
        refresh()
        if finished {
            gripScreen = nil
            defaults.set(Double(relativeSize), forKey: "relativeSize")
            defaults.set(NSStringFromPoint(panel.frame.origin), forKey: "position")
            sizeControl?.update(relativeSize)
            scheduleScreenAdaptation()
        }
    }
    func save() {
        if let data = try? JSONEncoder().encode(model.saved()) { defaults.set(data, forKey: "counter") }
        if let data = try? JSONEncoder().encode(wardrobe.saved()) { defaults.set(data, forKey: "wardrobe") }
        if let data = try? JSONEncoder().encode(rest.saved(at: Date())) { defaults.set(data, forKey: "restSession") }
        if let data = try? JSONEncoder().encode(reminderBook.saved()) { defaults.set(data, forKey: "scheduledReminders") }
        lastSaved = Date(); dirty = false
    }

    func menuWillOpen(_ menu: NSMenu) { feedback.react(.menu, say: false); pet.needsDisplay = true; rebuildMenu() }
    func rebuildMenu() {
        menu.removeAllItems()
        func add(_ title: String, _ action: Selector?, key: String = "", checked: Bool = false) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            if action == nil { item.isEnabled = false }
            if checked { item.state = .on }
            menu.addItem(item)
            return item
        }
        _ = add("今日有效输入 \(model.todayCount) 次", nil)
        _ = add("近 60 秒 \(model.rate()) 次 · 每秒刷新", nil)
        _ = add(model.isPaused ? "计数已暂停" : (IsSecureEventInputEnabled() ? "系统安全输入中，暂不计数" : (monitor.active ? "全局键鼠已连接" : "尚未连接，仅本应用内计数")), nil)
        menu.addItem(.separator())
        _ = add(reminderBook.pendingCount > 0 ? "定时提醒（\(reminderBook.pendingCount) 条待确认）…" : "定时提醒…", #selector(showReminderBook))
        _ = add("新增提醒…", #selector(newScheduledReminder))
        menu.addItem(.separator())
        _ = add("小衣柜（\(wardrobe.unlockedCount)/100）…", #selector(showWardrobe))
        _ = add("自动换装（每 100 次）", #selector(toggleAutomaticOutfits), checked: wardrobe.automatic)
        _ = add("恢复原样头像", #selector(chooseBareOutfit), checked: wardrobe.selectedID == nil)
        let outfitProgress = wardrobe.unlockedCount < 100 ? "下套装扮还需 \(wardrobe.keysToNext) 次" : "下次轮换还需 \(wardrobe.keysToNext) 次"
        _ = add("长期累计 \(wardrobe.total) 次 · \(outfitProgress)", nil)
        menu.addItem(.separator())
        _ = add(desktopVisible ? "收起桌宠" : "显示桌宠", #selector(toggleVisibility))
        _ = add(model.isPaused ? "继续计数" : "暂停计数", #selector(togglePause))
        let restItem = add(rest.enabled ? "休息提醒（\(Int(rest.intervalSeconds / 60)) 分钟）" : "休息提醒（已关闭）", nil)
        restItem.isEnabled = true
        let restMenu = NSMenu()
        let workInfo = NSMenuItem(title: "活跃工作约 \(Int(rest.activeSeconds / 60)) 分钟", action: nil, keyEquivalent: "")
        workInfo.isEnabled = false; restMenu.addItem(workInfo)
        let enableRest = NSMenuItem(title: "开启休息提醒", action: #selector(toggleRestReminders), keyEquivalent: "")
        enableRest.target = self; enableRest.state = rest.enabled ? .on : .off; restMenu.addItem(enableRest)
        restMenu.addItem(.separator())
        for minutes in [20,30,45,60] {
            let item = NSMenuItem(title: "\(minutes) 分钟", action: #selector(changeRestInterval(_:)), keyEquivalent: "")
            item.target = self; item.tag = minutes; item.state = Int(rest.intervalSeconds) == minutes * 60 ? .on : .off; restMenu.addItem(item)
        }
        restMenu.addItem(.separator())
        let preview = NSMenuItem(title: "预览休息提醒", action: #selector(previewRestReminder), keyEquivalent: ""); preview.target = self; restMenu.addItem(preview)
        let later = NSMenuItem(title: "再活跃 10 分钟后提醒", action: #selector(snoozeRest), keyEquivalent: ""); later.target = self; restMenu.addItem(later)
        later.isEnabled = rest.enabled
        let done = NSMenuItem(title: "我休息好了，重新计时", action: #selector(finishedRest), keyEquivalent: ""); done.target = self; restMenu.addItem(done)
        restItem.submenu = restMenu
        let sizeItem = add("桌宠大小（\(Int((relativeSize * 100).rounded()))%）", nil)
        sizeItem.isEnabled = true
        let sizeMenu = NSMenu()
        let sliderItem = NSMenuItem()
        let control = SizeControlView(value: relativeSize, target: self, action: #selector(sizeSliderChanged(_:)))
        sizeControl = control
        sliderItem.view = control
        sizeMenu.addItem(sliderItem)
        sizeMenu.addItem(.separator())
        for percent in [50, 75, 100, 125, 150, 180] {
            let item = NSMenuItem(title: percent == 100 ? "100% · 推荐大小" : "\(percent)%", action: #selector(selectSize(_:)), keyEquivalent: "")
            item.target = self; item.tag = percent
            item.state = abs(relativeSize * 100 - CGFloat(percent)) < 0.5 ? .on : .off
            sizeMenu.addItem(item)
        }
        sizeMenu.addItem(.separator())
        let info = NSMenuItem(title: "随屏幕自动适配 · 当前 \(Int(panel.frame.width.rounded())) × \(Int(panel.frame.height.rounded()))", action: nil, keyEquivalent: "")
        info.isEnabled = false
        sizeMenu.addItem(info)
        sizeItem.submenu = sizeMenu
        _ = add("鼠标穿透（从菜单栏恢复）", #selector(toggleClickThrough), checked: permanentlyClickThrough)
        let sleep = add("多久以后睡觉", nil)
        sleep.isEnabled = true
        let choices = NSMenu()
        for seconds in [30, 60, 120] {
            let item = NSMenuItem(title: seconds == 120 ? "2 分钟" : "\(seconds) 秒", action: #selector(changeSleep(_:)), keyEquivalent: "")
            item.target = self; item.tag = seconds
            item.state = model.sleepSeconds == Double(seconds) ? .on : .off
            choices.addItem(item)
        }
        sleep.submenu = choices
        menu.addItem(.separator())
        _ = add("打开试打窗口…", #selector(openTest))
        _ = add(monitor.active ? "输入监控设置…" : "开启全局键鼠计数…", #selector(openPermissions))
        _ = add("重新连接输入监听", #selector(reconnect))
        _ = add("计数规则与说明…", #selector(showAbout))
        menu.addItem(.separator())
        _ = add("退出敲敲", #selector(quit), key: "q")
    }
    func showMenu() {
        rebuildMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 205, y: 155), in: pet)
    }

    func enableMonitoring() {
        feedback.react(.permission); refresh()
        if monitor.active { openInputSettings(); return }
        if CGPreflightListenEventAccess(), monitor.start() { feedback.react(.connected); refresh(); return }
        let alert = NSAlert()
        alert.messageText = "让敲敲跟上你的键鼠"
        alert.informativeText = "跨应用计数需要 macOS 的“输入监控”权限。敲敲只在本机统计有效键鼠操作，不读取输入文字，不保存鼠标轨迹，也不联网。\n\n点“去开启”，在输入监控中打开“敲敲”。如果开关已经打开，请先关掉再打开，并按系统提示退出重开。\n\n本地原型更新后，临时签名可能变化，旧授权会失效。如果重新切换仍无效，请从列表移除旧“敲敲”，再添加现在运行的“敲敲.app”。\n\n暂时不授权时，只能统计本应用内的操作；定时提醒仍可使用。"
        alert.addButton(withTitle: "去开启")
        alert.addButton(withTitle: "先试打")
        alert.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            _ = CGRequestListenEventAccess()
            openInputSettings()
        } else if response == .alertSecondButtonReturn { showTestWindow() }
        NSApp.setActivationPolicy(testWindow?.isVisible == true ? .regular : .accessory)
    }

    func explainInputConnection() {
        if model.isPaused { togglePause(); return }
        if IsSecureEventInputEnabled() {
            let alert = NSAlert()
            alert.messageText = "系统正在保护键盘输入"
            alert.informativeText = "macOS 开启了安全输入，敲敲会暂时停止计数。离开密码输入框或关闭仍在使用安全输入的应用后会自动恢复。"
            alert.addButton(withTitle: "知道啦")
            NSApp.activate(ignoringOtherApps: true); alert.runModal()
        } else { enableMonitoring() }
    }
    func openInputSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") { NSWorkspace.shared.open(url) }
    }
    func showTestWindow() {
        feedback.react(.testing); refresh()
        if testWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 290), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "敲敲 · 试打窗口"
            window.acceptsMouseMovedEvents = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            let input = TryTypingView(frame: NSRect(x: 0, y: 0, width: 460, height: 290))
            input.count = model.todayCount
            input.onKey = { [weak self, weak input] event in
                guard let self = self else { return }
                if !self.monitor.active && self.localInputMonitor == nil {
                    self.accept(code: Int(event.keyCode), repeated: event.isARepeat, command: event.modifierFlags.contains(.command), control: event.modifierFlags.contains(.control))
                }
                // A global event tap already counted it when permission is active.
                input?.count = self.model.todayCount
                input?.needsDisplay = true
            }
            window.contentView = input
            window.center()
            testWindow = window
            testView = input
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        testView?.count = model.todayCount
        testView?.needsDisplay = true
        testWindow?.makeKeyAndOrderFront(nil)
        testWindow?.makeFirstResponder(testView)
    }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === testWindow {
            if wardrobeWindow?.window?.isVisible != true && reminderWindow?.window?.isVisible != true { NSApp.setActivationPolicy(.accessory) }
            feedback.react(.shown); refresh()
        }
    }

    @objc func showReminderBook() {
        if reminderWindow == nil {
            reminderWindow = ReminderWindowController(book: reminderBook) { [weak self] mutation in self?.remindersChanged(mutation) }
            reminderWindow?.onClose = { [weak self] in
                guard let self = self else { return }
                if self.testWindow?.isVisible != true && self.wardrobeWindow?.window?.isVisible != true { NSApp.setActivationPolicy(.accessory) }
                self.feedback.react(.shown); self.refresh()
            }
        }
        reminderWindow?.refresh()
        if let id = activeScheduledReminder { reminderWindow?.editor.selectReminder(id) }
        feedback.react(.reminderBook); refresh()
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
        reminderWindow?.showWindow(nil); reminderWindow?.window?.makeKeyAndOrderFront(nil)
    }
    @objc func newScheduledReminder() {
        showReminderBook(); reminderWindow?.editor.newEditor()
        reminderWindow?.window?.makeFirstResponder(reminderWindow?.editor.titleField)
    }
    func remindersChanged(_ mutation: ReminderMutation) {
        let reaction: PetReaction
        switch mutation {
        case .saved: reaction = .reminderSaved
        case .edited: reaction = .reminderEdited
        case .completed: reaction = .reminderDone
        case .snoozed: reaction = .reminderSnoozed
        case .acknowledged: reaction = .reminderAcknowledged
        case .deleted: reaction = .reminderDeleted
        }
        save(); reminderWindow?.refresh()
        // Rebuild a visible alert after edits; never treat merely displaying it as completion.
        clearScheduledPresentation()
        feedback.react(reaction); processScheduledReminders(at: Date()); refresh()
    }
    func clearScheduledPresentation() {
        reminderPresenter?.hide(); activeScheduledReminder = nil; pet.timedReminderVisible = false
    }
    func processScheduledReminders(at now: Date) {
        let newlyDue = reminderBook.collectDue(at: now)
        if !newlyDue.isEmpty { save(); reminderWindow?.refresh() }
        let hasPending = reminderBook.pendingCount > 0
        if hasPending != reminderBadge {
            reminderBadge = hasPending
            statusItem.button?.image = NSImage(systemSymbolName: hasPending ? "bell.badge.fill" : "pawprint.fill", accessibilityDescription: hasPending ? "敲敲，有待确认的提醒" : "敲敲桌宠")
        }
        guard !sessionInactive, !machineSleeping else { clearScheduledPresentation(); return }
        if let active = activeScheduledReminder, let item = reminderBook.awaiting.first(where: { $0.id == active }) {
            if !newlyDue.isEmpty { reminderPresenter?.show(item, count: reminderBook.pendingCount, near: panel.frame) }
            return
        }
        if activeScheduledReminder != nil { clearScheduledPresentation() }
        guard !pet.isInteracting, let item = reminderBook.awaiting.first else { return }
        if reminderPresenter == nil {
            let presenter = ScheduledReminderPresenter()
            presenter.onComplete = { [weak self] id in
                guard let self = self, self.reminderBook.complete(id) else { return }; self.remindersChanged(.completed)
            }
            presenter.onSnooze = { [weak self] id in
                guard let self = self else { return }
                guard (try? self.reminderBook.snooze(id, until: Date().addingTimeInterval(600))) != nil else { return }
                self.remindersChanged(.snoozed)
            }
            presenter.onLater = { [weak self] id in
                guard let self = self, self.reminderBook.acknowledge(id) else { return }; self.remindersChanged(.acknowledged)
            }
            reminderPresenter = presenter
        }
        activeScheduledReminder = item.id; pet.timedReminderVisible = true
        feedback.react(.scheduledReminder, at: now)
        reminderPresenter?.show(item, count: reminderBook.pendingCount, near: panel.frame)
        refresh()
    }

    @objc func showWardrobe() {
        if wardrobeWindow == nil {
            wardrobeWindow = WardrobeWindowController(wardrobe: wardrobe) { [weak self] id in self?.equipOutfit(id) }
            wardrobeWindow?.onClose = { [weak self] in
                guard let self = self else { return }
                if self.testWindow?.isVisible != true && self.reminderWindow?.window?.isVisible != true { NSApp.setActivationPolicy(.accessory) }
                self.feedback.react(.shown); self.refresh()
            }
        }
        wardrobeWindow?.refresh(); feedback.react(.catalog); refresh()
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
        wardrobeWindow?.showWindow(nil); wardrobeWindow?.window?.makeKeyAndOrderFront(nil)
    }
    func equipOutfit(_ id: Int?) {
        guard wardrobe.equip(id) else { return }
        feedback.react(id == nil ? .original : .dressed)
        pendingOutfitFeedback = nil
        wardrobeWindow?.refresh(); save(); refresh()
    }
    @objc func chooseBareOutfit() { equipOutfit(nil) }
    @objc func toggleAutomaticOutfits() {
        wardrobe.setAutomatic(!wardrobe.automatic)
        feedback.react(wardrobe.automatic ? .dressed : .settings)
        pendingOutfitFeedback = nil
        wardrobeWindow?.refresh(); save(); refresh()
    }

    @objc func toggleVisibility() {
        visibilityWork?.cancel()
        desktopVisible.toggle()
        if desktopVisible {
            panel.alphaValue = 1; panel.orderFrontRegardless(); feedback.react(.shown); refresh()
        } else {
            feedback.react(.hidden); refresh()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, !self.desktopVisible else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.18; self.panel.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    guard let self = self, !self.desktopVisible else { return }
                    self.panel.orderOut(nil); self.panel.alphaValue = 1
                })
            }
            visibilityWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }
    }
    @objc func togglePause() {
        model.setPaused(!model.isPaused)
        synchronizeMonitoringState()
        feedback.react(model.isPaused ? .paused : .resumed)
        refresh()
    }
    @objc func toggleRestReminders() { rest.setEnabled(!rest.enabled, at: Date()); pendingRestReminder = false; feedback.react(.settings); dirty = true; save(); refresh() }
    @objc func changeRestInterval(_ item: NSMenuItem) { rest.setInterval(Double(item.tag * 60), at: Date()); pendingRestReminder = false; feedback.react(.settings); dirty = true; save(); refresh() }
    @objc func snoozeRest() { rest.snooze(at: Date()); pendingRestReminder = false; feedback.react(.settings); dirty = true; save(); refresh() }
    @objc func finishedRest() { rest.resetAfterRest(at: Date()); pendingRestReminder = false; feedback.react(.restDone); dirty = true; save(); refresh() }
    @objc func previewRestReminder() { feedback.react(.restPreview); refresh() }
    @objc func toggleClickThrough() { permanentlyClickThrough.toggle(); panel.ignoresMouseEvents = permanentlyClickThrough; feedback.react(permanentlyClickThrough ? .ghost : .solid); refresh() }
    @objc func sizeSliderChanged(_ sender: NSSlider) { setRelativeSize(CGFloat(sender.doubleValue / 100)) }
    @objc func selectSize(_ item: NSMenuItem) { setRelativeSize(CGFloat(item.tag) / 100) }
    @objc func changeSleep(_ item: NSMenuItem) { model.sleepSeconds = Double(item.tag); dirty = true; save(); feedback.react(.settings); refresh() }
    @objc func openTest() { showTestWindow() }
    @objc func openPermissions() { enableMonitoring() }
    @objc func reconnect() {
        monitor.stop()
        if !monitoringSuspended { _ = monitor.start() }
        feedback.react(monitor.active ? .connected : .blocked)
        refresh()
        if !monitor.active && !monitoringSuspended { enableMonitoring() }
    }
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "敲敲 · 桌面小搭子 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")"
        alert.informativeText = "数字是今日真实按下动作总数与最近 60 秒的次数；每天零点归零，长期累计及装扮进度保留。\n\n键盘按下即记一次，包括删除、方向键、功能键、快捷键与 Shift、Command 等修饰键；松开和长按自动连发不重复加数。输入法最后上屏多少字不会影响计数。\n\n\(countingRule.pointerExplanation)\n\n默认每约 45 分钟活跃工作提醒休息，无输入 60 秒后暂停累计，休息 5 分钟后重新计时。\n\n右键 → 定时提醒，可填写事项与日期时间。到点弹出气泡，支持完成、延后 10 分钟或收进提醒本。需程序运行；睡眠或退出期间错过的，唤醒或重开后补提醒。暂停计数不会暂停定时提醒。\n\n所有数据只在本机处理。键鼠监听不读取输入文字，不保存轨迹。你主动填写的提醒事项与时间会保存在本机，无网络功能。"
        alert.addButton(withTitle: "知道啦")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    func synchronizeMonitoringState() {
        rest.setSuspended(monitoringSuspended, at: Date()); pointerFilter.reset(); pendingRestReminder = false
        modifierFilter.reset(flags: CGEventSource.flagsState(.combinedSessionState).rawValue)
        if monitoringSuspended { monitor.stop() } else { _ = monitor.start() }
    }
    @objc func didWake() { machineSleeping = false; synchronizeMonitoringState(); scheduleScreenAdaptation(); processScheduledReminders(at: Date()); refresh() }
    @objc func willSleep() { machineSleeping = true; synchronizeMonitoringState(); clearScheduledPresentation(); save() }
    @objc func sessionResigned() { sessionInactive = true; synchronizeMonitoringState(); clearScheduledPresentation(); save() }
    @objc func sessionBecameActive() { sessionInactive = false; synchronizeMonitoringState(); processScheduledReminders(at: Date()); refresh() }
    @objc func screensChanged() { scheduleScreenAdaptation() }
    func windowDidChangeScreen(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === panel { scheduleScreenAdaptation() }
    }
    func windowDidMove(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === panel { reminderPresenter?.reposition(near: panel.frame) }
    }
    func windowDidChangeBackingProperties(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === panel { scheduleScreenAdaptation() }
    }
    @objc func quit() {
        guard !isQuitting else { return }; isQuitting = true
        feedback.react(.goodbye); refresh(); save()
        DispatchQueue.main.asyncAfter(deadline: .now() + (panel.isVisible ? 0.45 : 0)) { NSApp.terminate(nil) }
    }
    func applicationWillTerminate(_ notification: Notification) { save(); monitor.stop(); if let local = localInputMonitor { NSEvent.removeMonitor(local) }; timer?.invalidate(); layoutWorkItem?.cancel(); resizeFeedbackWork?.cancel(); visibilityWork?.cancel() }
}
