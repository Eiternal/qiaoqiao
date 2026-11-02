import AppKit

/// Optional developer check. Uses the production controller, input filters,
/// timer and NSView in an actual window, with an isolated disposable save domain.
/// Measures callback -> completed draw, not physical device -> display scanout.
final class ResponseProbe: NSObject, NSApplicationDelegate {
    private let directory: URL
    private let domain = "local.qiaoqiao.response-probe.\(UUID().uuidString)"
    private var controller: AppController!
    private var inputTimer: Timer?
    private var inputs = 0
    private var expectedCount = 0
    private var requested: (serial: Int, began: Double, impact: Bool)?
    private var samples: [Double] = []
    private var missed = 0
    private var badContact = 0
    private var failed: [String] = []
    private var pulseDraws = 0
    private var pulseBegan = 0.0
    private var pulseSeconds = 0.0
    private var captured: Set<Int> = []
    private(set) var passed = false

    init(directory: String) { self.directory = URL(fileURLWithPath: directory); super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settings = UserDefaults(suiteName: domain)!
        let now = Date()
        let saved = SavedCounter(day: CounterModel.dayKey(now, calendar: .autoupdatingCurrent), count: 1398, sleepSeconds: 60, lifetimeCount: 1398)
        settings.set(try! JSONEncoder().encode(saved), forKey: "counter")
        controller = AppController(settings: settings)
        controller.panel = CompanionPanel(contentRect: NSRect(origin: .zero, size: PetView.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        controller.panel.isOpaque = false; controller.panel.backgroundColor = .clear
        controller.panel.level = .floating; controller.panel.hidesOnDeactivate = false
        controller.panel.title = "敲敲响应诊断"
        controller.pet = PetView(model: controller.model, feedback: controller.feedback, wardrobe: controller.wardrobe)
        controller.panel.contentView = controller.pet
        if let screen = NSScreen.main {
            controller.panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 300, y: screen.visibleFrame.minY + 40))
        }
        controller.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        CelAssets.preload(); if let outfit = controller.wardrobe.selected { OutfitLayers.preload(outfit) }
        controller.panel.orderFrontRegardless()
        controller.pet.onDraw = { [weak self] state, cel in self?.drew(state: state, cel: cel) }
        controller.timer = Timer(timeInterval: 1.0/24, repeats: true) { [weak self] _ in self?.controller.pulse() }
        RunLoop.main.add(controller.timer!, forMode: .common)
        expectedCount = 1398
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.startInputs() }
    }

    private func startInputs() {
        inputTimer = Timer(timeInterval: 0.07, repeats: true) { [weak self] _ in self?.input() }
        RunLoop.main.add(inputTimer!, forMode: .common)
    }

    private func input() {
        if requested != nil { missed += 1; requested = nil }
        guard inputs < 75 else { inputTimer?.invalidate(); startCadenceCheck(); return }
        let index = inputs; inputs += 1
        let feedback = controller.feedback
        // Previously blocking states plus a real unlock at 1,400 inputs.
        if [0, 15, 30, 45].contains(index) {
            let reaction: PetReaction = [0: .waking, 15: .dropped, 30: .rest, 45: .petting][index]!
            feedback.react(reaction)
        }
        controller.pet.timedReminderVisible = (60..<68).contains(index)
        let began = ProcessInfo.processInfo.systemUptime
        let oldSerial = feedback.inputSerial
        if index >= 72 {
            controller.pointerFilter.reset()
            let kind: EffectiveInputKind = index == 72 ? .click : (index == 73 ? .movement : .scroll)
            controller.acceptPointer(kind, dx: 32, dy: 0, momentum: false)
            if controller.countingRule.includesPointer(kind) { expectedCount += 1 }
        } else {
            let repeated = index == 55
            controller.accept(code: index % 24 >= 18 ? 51 : 0, repeated: repeated)
            if !repeated { expectedCount += 1 }
        }
        requested = (feedback.inputSerial, began, feedback.inputSerial != oldSerial)
        if controller.model.todayCount != expectedCount { failed.append("count differs at input \(index)") }
    }

    private func drew(state: CelState, cel: Int) {
        if pulseBegan > 0 { pulseDraws += 1 }
        guard let request = requested, request.serial == controller.feedback.inputSerial else { return }
        samples.append((ProcessInfo.processInfo.systemUptime - request.began) * 1000)
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let expected = state.inputCel(age: 0, serial: request.serial, reduced: reduce)
        if request.impact && (expected != cel || ![CelState.typing, .fast, .deleting].contains(state)) { badContact += 1 }
        requested = nil
        let index = inputs - 1
        if [0, 16, 31, 61, 72, 73, 74].contains(index), !captured.contains(index) {
            captured.insert(index)
            // Defer image export until after measuring this draw.
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let rep = self.controller.pet.bitmapImageRepForCachingDisplay(in: self.controller.pet.bounds) else { return }
                self.controller.pet.cacheDisplay(in: self.controller.pet.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: self.directory.appendingPathComponent("输入响应_\(index).png"))
            }
        }
    }

    private func startCadenceCheck() {
        controller.pet.timedReminderVisible = false
        controller.feedback.beginResize(at: Date())
        pulseBegan = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self else { return }
            self.pulseSeconds = ProcessInfo.processInfo.systemUptime - self.pulseBegan
            self.finish()
        }
    }

    private func finish() {
        controller.timer?.invalidate(); inputTimer?.invalidate()
        controller.pet.onDraw = nil
        let sorted = samples.sorted()
        let p50 = sorted.isEmpty ? .infinity : sorted[sorted.count/2]
        let p95 = sorted.isEmpty ? .infinity : sorted[Int(Double(sorted.count-1)*0.95)]
        let maxMS = sorted.last ?? .infinity
        let drawRate = Double(pulseDraws)/pulseSeconds
        if samples.count != 75 || missed != 0 { failed.append("not all 75 input callbacks painted before the next event") }
        if badContact != 0 { failed.append("\(badContact) inputs missed immediate contact drawing") }
        if p95 >= 75 || maxMS >= 100 { failed.append("callback-to-draw exceeded 75ms p95 / 100ms max budget") }
        if drawRate < 21 { failed.append("active draw cadence below 21 fps") }
        if controller.wardrobe.unlockedCount != 14 { failed.append("unlock progress failed") }
        passed = failed.isEmpty
        let report = """
        敲敲 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development") 原生窗口响应诊断
        采用实际 AppController.accept / acceptPointer、pulse 与 PetView.draw。
        测试输入从应用回调入口注入，不发送真实系统键鼠事件。
        使用独立临时存档，不读取或修改用户进度；不请求输入监控权限。
        输入间隔 70 ms，含唤醒、落地、休息、摸摸、自动换装、待处理提醒、删除、长按及三类鼠标输入。
        \(samples.count)/75 次输入在下一次输入之前完成绘制；遗漏 \(missed)，落爪帧错误 \(badContact)。
        回调入口到实际 draw 完成：p50 \(String(format: "%.2f", p50)) ms；p95 \(String(format: "%.2f", p95)) ms；最大 \(String(format: "%.2f", maxMS)) ms。
        连续动画绘制：\(pulseDraws) 帧 / \(String(format: "%.2f", pulseSeconds)) 秒，\(String(format: "%.2f", drawRate)) fps。
        计数：\(controller.model.todayCount)，预期 \(expectedCount)；装扮 \(controller.wardrobe.unlockedCount)/100。
        结果：\(passed ? "通过" : "未通过")。
        \(failed.joined(separator: "\n"))
        范围：不包含物理键盘、系统事件派发和显示器扫描输出的延迟；不能当作端到端硬件延迟。
        """
        print(report)
        try? report.write(to: directory.appendingPathComponent("响应诊断.txt"), atomically: true, encoding: .utf8)
        controller.panel.orderOut(nil)
        NSStatusBar.system.removeStatusItem(controller.statusItem)
        controller.defaults.removePersistentDomain(forName: domain)
        NSApp.stop(nil)
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: false) }
    }
}
