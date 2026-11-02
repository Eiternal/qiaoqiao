import AppKit

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }
}

final class PetView: NSView {
    static let size = ScreenSizing.baseSize
    let model: CounterModel
    let feedback: FeedbackModel
    let wardrobe: WardrobeModel?
    var previewOutfit: Outfit?
    var showsCounter = true
    var showsSpeech = true
    var timedReminderVisible = false
    var globalAvailable = false
    var secureInput = false
    var now = Date()
    var demo = false
    var previewCel: (state: CelState, elapsed: Double)?
    // Diagnostics observe the real NSView draw boundary, not a timer estimate.
    var onDraw: ((CelState, Int) -> Void)?
    private let celAnimator = CelAnimator()
    var onMenu: (() -> Void)?
    var onConnectInput: (() -> Void)?
    var onMove: (() -> Void)?
    var onResize: ((CGFloat, Bool) -> Void)?
    var onReaction: ((PetReaction) -> Void)?
    private var dragOrigin: NSPoint?
    private var windowOrigin: NSPoint?
    private var moved = false
    private var resizeStartFrame: NSRect?
    private var resizeStartMouse: NSPoint?
    var isInteracting: Bool { dragOrigin != nil || resizeStartFrame != nil }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private let ink = NSColor(hex: 0x51434E)
    private let outline = NSColor(hex: 0xD7BFAE)
    private let cream = NSColor(hex: 0xFFFAEF)
    private var resizeRect: NSRect { NSRect(x: 220, y: 207, width: 28, height: 28) }
    private let avatarRect = NSRect(x: 49, y: 47, width: 185, height: 145)
    private let counterRect = NSRect(x: 24, y: 195, width: 216, height: 35)
    var needsInputHelp: Bool { !demo && (!globalAvailable || secureInput || model.isPaused) }
    private static let countFormatter: NumberFormatter = {
        let value = NumberFormatter(); value.numberStyle = .decimal; return value
    }()

    init(model: CounterModel, feedback: FeedbackModel = FeedbackModel(), wardrobe: WardrobeModel? = nil) {
        self.model = model; self.feedback = feedback; self.wardrobe = wardrobe
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("敲敲头像与有效输入计数")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var counterText: String {
        let total = Self.countFormatter.string(from: NSNumber(value: model.todayCount)) ?? "0"
        return "\(total)｜\(model.rate(at: now))/min"
    }
    func visibleText() -> [String] {
        (showsCounter ? [counterText] : []) + (showsSpeech && !timedReminderVisible ? (feedback.visibleSpeech(at: now).map { [$0.text] } ?? []) : [])
    }

    private func text(_ value: String, in rect: NSRect, size: CGFloat, color: NSColor? = nil, weight: NSFont.Weight = .medium, mono: Bool = false) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byClipping
        let font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        (value as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color ?? ink, .paragraphStyle: paragraph])
    }
    private func round(_ rect: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, width: CGFloat = 1) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        fill.setFill(); path.fill()
        if let stroke = stroke { stroke.setStroke(); path.lineWidth = width; path.stroke() }
    }
    private func line(_ points: [NSPoint], color: NSColor? = nil, width: CGFloat = 2.2) {
        guard let first = points.first else { return }
        let p = NSBezierPath(); p.move(to: first)
        for point in points.dropFirst() { p.line(to: point) }
        p.lineWidth = width; p.lineCapStyle = .round; p.lineJoinStyle = .round
        (color ?? ink).setStroke(); p.stroke()
    }
    private func arc(from a: NSPoint, via b: NSPoint, to c: NSPoint, width: CGFloat = 2.8, color: NSColor? = nil) {
        let p = NSBezierPath(); p.move(to: a); p.curve(to: c, controlPoint1: b, controlPoint2: b)
        p.lineWidth = width; p.lineCapStyle = .round; (color ?? ink).setStroke(); p.stroke()
    }
    private func heart(at center: NSPoint, size: CGFloat) {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: center.x, y: center.y + size * 0.5))
        p.curve(to: NSPoint(x: center.x - size * 0.5, y: center.y - size * 0.1), controlPoint1: NSPoint(x: center.x - size, y: center.y), controlPoint2: NSPoint(x: center.x - size, y: center.y - size * 0.8))
        p.curve(to: NSPoint(x: center.x, y: center.y - size * 0.2), controlPoint1: NSPoint(x: center.x - size * 0.25, y: center.y - size * 0.55), controlPoint2: NSPoint(x: center.x, y: center.y - size * 0.55))
        p.curve(to: NSPoint(x: center.x + size * 0.5, y: center.y - size * 0.1), controlPoint1: NSPoint(x: center.x, y: center.y - size * 0.55), controlPoint2: NSPoint(x: center.x + size * 0.25, y: center.y - size * 0.55))
        p.curve(to: NSPoint(x: center.x, y: center.y + size * 0.5), controlPoint1: NSPoint(x: center.x + size, y: center.y - size * 0.8), controlPoint2: NSPoint(x: center.x + size, y: center.y))
        NSColor(hex: 0xE4A9B6).setFill(); p.fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Event handlers can invalidate between timer ticks (especially while
        // dragging). Use the current time for live views, fixed time for exports.
        if !demo && previewCel == nil { now = Date() }
        let mood = model.mood(at: now)
        let rawPose = feedback.pose(mood: mood, at: now)
        let pose: PetReaction? = timedReminderVisible && (rawPose == nil || [.sleeping, .drowsy, .paused].contains(rawPose!)) ? .scheduledReminder : rawPose
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let keyAge = max(0, now.timeIntervalSince(feedback.lastPress))
        let keyPulse = max(0, 1 - keyAge / 0.24)
        // Direct manipulation keeps its own animation while a due reminder stays visible.
        let recentInput = now.timeIntervalSince(feedback.lastInputResponse) < 0.25
        let reminderPose = timedReminderVisible && !recentInput && ![PetReaction.dragging, .pressed, .resizing, .petting, .dropped].contains(pose ?? .typing)
        let state = previewCel?.state ?? CelState.forReaction(pose, reminder: reminderPose)
        let elapsed = previewCel?.elapsed ?? celAnimator.elapsed(for: state, at: now)
        let cel = previewCel == nil ? (state.inputCel(age: now.timeIntervalSince(feedback.lastInputResponse), serial: feedback.inputSerial, reduced: reduce) ?? state.cel(at: elapsed, reduced: reduce)) : state.cel(at: elapsed, reduced: reduce)
        CelRenderer.draw(state: state, cel: cel, elapsed: elapsed, pose: pose, feedback: feedback,
                         outfit: previewOutfit ?? wardrobe?.selected, wardrobe: wardrobe, now: now, reduced: reduce)

        if showsCounter {
            round(counterRect, radius: 16, fill: NSColor(hex: 0xFFFDF9, alpha: model.isPaused ? 0.65 : 0.94), stroke: NSColor(hex: 0xE7DDE4, alpha: 0.8))
            if needsInputHelp {
                let dot = NSBezierPath(ovalIn: NSRect(x: 34, y: 209, width: 6, height: 6))
                NSColor(hex: model.isPaused ? 0xB1A6AF : 0xD39A42).setFill(); dot.fill()
            }
            let countText = counterText
            let fontSize: CGFloat = countText.count > 19 ? 13 : (countText.count > 16 ? 15 : 17)
            text(countText, in: NSRect(x: 33, y: 202 - (reduce ? 0 : keyPulse), width: 198, height: 25), size: fontSize, color: NSColor(hex: 0x796276, alpha: model.isPaused ? 0.6 : 1), mono: true)
        }
        if showsCounter && (feedback.hovered || feedback.interaction == .resizing) {
            line([NSPoint(x: 225, y: 221), NSPoint(x: 232, y: 214)], color: NSColor(hex: 0xCDBACD), width: 1.2)
            line([NSPoint(x: 231, y: 224), NSPoint(x: 235, y: 220)], color: NSColor(hex: 0xCDBACD), width: 1.2)
        }
        if showsSpeech && !timedReminderVisible, let speech = feedback.visibleSpeech(at: now) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.setAlpha(CGFloat(speech.alpha(at: now)))
            round(NSRect(x: 14, y: 4, width: 236, height: 39), radius: 15, fill: NSColor(hex: 0xFFFCF8), stroke: NSColor(hex: 0xE4D3CD))
            let tip = NSBezierPath(); tip.move(to: NSPoint(x: 123, y: 42)); tip.line(to: NSPoint(x: 132, y: 50)); tip.line(to: NSPoint(x: 141, y: 42)); tip.close(); NSColor(hex: 0xFFFCF8).setFill(); tip.fill()
            text(speech.text, in: NSRect(x: 24, y: 15, width: 216, height: 20), size: 12)
            NSGraphicsContext.restoreGraphicsState()
        }
        onDraw?(state, cel)
    }

    override func resetCursorRects() {
        super.resetCursorRects(); addCursorRect(resizeRect, cursor: .crosshair)
        if needsInputHelp { addCursorRect(counterRect, cursor: .pointingHand) }
    }
    func updatePointer(_ screenPoint: NSPoint) {
        guard let window = window else { return }
        let point = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        let hovered = avatarRect.contains(point) || counterRect.contains(point)
        if feedback.hovered != hovered { feedback.hovered = hovered; needsDisplay = true }
        feedback.lookX = Double(min(1, max(-1, (point.x - 132) / 80)))
        feedback.lookY = Double(min(1, max(-1, (point.y - 127) / 70)))
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if resizeRect.contains(point), let frame = window?.frame {
            resizeStartFrame = frame; resizeStartMouse = screenLocation(for: event)
            feedback.beginResize(at: Date()); needsDisplay = true
            return
        }
        if counterRect.contains(point), needsInputHelp {
            onConnectInput?(); return
        }
        if point.y < 50, feedback.visibleSpeech(at: Date()) != nil {
            feedback.react(.petting, at: Date(), say: false); needsDisplay = true
            return
        }
        dragOrigin = screenLocation(for: event); windowOrigin = window?.frame.origin; moved = false
        feedback.press(at: Date()); needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        if let frame = resizeStartFrame, let mouse = resizeStartMouse {
            let current = screenLocation(for: event), base = Self.size
            let delta = ((current.x - mouse.x) * base.width - (current.y - mouse.y) * base.height) / (base.width * base.width + base.height * base.height)
            onResize?(frame.width / base.width + delta, false); needsDisplay = true; return
        }
        guard let origin = dragOrigin, let start = windowOrigin, let window = window else { return }
        let current = screenLocation(for: event), dx = current.x - origin.x, dy = current.y - origin.y
        if abs(dx) + abs(dy) > 3 { moved = true; feedback.drag(at: Date()) }
        if moved { window.setFrameOrigin(NSPoint(x: start.x + dx, y: start.y + dy)) }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if resizeStartFrame != nil {
            let scale = (window?.frame.width ?? Self.size.width) / Self.size.width
            resizeStartFrame = nil; resizeStartMouse = nil
            feedback.endResize(at: Date()); onResize?(scale, true); needsDisplay = true; return
        }
        guard dragOrigin != nil else { return }
        let didMove = moved; dragOrigin = nil; windowOrigin = nil
        feedback.release(wasDragged: didMove, at: Date())
        if didMove { onMove?() }
        needsDisplay = true
    }
    override func rightMouseDown(with event: NSEvent) {
        feedback.react(.menu, at: Date(), say: false); needsDisplay = true; onMenu?()
    }
    private func screenLocation(for event: NSEvent) -> NSPoint {
        if let point = event.cgEvent?.location, let primary = NSScreen.screens.first { return NSPoint(x: point.x, y: primary.frame.maxY - point.y) }
        return window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }
}

final class TryTypingView: NSView {
    var onKey: ((NSEvent) -> Void)?
    var count = 0 { didSet { setAccessibilityValue("今日有效输入 \(count) 次"); needsDisplay = true } }
    override init(frame: NSRect) {
        super.init(frame: frame); setAccessibilityElement(true); setAccessibilityRole(.group)
        setAccessibilityLabel("试用区域，可敲键、点击、滚动或移动鼠标"); setAccessibilityValue("今日有效输入 0 次")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(hex: 0xFFFCF8).setFill(); bounds.fill()
        let style = NSMutableParagraphStyle(); style.alignment = .center
        ("\(count)" as NSString).draw(in: NSRect(x: 20, y: 125, width: bounds.width - 40, height: 55), withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 38, weight: .medium), .foregroundColor: NSColor(hex: 0x9580AF), .paragraphStyle: style])
        NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)?.draw(in: NSRect(x: bounds.midX - 22, y: 70, width: 44, height: 27))
    }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) { super.keyDown(with: event); return }; onKey?(event)
    }
}
