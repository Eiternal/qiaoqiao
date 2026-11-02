import AppKit

/// The same warm ink weight and fine pigment grain as the raster character.
/// Layers are cached once per design; texture is never regenerated on each tick.
enum OutfitPaint {
    static let cocoa = OutfitRenderer.color(0x70472F)
    private static let grain: CGImage = {
        let size=512;var bytes=[UInt8](repeating:0,count:size*size*4)
        var seed:UInt32=0x51A7C0DE
        for i in 0..<(size*size) {
            seed ^= seed << 13;seed ^= seed >> 17;seed ^= seed << 5
            let v=UInt8(60+seed%150)
            bytes[i*4]=v;bytes[i*4+1]=v;bytes[i*4+2]=v;bytes[i*4+3]=255
        }
        let data=CGDataProvider(data:Data(bytes) as CFData)!
        return CGImage(width:size,height:size,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:size*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:data,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
    }()
    static func fill(_ path:NSBezierPath,_ fill:NSColor,stroke:NSColor?=nil,width:CGFloat=1.8) {
        let alpha=fill.alphaComponent
        if alpha>0.001 {
            fill.setFill();path.fill()
            if alpha>0.3,let ctx=NSGraphicsContext.current?.cgContext {
                NSGraphicsContext.saveGraphicsState();path.addClip()
                ctx.setBlendMode(.softLight);ctx.setAlpha(0.31*alpha)
                ctx.draw(grain,in:CGRect(x:0,y:0,width:256,height:256))
                NSGraphicsContext.restoreGraphicsState()
                // A quiet highlight gives cloth volume without a hard vector bevel.
                NSGraphicsContext.saveGraphicsState();path.addClip()
                let b=path.bounds
                let highlight=NSBezierPath();highlight.move(to:NSPoint(x:b.minX-2,y:b.minY+b.height*0.29));highlight.curve(to:NSPoint(x:b.maxX+2,y:b.minY+b.height*0.23),controlPoint1:NSPoint(x:b.midX-b.width*0.2,y:b.minY+b.height*0.06),controlPoint2:NSPoint(x:b.midX+b.width*0.1,y:b.minY+b.height*0.15));highlight.lineWidth=max(1,b.height*0.08);highlight.lineCapStyle = .round
                NSColor.white.withAlphaComponent(0.13*alpha).setStroke();highlight.stroke();NSGraphicsContext.restoreGraphicsState()
            }
        }
        guard stroke != nil || alpha>0.45 else{return}
        let color=stroke.flatMap{$0.blended(withFraction:0.48,of:cocoa)} ?? cocoa
        outline(path,color:color.withAlphaComponent(stroke == nil ? 0.90 : max(0.72,color.alphaComponent)),width:max(1.35,width))
    }
    static func outline(_ original:NSBezierPath,color:NSColor,width:CGFloat) {
        let path=original.copy() as! NSBezierPath;path.flatness=0.25
        let flat=path.flattened
        var paths:[[NSPoint]]=[],points:[NSPoint]=[]
        var associated=[NSPoint](repeating:.zero,count:3)
        for index in 0..<flat.elementCount {
            let kind=associated.withUnsafeMutableBufferPointer {flat.element(at:index,associatedPoints:$0.baseAddress!)}
            switch kind {
            case .moveTo: if points.count>1{paths.append(points)};points=[associated[0]]
            case .lineTo:
                if let last=points.last {let p=associated[0],distance=hypot(p.x-last.x,p.y-last.y),steps=max(1,Int(ceil(distance/2.3)))
                    for i in 1...steps {let u=CGFloat(i)/CGFloat(steps);points.append(NSPoint(x:last.x+(p.x-last.x)*u,y:last.y+(p.y-last.y)*u))}}
            case .closePath: if let first=points.first{points.append(first)};if points.count>1{paths.append(points)};points=[]
            default: break
            }
        }
        if points.count>1{paths.append(points)}
        for line in paths {
            var left:[NSPoint]=[],right:[NSPoint]=[]
            let b=original.bounds,seed=Double(b.minX*0.7+b.minY*1.1+b.width*0.3)
            for i in line.indices {
                let a=line[max(0,i-1)],z=line[min(line.count-1,i+1)],p=line[i]
                let len=max(0.001,hypot(z.x-a.x,z.y-a.y)),nx = -(z.y-a.y)/len,ny=(z.x-a.x)/len
                let wobble=CGFloat(sin(Double(i)*0.73+seed))*0.20
                let half=width*(0.48+0.08*CGFloat(sin(Double(i)*0.4+seed)))
                left.append(NSPoint(x:p.x+nx*(half+wobble),y:p.y+ny*(half+wobble)))
                right.append(NSPoint(x:p.x-nx*(half-wobble),y:p.y-ny*(half-wobble)))
            }
            guard let first=left.first else{continue};let p=NSBezierPath();p.move(to:first)
            (Array(left.dropFirst())+Array(right.reversed())).forEach{p.line(to:$0)};p.close();color.setFill();p.fill()
        }
    }
}

enum OutfitLayer: String {case behind,hat,face}
enum OutfitLayers {
    private static let behindStyles: Set<OutfitStyle> = [.antlers,.reindeer,.devil,.halo,.bee,.butterfly,.dragon,.aurora,.astronaut,.knight,.ghost,.elf]
    private static let faceStyles: Set<OutfitStyle> = [.sunglasses,.glasses,.cyber,.steampunk,.mask,.pirate,.fox,.dragon]
    private static let cache:NSCache<NSString,NSImage> = {
        let value=NSCache<NSString,NSImage>();value.totalCostLimit=32*1024*1024;value.countLimit=48;return value
    }()
    static func image(_ outfit:Outfit,_ layer:OutfitLayer)->NSImage {
        let key="\(outfit.id)-\(layer.rawValue)"
        if let image=cache.object(forKey:key as NSString){return image}
        let ctx=CGContext(data:nil,width:528,height:472,bitsPerComponent:8,bytesPerRow:528*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x:0,y:472);ctx.scaleBy(x:2,y:-2)
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:ctx,flipped:true)
        switch layer {
        case .behind:OutfitRenderer.drawBehind(outfit)
        case .hat:OutfitRenderer.drawHeadwear(outfit)
        case .face:OutfitRenderer.drawFace(outfit)
        }
        NSGraphicsContext.restoreGraphicsState()
        let image=NSImage(cgImage:ctx.makeImage()!,size:NSSize(width:264,height:236));cache.setObject(image,forKey:key as NSString,cost:528*472*4);return image
    }
    private static func supports(_ outfit: Outfit, _ layer: OutfitLayer) -> Bool {
        switch layer {
        case .behind: return behindStyles.contains(outfit.style)
        case .face: return faceStyles.contains(outfit.style)
        case .hat: return outfit.style != .glasses && outfit.style != .sunglasses
        }
    }
    static func preload(_ outfit: Outfit) {
        for layer in [OutfitLayer.behind, .hat, .face] where supports(outfit, layer) { _ = image(outfit, layer) }
    }
    static func draw(_ outfit:Outfit,_ layer:OutfitLayer) {
        guard supports(outfit, layer) else { return }
        image(outfit,layer).draw(in:NSRect(x:0,y:0,width:264,height:236),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
    }
}
