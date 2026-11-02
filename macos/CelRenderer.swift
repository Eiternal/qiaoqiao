import AppKit
import ImageIO

enum CelAssets {
    static let directory: URL = {
        if let resources=Bundle.main.resourceURL, FileManager.default.fileExists(atPath:resources.appendingPathComponent("StarCels/idle_0.png").path) {return resources.appendingPathComponent("StarCels")}
        return URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Assets/Frames")
    }()
    private static var images:[String:NSImage]=[:]
    static func image(_ state:CelState,_ cel:Int)->NSImage? {
        let key="\(state.rawValue)_\(cel)"
        if let image=images[key]{return image}
        guard let source = CGImageSourceCreateWithURL(directory.appendingPathComponent(key+".png") as CFURL, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: decoded, size: NSSize(width: decoded.width, height: decoded.height))
        images[key]=image;return image
    }
    static func preload() {
        for state in CelState.allCases { for cel in 0..<4 { _ = image(state, cel) } }
    }
}

/// Seeded pressure strokes for the FX layer: centreline -> tapered outline.
/// Technique adapted from mg-styles-15's MIT cel-brush reference; the character
/// itself is image-generated cel art. No global camera jitter is used as boil.
enum CelBrush {
    static func stroke(_ points:[NSPoint],width:CGFloat,color:NSColor,seed:Int) {
        guard points.count>1 else{return}
        var left:[NSPoint]=[],right:[NSPoint]=[]
        for i in points.indices {
            let a=points[max(0,i-1)],b=points[min(points.count-1,i+1)],p=points[i]
            let length=max(0.001,hypot(b.x-a.x,b.y-a.y)),nx = -(b.y-a.y)/length,ny=(b.x-a.x)/length
            let u=CGFloat(i)/CGFloat(points.count-1),pressure=0.42+0.58*sin(.pi*u)
            let jitter=CGFloat(sin(Double(seed*29+i*13))*0.35),half=width*pressure/2
            left.append(NSPoint(x:p.x+nx*(half+jitter),y:p.y+ny*(half+jitter)))
            right.append(NSPoint(x:p.x-nx*(half-jitter),y:p.y-ny*(half-jitter)))
        }
        let path=NSBezierPath();path.move(to:left[0]);(Array(left.dropFirst())+right.reversed()).forEach{path.line(to:$0)};path.close();color.setFill();path.fill()
    }
    static func arc(_ center:NSPoint,radius:CGFloat,from:Double,to:Double,seed:Int,color:NSColor,width:CGFloat=1.8) {
        stroke((0...16).map { i in let a=from+(to-from)*Double(i)/16;return NSPoint(x:center.x+CGFloat(cos(a))*radius,y:center.y+CGFloat(sin(a))*radius)},width:width,color:color,seed:seed)
    }
}

enum CelRenderer {
    static let imageRect=NSRect(x:36,y:32,width:200,height:160)
    private static let gold=OutfitRenderer.color(0xDCAD50)
    private static let ink=OutfitRenderer.color(0xA57C5D)
    static func draw(state:CelState,cel:Int,elapsed:Double,pose:PetReaction?,feedback:FeedbackModel,outfit:Outfit?,wardrobe:WardrobeModel?,now:Date,reduced:Bool) {
        let step=reduced ? 0 : floor(elapsed*12)/12
        NSGraphicsContext.saveGraphicsState()
        let t=NSAffineTransform();t.translateX(by:132,yBy:182)
        if pose == .pressed {t.scaleX(by:1.045,yBy:0.94)}
        if !reduced && state == .sleeping {
            let phase = max(0, elapsed).truncatingRemainder(dividingBy: 4.8) / 4.8 * 2 * Double.pi
            let breath = CGFloat((1 - cos(phase)) / 2)
            // Less than 1.3 logical points of expansion, anchored at the paws.
            // Costume and sprite share this transform, so both breathe together.
            t.scaleX(by: 1 + 0.003 * breath, yBy: 1 + 0.008 * breath)
        } else if !reduced && state != .dragging {
            let angle=(feedback.hovered ? CGFloat((feedback.lookX*2).rounded())*0.45 : 0)
            t.rotate(byDegrees:angle)
            if state == .petting && elapsed<0.18 {let q=CGFloat(sin(min(1,step/0.18)*Double.pi));t.scaleX(by:1+0.025*q,yBy:1-0.025*q)}
        }
        t.translateX(by:-132,yBy:-182);t.concat()
        if feedback.hovered || state == .resizing {
            OutfitRenderer.color(0xE6CB9E,alpha:0.13).setFill();NSBezierPath(ovalIn:NSRect(x:56,y:61,width:152,height:123)).fill()
        }
        let rig = OutfitRig.frame(state, cel)
        if let outfit=outfit {
            NSGraphicsContext.saveGraphicsState();NSBezierPath(rect:NSRect(x:18,y:43,width:228,height:144)).addClip()
            rig.withHead {OutfitLayers.draw(outfit,.behind)};NSGraphicsContext.restoreGraphicsState()
        }
        if let image=CelAssets.image(state,cel) {
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(in:imageRect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        }
        if let outfit=outfit {
            NSGraphicsContext.saveGraphicsState();NSBezierPath(rect:NSRect(x:18,y:43,width:228,height:144)).addClip()
            rig.withHead {OutfitLayers.draw(outfit,.hat)}
            if outfit.style == .astronaut {rig.withHead {OutfitLayers.draw(outfit,.face)}}
            else {rig.withFace {OutfitLayers.draw(outfit,.face)}}
            NSGraphicsContext.restoreGraphicsState()
            // This character has no exposed neck. A compulsory scarf/bib would
            // cover its moving paws and cup, so outfits use a single themed piece.
        }
        if !reduced {drawFX(state:state,cel:cel,tick:Int(floor(elapsed*24)),seed:Int(floor(elapsed*12))%4)}
        if let wardrobe=wardrobe {
            let age=now.timeIntervalSince(wardrobe.changedAt)
            if age>=0 && age<1.8 {
                let fade=CGFloat(1-age/1.8)
                for i in 0..<6 {let a=Double(i) * .pi/3+(reduced ? 0 : floor(age*12)/12*0.4);let r=CGFloat(75+age*8)
                    OutfitRenderer.star(132+CGFloat(cos(a))*r,122+CGFloat(sin(a))*r*0.7,radius:3+fade*2,fill:gold.withAlphaComponent(fade))}
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        if state == .sleeping { drawSleepSymbols(elapsed: elapsed, reduced: reduced) }
    }
    private static func drawSleepSymbols(elapsed: Double, reduced: Bool) {
        // Kept outside the body's breathing transform: the symbols drift up
        // gently, while the closed-eye sleeping pose stays settled.
        for i in 0..<3 {
            let phase = reduced ? 0.5 : (max(0, elapsed) / 3.2 + Double(i) * 0.23).truncatingRemainder(dividingBy: 1)
            let alpha = CGFloat(sin(phase * .pi)) * 0.82
            let x = CGFloat(211 + i * 13), y = CGFloat(109 - i * 21) - (reduced ? 0 : CGFloat(phase) * 6)
            let width = CGFloat(7 + i * 3), height = CGFloat(8 + i * 3)
            let points = [NSPoint(x: x, y: y), NSPoint(x: x + width, y: y), NSPoint(x: x, y: y + height), NSPoint(x: x + width, y: y + height)]
            // A quiet cream edge keeps the warm ink legible over the desktop.
            CelBrush.stroke(points, width: 3.4, color: OutfitRenderer.color(0xFFFAEF, alpha: alpha * 0.8), seed: i)
            CelBrush.stroke(points, width: 1.8, color: OutfitRenderer.color(0x98718C, alpha: alpha), seed: i)
        }
    }
    static func drawFX(state:CelState,cel:Int,tick:Int,seed:Int) {
        switch state {
        case .typing:
            if cel == 1 || cel == 3 {
                let x:CGFloat=cel == 1 ? 107 : 157
                for dx:CGFloat in [-7,0,7]{CelBrush.stroke([NSPoint(x:x+dx,y:188),NSPoint(x:x+dx*1.2,y:191),NSPoint(x:x+dx*1.4,y:193)],width:1.7,color:gold.withAlphaComponent(0.6),seed:seed)}
            }
        case .fast:
            for i in 0..<3 {let y=CGFloat(108+i*13);CelBrush.stroke([NSPoint(x:39,y:y),NSPoint(x:47,y:y-2+CGFloat(seed)*0.3),NSPoint(x:54,y:y-1)],width:2.2,color:gold.withAlphaComponent(0.8),seed:seed+i)}
        case .dragging:
            CelBrush.arc(NSPoint(x:132,y:178),radius:28,from:0.2,to:1.2,seed:seed,color:ink.withAlphaComponent(0.55))
        case .deleting:
            if cel == 1 || cel == 2 {let pts=(0...35).map{ i -> NSPoint in let a=Double(i) * .pi/8;let r=CGFloat(2+Double(i)*0.09);return NSPoint(x:220+CGFloat(cos(a))*r,y:85+CGFloat(sin(a))*r*0.55)};CelBrush.stroke(pts,width:1.5,color:ink.withAlphaComponent(0.6),seed:seed)}
        case .resizing:
            for i in 0..<3 {OutfitRenderer.star(CGFloat(49+i*78),CGFloat(i%2 == 0 ? 105 : 47)+CGFloat(seed),radius:3,fill:gold.withAlphaComponent(0.7))}
        case .rest:
            for i in 0..<2 {let x=CGFloat(119+i*13);CelBrush.stroke([NSPoint(x:x,y:157),NSPoint(x:x-2+CGFloat(seed),y:150),NSPoint(x:x+2,y:145)],width:1.4,color:ink.withAlphaComponent(0.35),seed:seed+i)}
        case .reminder:
            if cel == 1 || cel == 2 {for r:CGFloat in [9,15]{CelBrush.arc(NSPoint(x:70,y:143),radius:r,from:3.3,to:4.8,seed:seed,color:gold,width:1.8)}}
        default:break
        }
    }
}

@discardableResult
func runCelAssetTests()->Bool {
    var failures:[String]=[],n=0
    for state in CelState.allCases {for cel in 0..<4 {
        n+=1
        guard let image=CelAssets.image(state,cel),let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil),cg.width==360,cg.height==340 else{failures.append("missing or invalid \(state.rawValue)_\(cel)");continue}
        let rep=NSBitmapImageRep(cgImage:cg)
        let corners=[(0,0),(359,0),(0,339),(359,339)]
        if !rep.hasAlpha || !corners.allSatisfy({(rep.colorAt(x:$0.0,y:$0.1)?.alphaComponent ?? 1)<0.05}) {failures.append("bad transparent matte \(state.rawValue)_\(cel)")}
    }}
    print("Cel asset tests: \(n-failures.count)/\(n) passed");failures.forEach{print("FAIL: \($0)")};return failures.isEmpty
}
