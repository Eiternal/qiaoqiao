import AppKit
import ImageIO
import UniformTypeIdentifiers
struct Component { var points:[Int]; var bounds:[Int]; var cx:Double { Double(bounds[0]+bounds[2])/2 }; var cy:Double { Double(bounds[1]+bounds[3])/2 } }
struct FrameInfo:Codable { let state:String, frame:Int, file:String, sourceBounds:[Int], width:Int, height:Int; let registrationOffset:[Double] }
let root=URL(fileURLWithPath:CommandLine.arguments[1])
let atlases=[("打字与表情.png",["idle","typing","fast","deleting"]),("睡眠与拖动.png",["drowsy","sleeping","waking","dragging"]),("互动与提醒.png",["petting","resizing","rest","reminder"])]
var metadata:[FrameInfo]=[]
for (sheet,states) in atlases {
 let im=CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(root.appendingPathComponent(sheet) as CFURL,nil)!,0,nil)!, w=im.width,h=im.height
 var px=[UInt8](repeating:0,count:w*h*4)
 px.withUnsafeMutableBytes { let c=CGContext(data:$0.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!;c.draw(im,in:CGRect(x:0,y:0,width:w,height:h)) }
 var labels=[Int](repeating:-1,count:w*h),components:[Component]=[]
 for a in 0..<(w*h) where labels[a]<0 && px[a*4+3]>=24 {
  let label=components.count;var q=[a],i=0,x0=w,y0=h,x1=0,y1=0;labels[a]=label
  while i<q.count {let v=q[i];i+=1;let x=v%w,y=v/w;x0=min(x0,x);x1=max(x1,x);y0=min(y0,y);y1=max(y1,y)
   for(dx,dy)in[(-1,0),(1,0),(0,-1),(0,1)] {let xx=x+dx,yy=y+dy;if xx<0||yy<0||xx>=w||yy>=h{continue};let n=yy*w+xx;if labels[n]<0 && px[n*4+3]>=24{labels[n]=label;q.append(n)}}
  }
  components.append(Component(points:q,bounds:[x0,y0,x1,y1]))
 }
 let mains=components.indices.filter{components[$0].points.count>10000}.sorted{components[$0].cy<components[$1].cy}
 precondition(mains.count==16,"Expected 16 isolated character silhouettes in \(sheet), got \(mains.count)")
 var ordered:[Int]=[]
 for row in 0..<4 {ordered += mains[(row*4)..<(row*4+4)].sorted{components[$0].cx<components[$1].cx}}
 var owner=[Int:Int]()
 for (i,component) in components.enumerated() where component.points.count>=18 {
  owner[i] = mains.contains(i) ? i : mains.min { a,b in
   func distance(_ k:Int)->Double {let m=components[k];let dx=max(Double(m.bounds[0])-component.cx,0,component.cx-Double(m.bounds[2]));let dy=max(Double(m.bounds[1])-component.cy,0,component.cy-Double(m.bounds[3]));return dx*dx+dy*dy}
   return distance(a)<distance(b)
  }
 }
 for row in 0..<4 {
  let group=Array(ordered[(row*4)..<(row*4+4)]), widths=group.map{components[$0].bounds[2]-components[$0].bounds[0]+1}.sorted()
  let tallest=group.map{components[$0].bounds[3]-components[$0].bounds[1]+1}.max()!
  let scale=min(310/Double(widths[1]),282/Double(tallest))
  for col in 0..<4 {
   let main=group[col], body=components[main],b=body.bounds
   let chosen=components.indices.filter{owner[$0]==main}
   let x0=max(0,chosen.map{components[$0].bounds[0]}.min()!-2),y0=max(0,chosen.map{components[$0].bounds[1]}.min()!-2)
   let x1=min(w-1,chosen.map{components[$0].bounds[2]}.max()!+2),y1=min(h-1,chosen.map{components[$0].bounds[3]}.max()!+2),cw=x1-x0+1,ch=y1-y0+1
   var centers:[Double]=[]
   for y in (b[1]+Int(Double(b[3]-b[1])*0.35))...(b[1]+Int(Double(b[3]-b[1])*0.55)) {
    let xs=(b[0]...b[2]).filter{labels[y*w+$0]==main && px[(y*w+$0)*4+3]>160}
    if let a=xs.first,let z=xs.last {centers.append(Double(a+z)/2)}
   }
   centers.sort();let headX=centers.isEmpty ? body.cx : centers[centers.count/2]
   let dx=172-(headX-Double(x0))*scale,dy=322-Double(b[3]+1-y0)*scale
   var data=[UInt8](repeating:0,count:cw*ch*4)
   for y in y0...y1 {for x in x0...x1 {
    let n=y*w+x,l=labels[n];var belongs=l>=0 && owner[l]==main
    if !belongs && px[n*4+3]>4 {for yy in max(0,y-1)...min(h-1,y+1){for xx in max(0,x-1)...min(w-1,x+1){let k=labels[yy*w+xx];if k>=0 && owner[k]==main{belongs=true}}}}
    if belongs {let dst=((y-y0)*cw+x-x0)*4;for c in 0..<4{data[dst+c]=px[n*4+c]}}
   }}
   let provider=CGDataProvider(data:Data(data) as CFData)!,cel=CGImage(width:cw,height:ch,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:cw*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent)!
   let output=CGContext(data:nil,width:360,height:340,bitsPerComponent:8,bytesPerRow:1440,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
   output.interpolationQuality = .high;output.draw(cel,in:CGRect(x:dx,y:340-dy-Double(ch)*scale,width:Double(cw)*scale,height:Double(ch)*scale))
   let file="\(states[row])_\(col).png",url=root.appendingPathComponent("Frames/"+file)
   let dest=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!
   CGImageDestinationAddImage(dest,output.makeImage()!,nil);precondition(CGImageDestinationFinalize(dest))
   metadata.append(FrameInfo(state:states[row],frame:col,file:file,sourceBounds:b,width:360,height:340,registrationOffset:[dx,dy]))
  }
 }
 print("Prepared \(sheet): 16 complete, registered cels")
}
let enc=JSONEncoder();enc.outputFormatting=[.prettyPrinted,.sortedKeys];try enc.encode(metadata).write(to:root.appendingPathComponent("Frames/manifest.json"))
