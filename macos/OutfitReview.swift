import AppKit
import ImageIO
import UniformTypeIdentifiers

private final class OutfitReviewView:NSView {
    let pets:[PetView]
    let outfits=[12,17,51,26,1,91]
    var state:CelState = .idle
    override var isFlipped:Bool{true}
    init(){
        pets=(0..<6).map{_ in let now=Date(timeIntervalSince1970:1800000000);let v=PetView(model:CounterModel(now:now));v.now=now;v.showsSpeech=false;v.previewCel=(.idle,0);return v}
        super.init(frame:NSRect(x:0,y:0,width:720,height:520))
        for(i,v)in pets.enumerated(){v.previewOutfit=OutfitCatalog.all[outfits[i]];v.frame=NSRect(x:CGFloat(i%3)*240+6,y:CGFloat(i/3)*260+30,width:228,height:204);v.bounds=NSRect(origin:.zero,size:PetView.size);addSubview(v)}
    }
    required init?(coder:NSCoder){fatalError()}
    func setTime(_ elapsed:Double){
        let states:[CelState]=[.idle,.typing,.sleeping,.dragging]
        state=states[min(3,Int(elapsed/2))]
        let phase=elapsed.truncatingRemainder(dividingBy:2)
        for pet in pets{pet.previewCel=(state,phase);pet.needsDisplay=true}
        needsDisplay=true
    }
    override func draw(_ rect:NSRect){
        OutfitRenderer.color(0xF6EFE5).setFill();bounds.fill()
        for i in 0..<6 {
            let x=CGFloat(i%3)*240,y=CGFloat(i/3)*260
            let card=NSBezierPath(roundedRect:NSRect(x:x+6,y:y+6,width:228,height:248),xRadius:17,yRadius:17);OutfitRenderer.color(0xFFFCF8).setFill();card.fill()
            let p=NSMutableParagraphStyle();p.alignment = .center
            ((OutfitCatalog.all[outfits[i]].name+" · "+state.title) as NSString).draw(in:NSRect(x:x+9,y:y+15,width:222,height:20),withAttributes:[.font:NSFont.systemFont(ofSize:12,weight:.medium),.foregroundColor:OutfitRenderer.color(0x755640),.paragraphStyle:p])
        }
    }
}
func exportOutfitReview(to directory:String)throws {
    let root=URL(fileURLWithPath:directory);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    let view=OutfitReviewView(),window=NSWindow(contentRect:view.bounds,styleMask:.borderless,backing:.buffered,defer:false);window.contentView=view
    let gif=root.appendingPathComponent("装扮动态适配.gif"),total=96
    let destination=CGImageDestinationCreateWithURL(gif as CFURL,UTType.gif.identifier as CFString,total,nil)!
    CGImageDestinationSetProperties(destination,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
    for i in 0..<total {
        view.setTime(Double(i)/12);view.display()
        let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:view.bounds,to:rep)
        let delay=i%3==2 ? 0.09 : 0.08
        CGImageDestinationAddImage(destination,rep.cgImage!,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:delay,kCGImagePropertyGIFUnclampedDelayTime:delay]] as CFDictionary)
        if [6,30,54,78].contains(i) {let tag=[6:"安静",30:"打字",54:"睡眠",78:"拖动"][i]!;try rep.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("装扮适配_"+tag+".png"))}
    }
    guard CGImageDestinationFinalize(destination) else{throw NSError(domain:"OutfitReview",code:1)}
    print("Outfit motion review exported: \(gif.path)")
}
