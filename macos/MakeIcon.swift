import AppKit
@main struct MakeIcon {
 static func main() throws {
  let output=URL(fileURLWithPath:CommandLine.arguments[1])
  let path=CommandLine.arguments.count>2 ? CommandLine.arguments[2] : URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Assets/Frames/idle_0.png").path
  guard let art=NSImage(contentsOfFile:path) else{throw NSError(domain:"MakeIcon",code:1)}
  try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
  let sizes=[(16,"icon_16x16.png"),(32,"icon_16x16@2x.png"),(32,"icon_32x32.png"),(64,"icon_32x32@2x.png"),(128,"icon_128x128.png"),(256,"icon_128x128@2x.png"),(256,"icon_256x256.png"),(512,"icon_256x256@2x.png"),(512,"icon_512x512.png"),(1024,"icon_512x512@2x.png")]
  for(pixels,name)in sizes {
   let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
   NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
   let t=NSAffineTransform();t.scale(by:CGFloat(pixels)/256);t.concat()
   NSColor(srgbRed:0.96,green:0.90,blue:0.81,alpha:1).setFill();NSBezierPath(roundedRect:NSRect(x:15,y:15,width:226,height:226),xRadius:52,yRadius:52).fill()
   art.draw(in:NSRect(x:18,y:21,width:220,height:208),from:.zero,operation:.sourceOver,fraction:1)
   NSGraphicsContext.restoreGraphicsState();try rep.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name))
  }
 }
}
