import AppKit
import Foundation
import ImageIO
_ = NSApplication.shared
let root=URL(fileURLWithPath:CommandLine.arguments[1])
try FileManager.default.createDirectory(at:root.appendingPathComponent("outfits"),withIntermediateDirectories:true)
let behind:Set<OutfitStyle>=[.antlers,.reindeer,.devil,.halo,.bee,.butterfly,.dragon,.aurora,.astronaut,.knight,.ghost,.elf]
let face:Set<OutfitStyle>=[.sunglasses,.glasses,.cyber,.steampunk,.mask,.pirate,.fox,.dragon]
var outfits:[[String:Any]]=[]
for outfit in OutfitCatalog.all {
 var layers:[String]=[]
 for layer in [OutfitLayer.behind,.hat,.face] {
  let supported = layer == .behind ? behind.contains(outfit.style) : (layer == .face ? face.contains(outfit.style) : ![OutfitStyle.glasses,.sunglasses].contains(outfit.style))
  if !supported { continue }
  let image=OutfitLayers.image(outfit,layer)
  let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil)!
  let url=root.appendingPathComponent("outfits/\(outfit.id)-\(layer.rawValue).png")
  let out=CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil)!
  CGImageDestinationAddImage(out,cg,nil);precondition(CGImageDestinationFinalize(out))
  layers.append(layer.rawValue)
 }
 outfits.append(["id":outfit.id,"name":outfit.name,"theme":outfit.theme,"style":outfit.style.rawValue,"layers":layers])
}
var states:[String:Any]=[:]
for state in CelState.allCases {
 let rig=(0..<4).map { i -> [String:Any] in let r=OutfitRig.frame(state,i);return ["x":Double(r.eyes.x),"y":Double(r.eyes.y),"angle":Double(r.angle),"headScale":Double(r.headScale),"faceScale":Double(r.eyeDistance/54)] }
 states[state.rawValue] = ["exposures":state.exposures.map{[$0.cel,$0.ticks]},"loops":state.loops,"rig":rig]
}
let data:[String:Any] = ["outfits":outfits,"themes":OutfitCatalog.themes,"states":states,"width":264,"height":236]
try JSONSerialization.data(withJSONObject:data,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("catalog.json"))
print("Exported \(outfits.count) outfits, \(states.count) animation states")
