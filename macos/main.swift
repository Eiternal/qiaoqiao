import AppKit

func renderPreview(_ view: NSView, to path: String) {
    view.display()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: rep)
    if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: path)) }
}

func previewScene(_ name: String, now: Date) -> PetView {
    let day = CounterModel.dayKey(now, calendar: .autoupdatingCurrent)
    let model = CounterModel(now: now, saved: SavedCounter(day: day, count: 1268, sleepSeconds: 60))
    let feedback = FeedbackModel()
    let view = PetView(model: model, feedback: feedback)
    view.globalAvailable = true; view.demo = true
    feedback.observe(mood: .awake, at: now)
    var end = now.addingTimeInterval(4)
    switch name {
    case "正在打字", "快速打字", "连续删除":
        let n = name == "快速打字" ? 18 : (name == "连续删除" ? 8 : 1)
        let code = name == "连续删除" ? 51 : 0
        for i in 0..<n {
            let time = now.addingTimeInterval(Double(i) * 0.1)
            model.record(keyCode: code, at: time)
            feedback.key(code: code, repeated: false, counted: true, previousMood: .typing, at: time)
        }
        end = now.addingTimeInterval(Double(n - 1) * 0.1 + 0.18)
    case "开始犯困": feedback.observe(mood: .drowsy, at: now.addingTimeInterval(55)); end = now.addingTimeInterval(55.5)
    case "睡着啦": feedback.observe(mood: .sleeping, at: now.addingTimeInterval(60)); end = now.addingTimeInterval(60.5)
    case "被提起": feedback.press(at: now); feedback.drag(at: now.addingTimeInterval(0.1)); end = now.addingTimeInterval(0.7)
    case "摸摸": feedback.press(at: now); feedback.release(wasDragged: false, at: now.addingTimeInterval(0.1)); end = now.addingTimeInterval(0.7)
    case "缩放": feedback.beginResize(at: now); end = now.addingTimeInterval(0.5)
    case "休息提醒": feedback.react(.rest, at: now); end = now.addingTimeInterval(0.5)
    default: break
    }
    view.now = end
    return view
}

func runPresentationTests() -> Bool {
    let now = Date()
    let view = previewScene("安静", now: now)
    let visible = view.visibleText()
    let numericOnly = visible.count == 1 && visible[0].range(of: "^[0-9,]+｜[0-9]+/min$", options: .regularExpression) != nil
    let noTooltip = view.toolTip == nil
    let fast = previewScene("快速打字", now: now)
    let deletes = previewScene("连续删除", now: now)
    let speaks = fast.visibleText().count == 2 && deletes.visibleText().count == 2
    let expired = fast.feedback.visibleSpeech(at: now.addingTimeInterval(30)) == nil
    let sameGeometry = view.bounds.size == ScreenSizing.baseSize
    let results = [numericOnly, noTooltip, speaks, expired, sameGeometry]
    print("Presentation tests: \(results.filter { $0 }.count)/\(results.count) passed")
    return results.allSatisfy { $0 }
}

func runInputConnectionPresentationTests() -> Bool {
    let model = CounterModel(), view = PetView(model: CounterModel())
    let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = view
    var requests = 0
    view.onConnectInput = { requests += 1 }
    let location = view.convert(NSPoint(x: 132, y: 212), to: nil)
    let click = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    var results = [view.needsInputHelp, view.visibleText().count == 1]
    view.mouseDown(with: click)
    results.append(requests == 1 && !view.isInteracting && view.feedback.interaction == .none)
    view.globalAvailable = true; results.append(!view.needsInputHelp)
    view.mouseDown(with: click)
    results.append(requests == 1 && view.feedback.interaction == .pressed)
    view.mouseUp(with: click)
    view.secureInput = true; view.mouseDown(with: click)
    results.append(requests == 2 && view.needsInputHelp)
    view.secureInput = false; view.model.setPaused(true); view.mouseDown(with: click)
    results.append(requests == 3 && view.needsInputHelp)
    view.demo = true; results.append(!view.needsInputHelp)
    results.append(model.todayCount == 0 && view.model.todayCount == 0)
    print("Input connection UI tests: \(results.filter { $0 }.count)/\(results.count) passed")
    return results.allSatisfy { $0 }
}

func runPressIntegrationTests() -> Bool {
    let domain = "local.qiaoqiao.press-test.\(UUID().uuidString)"
    let settings = UserDefaults(suiteName: domain)!
    let now = Date()
    let saved = SavedCounter(day: CounterModel.dayKey(now, calendar: .autoupdatingCurrent), count: 0, sleepSeconds: 60, lifetimeCount: 0)
    settings.set(try! JSONEncoder().encode(saved), forKey: "counter")
    settings.set(InputCountingRule.keyAndMouseButtons.rawValue, forKey: "inputCountingRule")
    let controller = AppController(settings: settings)
    controller.panel = CompanionPanel(contentRect: NSRect(origin: .zero, size: PetView.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    controller.pet = PetView(model: controller.model, feedback: controller.feedback, wardrobe: controller.wardrobe)
    controller.panel.contentView = controller.pet
    var results: [Bool] = []
    controller.accept(code: 0)
    results.append(controller.model.todayCount == 1)
    for _ in 0..<20 { controller.accept(code: 0, repeated: true) }
    results.append(controller.model.todayCount == 1)
    controller.accept(code: 51); controller.accept(code: 51)
    results.append(controller.model.todayCount == 3)
    controller.modifierFilter.reset(flags: 0)
    controller.acceptModifier(code: 56, flags: 0x20002)
    controller.acceptModifier(code: 56, flags: 0x20002)
    results.append(controller.model.todayCount == 4)
    controller.acceptModifier(code: 56, flags: 0)
    results.append(controller.model.todayCount == 4)
    controller.acceptModifier(code: 55, flags: 0x100008)
    controller.accept(code: 8, command: true)
    controller.acceptModifier(code: 55, flags: 0)
    results.append(controller.model.todayCount == 6)
    controller.acceptPointer(.movement, dx: 1000, dy: 0, momentum: false)
    controller.acceptPointer(.scroll, dx: 0, dy: 100, momentum: false)
    results.append(controller.model.todayCount == 6 && controller.model.mood() == .typing && controller.rest.lastActivity != nil)
    controller.acceptPointer(.click, dx: 0, dy: 0, momentum: false)
    results.append(controller.model.todayCount == 7)
    settings.set(InputCountingRule.keyboardOnly.rawValue, forKey: "inputCountingRule")
    controller.acceptPointer(.click, dx: 0, dy: 0, momentum: false)
    results.append(controller.model.todayCount == 7)
    controller.accept(code: 49)
    results.append(controller.pet.counterText == "8｜8/min")
    results.append(controller.model.lifetimeCount == 8 && controller.model.pressSerial == 8)
    results.append(controller.wardrobe.total == 8)
    settings.removePersistentDomain(forName: domain)
    print("Physical press integration tests: \(results.filter { $0 }.count)/\(results.count) passed")
    return results.allSatisfy { $0 }
}

let args = CommandLine.arguments
if args.contains("--self-test") {
    let counterPassed = runModelTests()
    let sizingPassed = runSizingTests()
    let feedbackPassed = runFeedbackTests()
    let wardrobePassed = runWardrobeTests()
    let activityPassed = runActivityTests()
    let remindersPassed = runReminderTests()
    let animationPassed = runCelAnimationTests()
    let pressesPassed = runPressInputTests()
    exit(counterPassed && sizingPassed && feedbackPassed && wardrobePassed && activityPassed && remindersPassed && animationPassed && pressesPassed ? 0 : 1)
}

let application = NSApplication.shared
application.appearance = NSAppearance(named: .aqua)

if let index = args.firstIndex(of: "--response-test"), args.count > index + 1 {
    let probe = ResponseProbe(directory: args[index + 1])
    application.delegate = probe
    application.run()
    exit(probe.passed ? 0 : 1)
}

if args.contains("--presentation-test") {
    let base = runPresentationTests(), reminders = runReminderPresentationTests(), art = runCelAssetTests(), rig = runOutfitRigTests(), connection = runInputConnectionPresentationTests()
    let sleep = runSleepTransitionTests()
    let presses = runPressIntegrationTests()
    exit(base && reminders && art && rig && connection && sleep && presses ? 0 : 1)
}

if let index = args.firstIndex(of: "--render-sleep"), args.count > index + 1 {
    do { try exportSleepAnimation(to: args[index + 1]); exit(0) }
    catch { print("Sleep export failed: \(error)"); exit(1) }
}

if let index = args.firstIndex(of: "--render-outfit-review"), args.count > index + 1 {
    do { try exportOutfitReview(to: args[index + 1]); exit(0) }
    catch { print("Outfit review failed: \(error)"); exit(1) }
}

if let index = args.firstIndex(of: "--render-animation"), args.count > index + 1 {
    do { try exportCelAnimation(to: args[index + 1]); exit(0) }
    catch { print("Cel export failed: \(error)"); exit(1) }
}

if let index = args.firstIndex(of: "--render-reminders"), args.count > index + 1 {
    do { try exportReminderPreviews(to: args[index + 1]); exit(0) }
    catch { print("Reminder preview failed: \(error)"); exit(1) }
}

if let index = args.firstIndex(of: "--render-wardrobe"), args.count > index + 1 {
    do { try exportWardrobe(to: args[index + 1]); exit(0) }
    catch { print("Wardrobe export failed: \(error)"); exit(1) }
}

if let index = args.firstIndex(of: "--render-previews"), args.count > index + 1 {
    let directory = args[index + 1]
    try! FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    for scene in ["安静", "正在打字", "快速打字", "连续删除", "开始犯困", "睡着啦", "被提起", "摸摸", "缩放", "休息提醒"] {
        let view = previewScene(scene, now: Date())
        let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        renderPreview(view, to: directory + "/" + scene + ".png")
    }
    print("Previews rendered to \(directory)")
    exit(0)
}

let controller = AppController()
application.delegate = controller
application.run()
