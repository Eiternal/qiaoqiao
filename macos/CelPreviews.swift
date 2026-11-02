import AppKit
import ImageIO
import UniformTypeIdentifiers

private final class CelContactView:NSView {
    let pets:[PetView]
    override var isFlipped:Bool{true}
    init() {
        pets=CelState.allCases.map{ state in
            let time=Date(timeIntervalSince1970:1800000000)
            let m=CounterModel(now:time,saved:SavedCounter(day:CounterModel.dayKey(time,calendar:.autoupdatingCurrent),count:1268,sleepSeconds:60))
            let v=PetView(model:m);v.now=time;v.previewCel=(state,0);v.showsSpeech=false;v.demo=true;return v
        }
        super.init(frame:NSRect(x:0,y:0,width:864,height:702))
        for (i,pet) in pets.enumerated() {
            let x=CGFloat(i%4)*216,y=CGFloat(i/4)*234
            pet.frame=NSRect(x:x+3,y:y+35,width:210,height:188);pet.bounds=NSRect(origin:.zero,size:PetView.size);addSubview(pet)
        }
    }
    required init?(coder:NSCoder){fatalError()}
    func setTime(_ time:Double){for (i,p) in pets.enumerated(){p.previewCel=(CelState.allCases[i],time);p.now=Date(timeIntervalSince1970:1800000000+time);p.needsDisplay=true};needsDisplay=true}
    override func draw(_ dirtyRect:NSRect){
        OutfitRenderer.color(0xF8F3ED).setFill();bounds.fill()
        for(i,state)in CelState.allCases.enumerated(){let x=CGFloat(i%4)*216,y=CGFloat(i/4)*234
            let card=NSBezierPath(roundedRect:NSRect(x:x+6,y:y+6,width:204,height:222),xRadius:17,yRadius:17)
            OutfitRenderer.color(0xFFFCF8).setFill();card.fill()
            let p=NSMutableParagraphStyle();p.alignment = .center
            (state.title as NSString).draw(in:NSRect(x:x+12,y:y+17,width:192,height:21),withAttributes:[.font:NSFont.systemFont(ofSize:13,weight:.medium),.foregroundColor:OutfitRenderer.color(0x8D705C),.paragraphStyle:p])
        }
    }
}

func exportCelAnimation(to directory:String)throws {
    let url=URL(fileURLWithPath:directory);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
    let view=CelContactView(),window=NSWindow(contentRect:view.bounds,styleMask:.borderless,backing:.buffered,defer:false)
    window.contentView=view
    let gif=url.appendingPathComponent("动作总览.gif")
    let total=72
    let dest=CGImageDestinationCreateWithURL(gif as CFURL,UTType.gif.identifier as CFString,total,nil)!
    CGImageDestinationSetProperties(dest,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
    for frame in 0..<total {
        view.setTime(Double(frame)/24);view.display();view.layoutSubtreeIfNeeded()
        guard let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{continue}
        view.cacheDisplay(in:view.bounds,to:rep)
        guard let image=rep.cgImage else{continue}
        CGImageDestinationAddImage(dest,image,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:1.0/24,kCGImagePropertyGIFUnclampedDelayTime:1.0/24]] as CFDictionary)
        if frame==12 {try rep.representation(using:.png,properties:[:])!.write(to:url.appendingPathComponent("动作总览.png"))}
    }
    guard CGImageDestinationFinalize(dest) else{throw NSError(domain:"CelExport",code:1,userInfo:[NSLocalizedDescriptionKey:"GIF export failed"])}
    print("Actual PetView animation preview exported: \(gif.path)")
}

private func sleepPreviewSession(seconds: TimeInterval) -> (CounterModel, FeedbackModel, PetView, NSWindow, Date) {
    let began = Date(timeIntervalSince1970: 1_800_000_000)
    let saved = SavedCounter(day: CounterModel.dayKey(began, calendar: .autoupdatingCurrent), count: 0, sleepSeconds: seconds)
    let model = CounterModel(now: began, saved: saved), feedback = FeedbackModel()
    let view = PetView(model: model, feedback: feedback)
    view.demo = true; view.globalAvailable = true; view.now = began
    view.previewOutfit = OutfitCatalog.all[12]
    let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = view
    feedback.observe(mood: .awake, at: began)
    return (model, feedback, view, window, began)
}

/// Runs the actual idle clock, feedback state and NSView drawing together.
/// Long samples catch a return to nodding after the initial sleep transition.
func runSleepTransitionTests() -> Bool {
    var checks = 0, failures: [String] = []
    func check(_ value: Bool, _ message: String) { checks += 1; if !value { failures.append(message) } }
    for seconds in [30.0, 60, 120] {
        let (model, feedback, view, window, began) = sleepPreviewSession(seconds: seconds)
        var drawn: (CelState, Int)?
        view.onDraw = { state, cel in drawn = (state, cel) }
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        func sample(_ idle: Double) -> (CelState, Int)? {
            view.now = began.addingTimeInterval(idle)
            feedback.observe(mood: model.mood(at: view.now), at: view.now)
            view.cacheDisplay(in: view.bounds, to: rep)
            return drawn
        }
        check(sample(seconds - 5.01)?.0 == .idle, "\(seconds)s setting stays awake until the brief lead-in")
        let first = sample(seconds - 5)
        check(first?.0 == .drowsy && first?.1 == 0, "\(seconds)s setting begins a single drowsy action")
        let nod = sample(seconds - 0.01)
        check(nod?.0 == .drowsy && nod?.1 == 1, "\(seconds)s drowsiness ends head-down")
        let asleep = sample(seconds)
        check(asleep?.0 == .sleeping && asleep?.1 == 1, "\(seconds)s deadline actually closes eyes")
        check([1.0, 60, 3600].allSatisfy { delta in let value = sample(seconds + delta); return value?.0 == .sleeping && value?.1 == 1 }, "\(seconds)s sleeping never returns to a yawn or raised head")
        check(model.todayCount == 0, "idle and breathing cannot manufacture inputs")
        let wake = began.addingTimeInterval(seconds + 3601)
        let previous = model.mood(at: wake)
        let counted = model.recordKeyboardInput(keyCode: 0, at: wake)
        feedback.key(code: 0, repeated: false, counted: counted, previousMood: previous, at: wake)
        let awake = sample(seconds + 3601)
        check(awake?.0 == .typing && awake?.1 == 1 && model.todayCount == 1, "\(seconds)s real input immediately wakes and taps")
        window.orderOut(nil)
    }
    print("Sleep transition tests: \(checks - failures.count)/\(checks) passed")
    failures.forEach { print("FAIL: \($0)") }
    return failures.isEmpty
}

func exportSleepAnimation(to directory: String) throws {
    let root = URL(fileURLWithPath: directory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let (model, feedback, view, window, began) = sleepPreviewSession(seconds: 30)
    let frames = 288
    let gif = root.appendingPathComponent("入睡过程.gif")
    let destination = CGImageDestinationCreateWithURL(gif as CFURL, UTType.gif.identifier as CFString, frames, nil)!
    // No loop extension: play once, then leave the final settled sleep on screen.
    var timeline: [[String: Any]] = []
    var drawn: (CelState, Int)?
    view.onDraw = { state, cel in drawn = (state, cel) }
    for index in 0..<frames {
        let time = Double(index) / 24
        view.now = began.addingTimeInterval(24 + time)
        let mood = model.mood(at: view.now)
        feedback.observe(mood: mood, at: view.now)
        // Each transparent frame needs a clean bitmap, otherwise previous
        // poses remain underneath and produce a trail in the exported GIF.
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        // An opaque preview background also avoids GIF disposal artifacts in
        // players. This only affects the export, not the transparent desktop pet.
        let canvas = CGContext(data: nil, width: rep.pixelsWide, height: rep.pixelsHigh, bitsPerComponent: 8, bytesPerRow: rep.pixelsWide * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let canvasRect = CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh)
        canvas.setFillColor(OutfitRenderer.color(0xF8F3ED).cgColor); canvas.fill(canvasRect)
        canvas.draw(rep.cgImage!, in: canvasRect)
        let output = canvas.makeImage()!
        // GIF delays are whole centiseconds: six drawings occupy exactly 0.25s.
        let delay = index % 6 == 5 ? 0.05 : 0.04
        CGImageDestinationAddImage(destination, output, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
        timeline.append(["time": time, "idleSeconds": 24 + time, "mood": mood.rawValue, "drawnState": drawn?.0.rawValue ?? "missing", "cel": drawn?.1 ?? -1])
        if let tag = [0: "清醒", 67: "困倦", 168: "睡着"][index] {
            try NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(tag + ".png"))
        }
    }
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "SleepExport", code: 1) }
    try JSONSerialization.data(withJSONObject: timeline, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("入睡时间线.json"))
    window.orderOut(nil)
    print("Sleep transition exported: 1s awake, 5s drowsy, 6s settled sleep; \(frames) actual PetView frames; no GIF loop.")
}
