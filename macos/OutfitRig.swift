import AppKit

/// Authored against each registered raster cel. Coordinates are in the 360 x 340
/// source image, not the old avatar. All 48 landmarks were visually checked.
struct RigFrame {
    let left: CGPoint, right: CGPoint
    let headScale: CGFloat
    func pointInView(_ p:CGPoint)->CGPoint {
        CGPoint(x:CelRenderer.imageRect.minX+p.x*CelRenderer.imageRect.width/360,
                y:CelRenderer.imageRect.minY+p.y*CelRenderer.imageRect.height/340)
    }
    var eyes: CGPoint {let l=pointInView(left),r=pointInView(right);return CGPoint(x:(l.x+r.x)/2,y:(l.y+r.y)/2)}
    var angle: CGFloat {let l=pointInView(left),r=pointInView(right);return atan2(r.y-l.y,r.x-l.x)}
    var eyeDistance: CGFloat {let l=pointInView(left),r=pointInView(right);return hypot(r.x-l.x,r.y-l.y)}
    func withHead(_ draw:()->Void) {
        NSGraphicsContext.saveGraphicsState()
        let t=NSAffineTransform();t.translateX(by:eyes.x,yBy:eyes.y);t.rotate(byRadians:angle)
        t.scaleX(by:headScale,yBy:headScale);t.translateX(by:-132,yBy:-121);t.concat()
        draw();NSGraphicsContext.restoreGraphicsState()
    }
    func withFace(_ draw:()->Void) {
        NSGraphicsContext.saveGraphicsState()
        let t=NSAffineTransform();t.translateX(by:eyes.x,yBy:eyes.y);t.rotate(byRadians:angle)
        t.scaleX(by:eyeDistance/54,yBy:headScale);t.translateX(by:-132,yBy:-121);t.concat()
        draw();NSGraphicsContext.restoreGraphicsState()
    }
}
enum OutfitRig {
    static let frames:[CelState:[RigFrame]] = [
        .idle: [
            RigFrame(left: CGPoint(x: 129.5, y: 201.5), right: CGPoint(x: 207.5, y: 211.0), headScale: 1.00),
            RigFrame(left: CGPoint(x: 130.5, y: 201.0), right: CGPoint(x: 211.5, y: 209.5), headScale: 1.00),
            RigFrame(left: CGPoint(x: 128.0, y: 204.0), right: CGPoint(x: 212.5, y: 210.0), headScale: 1.00),
            RigFrame(left: CGPoint(x: 132.5, y: 204.0), right: CGPoint(x: 208.5, y: 210.0), headScale: 1.00)
        ],
        .typing: [
            RigFrame(left: CGPoint(x: 131.0, y: 185.5), right: CGPoint(x: 209.5, y: 201.0), headScale: 1.00),
            RigFrame(left: CGPoint(x: 130.0, y: 216.0), right: CGPoint(x: 210.0, y: 220.0), headScale: 1.00),
            RigFrame(left: CGPoint(x: 131.0, y: 206.0), right: CGPoint(x: 209.0, y: 214.0), headScale: 1.00),
            RigFrame(left: CGPoint(x: 131.5, y: 215.5), right: CGPoint(x: 208.5, y: 220.0), headScale: 1.00)
        ],
        .fast: [
            RigFrame(left: CGPoint(x: 132.5, y: 196.5), right: CGPoint(x: 210.5, y: 210.0), headScale: 1.00),
            RigFrame(left: CGPoint(x: 129.0, y: 215.5), right: CGPoint(x: 206.0, y: 220.5), headScale: 1.00),
            RigFrame(left: CGPoint(x: 125.5, y: 211.5), right: CGPoint(x: 201.5, y: 226.5), headScale: 1.00),
            RigFrame(left: CGPoint(x: 126.5, y: 205.0), right: CGPoint(x: 203.5, y: 213.0), headScale: 1.00)
        ],
        .deleting: [
            RigFrame(left: CGPoint(x: 133.0, y: 194.5), right: CGPoint(x: 210.0, y: 196.0), headScale: 1.00),
            RigFrame(left: CGPoint(x: 134.0, y: 216.0), right: CGPoint(x: 211.0, y: 223.5), headScale: 1.00),
            RigFrame(left: CGPoint(x: 128.0, y: 219.0), right: CGPoint(x: 204.5, y: 211.0), headScale: 1.00),
            RigFrame(left: CGPoint(x: 130.5, y: 191.5), right: CGPoint(x: 206.5, y: 209.5), headScale: 1.00)
        ],
        .drowsy: [
            RigFrame(left: CGPoint(x: 103.0, y: 235.5), right: CGPoint(x: 196.0, y: 244.0), headScale: 1.00),
            RigFrame(left: CGPoint(x: 108.0, y: 247.0), right: CGPoint(x: 198.5, y: 255.0), headScale: 1.00),
            RigFrame(left: CGPoint(x: 112.5, y: 196.5), right: CGPoint(x: 219.0, y: 213.5), headScale: 1.00),
            RigFrame(left: CGPoint(x: 111.5, y: 220.5), right: CGPoint(x: 205.5, y: 233.5), headScale: 1.00)
        ],
        .sleeping: [
            RigFrame(left: CGPoint(x: 103.0, y: 232.5), right: CGPoint(x: 193.0, y: 250.0), headScale: 1.00),
            RigFrame(left: CGPoint(x: 103.0, y: 251.0), right: CGPoint(x: 196.0, y: 253.0), headScale: 1.00),
            RigFrame(left: CGPoint(x: 110.0, y: 208.0), right: CGPoint(x: 206.5, y: 219.0), headScale: 1.00),
            RigFrame(left: CGPoint(x: 107.5, y: 233.5), right: CGPoint(x: 200.5, y: 247.5), headScale: 1.00)
        ],
        .waking: [
            RigFrame(left: CGPoint(x: 127.5, y: 213.5), right: CGPoint(x: 201.5, y: 221.5), headScale: 1.00),
            RigFrame(left: CGPoint(x: 124.0, y: 159.5), right: CGPoint(x: 219.5, y: 176.5), headScale: 1.00),
            RigFrame(left: CGPoint(x: 132.0, y: 206.0), right: CGPoint(x: 209.0, y: 211.5), headScale: 1.00),
            RigFrame(left: CGPoint(x: 127.5, y: 213.5), right: CGPoint(x: 200.5, y: 222.5), headScale: 1.00)
        ],
        .dragging: [
            RigFrame(left: CGPoint(x: 147.5, y: 129.5), right: CGPoint(x: 199.5, y: 134.0), headScale: 0.78),
            RigFrame(left: CGPoint(x: 140.0, y: 136.0), right: CGPoint(x: 184.5, y: 160.0), headScale: 0.78),
            RigFrame(left: CGPoint(x: 167.5, y: 165.5), right: CGPoint(x: 212.5, y: 137.0), headScale: 0.78),
            RigFrame(left: CGPoint(x: 146.5, y: 141.0), right: CGPoint(x: 202.0, y: 142.0), headScale: 0.78)
        ],
        .petting: [
            RigFrame(left: CGPoint(x: 122.5, y: 199.0), right: CGPoint(x: 205.5, y: 211.0), headScale: 1.00),
            RigFrame(left: CGPoint(x: 116.5, y: 193.5), right: CGPoint(x: 211.5, y: 204.0), headScale: 1.00),
            RigFrame(left: CGPoint(x: 112.0, y: 190.5), right: CGPoint(x: 200.5, y: 220.0), headScale: 1.00),
            RigFrame(left: CGPoint(x: 120.0, y: 193.5), right: CGPoint(x: 204.0, y: 207.0), headScale: 1.00)
        ],
        .resizing: [
            RigFrame(left: CGPoint(x: 120.5, y: 227.5), right: CGPoint(x: 200.0, y: 237.0), headScale: 1.03),
            RigFrame(left: CGPoint(x: 126.0, y: 185.0), right: CGPoint(x: 202.5, y: 195.5), headScale: 0.96),
            RigFrame(left: CGPoint(x: 116.0, y: 232.0), right: CGPoint(x: 203.5, y: 240.5), headScale: 1.06),
            RigFrame(left: CGPoint(x: 124.5, y: 201.5), right: CGPoint(x: 204.0, y: 213.5), headScale: 0.99)
        ],
        .rest: [
            RigFrame(left: CGPoint(x: 123.5, y: 209.5), right: CGPoint(x: 212.5, y: 215.5), headScale: 1.00),
            RigFrame(left: CGPoint(x: 121.0, y: 196.0), right: CGPoint(x: 210.0, y: 210.0), headScale: 1.00),
            RigFrame(left: CGPoint(x: 121.5, y: 199.0), right: CGPoint(x: 210.5, y: 211.0), headScale: 1.00),
            RigFrame(left: CGPoint(x: 123.0, y: 194.5), right: CGPoint(x: 207.0, y: 206.5), headScale: 1.00)
        ],
        .reminder: [
            RigFrame(left: CGPoint(x: 123.5, y: 197.5), right: CGPoint(x: 208.0, y: 210.5), headScale: 1.00),
            RigFrame(left: CGPoint(x: 122.5, y: 190.5), right: CGPoint(x: 205.0, y: 208.0), headScale: 1.00),
            RigFrame(left: CGPoint(x: 130.0, y: 186.5), right: CGPoint(x: 216.0, y: 207.5), headScale: 1.00),
            RigFrame(left: CGPoint(x: 126.0, y: 194.0), right: CGPoint(x: 206.0, y: 205.0), headScale: 1.00)
        ]
    ]
    static func frame(_ state:CelState,_ cel:Int)->RigFrame {frames[state]![max(0,min(3,cel))]}
}

@discardableResult
func runOutfitRigTests()->Bool {
    var failures:[String]=[],count=0
    for state in CelState.allCases {
        count+=1
        if OutfitRig.frames[state]?.count != 4 {failures.append("missing authored anchors: \(state)")}
        for cel in 0..<4 {
            count+=1;let r=OutfitRig.frame(state,cel)
            let bounds=CelRenderer.imageRect
            if !bounds.contains(r.pointInView(r.left)) || !bounds.contains(r.pointInView(r.right)) || r.eyeDistance<20 || r.eyeDistance>70 || abs(r.angle)>0.6 {failures.append("invalid landmark: \(state)_\(cel)")}
        }
    }
    count+=1
    if OutfitRig.frame(.dragging,1).angle<=0 || OutfitRig.frame(.dragging,2).angle>=0 {failures.append("dragged head must sway with the authored cel")}
    count+=1
    if OutfitRig.frame(.sleeping,1).eyes.y<=OutfitRig.frame(.sleeping,2).eyes.y {failures.append("sleep squash must move the eye and hat anchors")}
    print("Outfit rig tests: \(count-failures.count)/\(count) passed");failures.forEach{print("FAIL: \($0)")};return failures.isEmpty
}
