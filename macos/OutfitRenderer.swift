import AppKit

/// Every costume is drawn in the avatar's own coordinate system. Existing head
/// movement, gestures, screen scaling and eye/mouth expressions remain shared.
enum OutfitRenderer {
    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }
    static let ink = color(0x70472F)
    static let white = color(0xFFF4DD)
    static let gold = color(0xE2BA66)
    static let green = color(0x87AD83)

    private static func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ fill: NSColor, stroke: NSColor? = nil, line: CGFloat = 1.6) {
        let path = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: w, height: h)); OutfitPaint.fill(path,fill,stroke:stroke,width:line)
    }
    private static func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ fill: NSColor, stroke: NSColor? = nil) {
        let path = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
        OutfitPaint.fill(path,fill,stroke:stroke,width:1.9)
    }
    private static func poly(_ points: [(CGFloat, CGFloat)], _ fill: NSColor, stroke: NSColor? = nil) {
        guard let first = points.first else { return }; let path = NSBezierPath(); path.move(to: NSPoint(x: first.0, y: first.1))
        points.dropFirst().forEach { path.line(to: NSPoint(x: $0.0, y: $0.1)) }; path.close(); OutfitPaint.fill(path,fill,stroke:stroke,width:1.9)
    }
    private static func line(_ points: [(CGFloat, CGFloat)], _ stroke: NSColor = ink, width: CGFloat = 2) {
        guard let first = points.first else { return }; let p = NSBezierPath(); p.move(to: NSPoint(x: first.0, y: first.1))
        points.dropFirst().forEach { p.line(to: NSPoint(x: $0.0, y: $0.1)) }; OutfitPaint.outline(p,color:stroke.blended(withFraction:0.18,of:ink) ?? stroke,width:width)
    }
    private static func arc(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ stroke: NSColor, width: CGFloat = 3) {
        let p = NSBezierPath(); p.move(to: NSPoint(x: x, y: y + h)); p.curve(to: NSPoint(x: x + w, y: y + h), controlPoint1: NSPoint(x: x, y: y), controlPoint2: NSPoint(x: x + w, y: y)); OutfitPaint.outline(p,color:stroke.blended(withFraction:0.18,of:ink) ?? stroke,width:width)
    }
    static func star(_ x: CGFloat, _ y: CGFloat, radius: CGFloat, fill: NSColor, points: Int = 5, rotation: Double = -.pi / 2) {
        let pts = (0..<(points * 2)).map { i -> (CGFloat, CGFloat) in
            let a = rotation + Double(i) * .pi / Double(points), r = i % 2 == 0 ? radius : radius * 0.44
            return (x + CGFloat(cos(a)) * r, y + CGFloat(sin(a)) * r)
        }; poly(pts, fill)
    }
    private static func leaf(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ fill: NSColor = green) {
        let p = NSBezierPath(); p.move(to: NSPoint(x: x, y: y + h)); p.curve(to: NSPoint(x: x + w, y: y), controlPoint1: NSPoint(x: x - w * 0.2, y: y), controlPoint2: NSPoint(x: x + w * 0.5, y: y - h * 0.1)); p.curve(to: NSPoint(x: x, y: y + h), controlPoint1: NSPoint(x: x + w * 1.2, y: y + h), controlPoint2: NSPoint(x: x + w * 0.4, y: y + h)); OutfitPaint.fill(p,fill)
    }
    private static func flower(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, petals: Int = 6, fill: NSColor, center: NSColor = gold) {
        for i in 0..<petals { let a = Double(i) * .pi * 2 / Double(petals); oval(x + CGFloat(cos(a)) * r * 0.65 - r * 0.42, y + CGFloat(sin(a)) * r * 0.65 - r * 0.42, r * 0.84, r * 0.84, fill) }
        oval(x - r * 0.35, y - r * 0.35, r * 0.70, r * 0.70, center)
    }
    private static func bow(_ x: CGFloat, _ y: CGFloat, _ fill: NSColor, scale: CGFloat = 1) {
        poly([(x, y), (x - 15 * scale, y - 8 * scale), (x - 15 * scale, y + 8 * scale)], fill, stroke: ink.withAlphaComponent(0.3))
        poly([(x, y), (x + 15 * scale, y - 8 * scale), (x + 15 * scale, y + 8 * scale)], fill, stroke: ink.withAlphaComponent(0.3))
        oval(x - 3.5 * scale, y - 3.5 * scale, 7 * scale, 7 * scale, fill.blended(withFraction: 0.18, of: white) ?? fill)
    }
    private static func cap(_ fill: NSColor, brim: NSColor? = nil, high: CGFloat = 24) {
        let p = NSBezierPath(); p.move(to: NSPoint(x: 91, y: 91)); p.curve(to: NSPoint(x: 173, y: 91), controlPoint1: NSPoint(x: 91, y: 91 - high * 1.7), controlPoint2: NSPoint(x: 173, y: 91 - high * 1.7)); p.close(); OutfitPaint.fill(p,fill,width:2.2)
        box(88, 87, 89, 8, 4, brim ?? fill)
    }
    private static func crown(_ fill: NSColor, crystal: Bool = false) {
        if crystal { poly([(99, 88), (95, 65), (111, 77), (120, 52), (132, 72), (147, 50), (155, 77), (170, 64), (164, 89)], fill, stroke: ink.withAlphaComponent(0.4)) }
        else { poly([(99, 88), (94, 59), (113, 75), (132, 50), (150, 75), (171, 59), (164, 88)], fill, stroke: ink.withAlphaComponent(0.4)) }
        box(98, 85, 68, 9, 3, fill); oval(127, 77, 10, 10, white.withAlphaComponent(0.8))
    }
    private static func wizard(_ fill: NSColor, bent: Bool = false) {
        poly(bent ? [(98, 88), (124, 55), (151, 49), (140, 65), (166, 88)] : [(99, 88), (131, 46), (165, 88)], fill, stroke: ink.withAlphaComponent(0.4))
        oval(87, 84, 90, 13, fill); box(106, 79, 52, 7, 2, gold); star(132, 69, radius: 7, fill: gold)
    }
    private static func glasses(_ fill: NSColor, shaded: Bool = false, square: Bool = false) {
        let lens = shaded ? fill.withAlphaComponent(0.19) : white.withAlphaComponent(0.04)
        if square { box(88, 111, 33, 22, 5, lens, stroke: fill); box(143, 111, 33, 22, 5, lens, stroke: fill) }
        else { oval(91, 109, 29, 27, lens, stroke: fill, line: 2.2); oval(144, 109, 29, 27, lens, stroke: fill, line: 2.2) }
        line([(120, 119), (132, 116), (144, 119)], fill, width: 2)
        line([(88, 116), (78, 112)], fill); line([(176, 116), (186, 112)], fill)
    }
    private static func headset(_ fill: NSColor) {
        arc(65, 70, 134, 58, fill, width: 6); box(60, 113, 13, 30, 6, fill); box(191, 113, 13, 30, 6, fill)
    }
    private static func antlers(_ fill: NSColor) {
        for side: CGFloat in [-1, 1] {
            let x = 132 + side * 45
            line([(x, 81), (x + side * 7, 67), (x + side * 5, 49)], fill, width: 4)
            line([(x + side * 6, 64), (x + side * 18, 57), (x + side * 18, 50)], fill, width: 3)
            line([(x + side * 7, 69), (x - side * 4, 59)], fill, width: 3)
        }
    }

    static func drawBehind(_ outfit: Outfit) {
        let p = color(outfit.primary), s = color(outfit.secondary)
        switch outfit.style {
        case .bear, .bunny, .fox: break
        case .antlers, .reindeer: antlers(color(0xAC8065))
        case .devil: poly([(77, 83), (86, 47), (102, 80)], color(0xCB7B87)); poly([(162, 80), (178, 47), (187, 83)], color(0xCB7B87))
        case .halo: oval(99, 48, 66, 13, gold.withAlphaComponent(0.3), stroke: gold, line: 3)
        case .frog: break
        case .bee:
            line([(111, 82), (102, 55)], ink, width: 2); line([(153, 82), (162, 55)], ink, width: 2); oval(96, 48, 12, 12, gold); oval(156, 48, 12, 12, gold)
            oval(48, 112, 29, 34, color(0xD7E6E7, alpha: 0.85)); oval(187, 112, 29, 34, color(0xD7E6E7, alpha: 0.85))
        case .butterfly, .dragon, .aurora:
            for side: CGFloat in [-1, 1] { let x = side < 0 ? CGFloat(40) : 190; oval(x, 94, 35, 43, p.withAlphaComponent(0.85)); oval(x + (side < 0 ? 8 : -5), 128, 28, 31, s.withAlphaComponent(0.8)); star(x + 18, 114, radius: 5, fill: white) }
            if outfit.style == .aurora { oval(95, 47, 74, 13, color(0xB7CFD8, alpha: 0.25), stroke: color(0xA9B7D9), line: 2.5) }
        case .astronaut:
            box(61,105,13,30,6,color(0xC0D3D6));box(190,105,13,30,6,color(0xC0D3D6))
        case .knight: box(60, 64, 144, 110, 42, color(0xB7C0CE)); poly([(122, 70), (132, 46), (144, 70)], s)
        case .ghost:
            let points: [(CGFloat,CGFloat)] = [(58, 94), (75, 64), (132, 52), (189, 64), (206, 94), (207, 185), (191, 176), (176, 187), (158, 178), (140, 187), (121, 179), (104, 187), (85, 176), (58, 185)]
            poly(points, color(0xEDEAF2), stroke: color(0xC9C0D4))
        case .elf: leaf(45, 109, 33, 22); leaf(187, 109, 33, 22)
        default: break
        }
    }

    static func drawHeadwear(_ outfit: Outfit) {
        let p = color(outfit.primary), s = color(outfit.secondary)
        switch outfit.style {
        case .bear:
            oval(155,71,8,8,color(0xC28D61));oval(176,71,8,8,color(0xC28D61));oval(157,75,25,20,color(0xD6AE7E));oval(165,84,9,7,white);oval(163,82,2,3,ink);oval(175,82,2,3,ink);oval(168,86,3,2,ink)
        case .bunny:
            oval(157,60,7,21,white);oval(173,60,7,21,white);oval(160,65,2,12,color(0xDAA9BB));oval(176,65,2,12,color(0xDAA9BB));oval(154,77,29,18,white);oval(161,83,2,3,ink);oval(175,83,2,3,ink);bow(179,92,color(0xDAA9BB),scale:0.30)
        case .fox:
            poly([(151,76),(154,65),(165,74),(174,65),(178,77),(165,92)],color(0xC37E55));poly([(154,78),(162,80),(165,88),(168,80),(175,78),(165,91)],white);oval(158,76,2,3,ink);oval(170,76,2,3,ink);oval(163,85,4,3,ink)
        case .antlers: flower(132, 82, 10, petals: 5, fill: white)
        case .devil: poly([(123, 83), (132, 75), (141, 83), (132, 90)], color(0xCB7B87))
        case .halo: flower(173, 82, 9, fill: white)
        case .frog:
            cap(color(0x9DB889),high:16);oval(107,63,15,15,color(0x9DB889));oval(145,63,15,15,color(0x9DB889));oval(111,66,7,8,white);oval(149,66,7,8,white);oval(114,68,3,4,ink);oval(152,68,3,4,ink)
        case .bee: cap(gold, brim: ink, high: 13); line([(116, 71), (116, 84)], ink, width: 5); line([(145, 71), (145, 84)], ink, width: 5)
        case .butterfly: line([(132, 81), (122, 58)], p, width: 1.6); line([(132, 81), (143, 58)], p, width: 1.6); oval(118, 53, 7, 7, s); oval(140, 53, 7, 7, s)
        case .unicorn:
            poly([(121, 84), (132, 47), (143, 84)], color(0xD5BCD8), stroke: color(0xB9A0C2)); line([(126, 69), (138, 74)], white, width: 2); flower(108, 85, 8, fill: color(0xE4B3C1)); flower(154, 85, 8, fill: color(0xBBD5C4))
        case .cap, .sport: cap(p); oval(127, 72, 10, 10, white); if outfit.style == .sport { box(77, 94, 110, 7, 2, s); star(132, 97, radius: 6, fill: white) }
        case .beret, .painter: oval(86, 58, 92, 32, p, stroke: ink.withAlphaComponent(0.3)); box(94, 82, 78, 9, 4, p); line([(135, 60), (141, 51)], p, width: 5); if outfit.style == .painter { line([(172, 84), (186, 56)], color(0xB68B63), width: 4); oval(181, 48, 10, 14, s) }
        case .bucket, .gardener:
            let crown=NSBezierPath();crown.move(to:NSPoint(x:99,y:84));crown.curve(to:NSPoint(x:106,y:58),controlPoint1:NSPoint(x:100,y:76),controlPoint2:NSPoint(x:103,y:63));crown.curve(to:NSPoint(x:158,y:59),controlPoint1:NSPoint(x:120,y:54),controlPoint2:NSPoint(x:147,y:55));crown.curve(to:NSPoint(x:166,y:85),controlPoint1:NSPoint(x:161,y:64),controlPoint2:NSPoint(x:164,y:78));crown.close();OutfitPaint.fill(crown,p,width:2.2)
            let brim=NSBezierPath();brim.move(to:NSPoint(x:99,y:80));brim.curve(to:NSPoint(x:81,y:89),controlPoint1:NSPoint(x:93,y:84),controlPoint2:NSPoint(x:85,y:85));brim.curve(to:NSPoint(x:182,y:91),controlPoint1:NSPoint(x:100,y:102),controlPoint2:NSPoint(x:158,y:103));brim.curve(to:NSPoint(x:166,y:82),controlPoint1:NSPoint(x:178,y:87),controlPoint2:NSPoint(x:173,y:84));brim.curve(to:NSPoint(x:99,y:80),controlPoint1:NSPoint(x:144,y:88),controlPoint2:NSPoint(x:119,y:88));brim.close();OutfitPaint.fill(brim,p,width:2.1)
            arc(106,70,51,9,s,width:4)
            if outfit.style == .gardener { leaf(149,60,16,18) }
        case .beanie, .barista: cap(p, high: 29); box(88, 80, 89, 15, 6, p); for x in stride(from: CGFloat(96), through: 166, by: 10) { line([(x, 83), (x, 92)], white.withAlphaComponent(0.35), width: 1.4) }; oval(124, 49, 16, 16, s); if outfit.style == .barista { box(121, 79, 22, 14, 3, white); arc(143, 81, 7, 7, white, width: 2) }
        case .aviator, .spacePilot:
            cap(color(0xAD8C75), high: 26); box(79, 80, 16, 27, 6, color(0xAD8C75)); box(169, 80, 16, 27, 6, color(0xAD8C75)); oval(103, 69, 23, 15, color(0xD8E6E7), stroke: ink); oval(138, 69, 23, 15, color(0xD8E6E7), stroke: ink); line([(126, 76), (138, 76)], ink); if outfit.style == .spacePilot { star(176, 94, radius: 7, fill: gold); line([(88, 103), (75, 119)], s, width: 4) }
        case .detective: cap(color(0xB6A18B), brim: color(0x8D7866), high: 25); for x in stride(from: CGFloat(105), through: 161, by: 14) { line([(x, 68), (x, 86)], color(0xDBCCB6), width: 1.4) }; line([(96, 75), (170, 75)], color(0x78695D), width: 1.5)
        case .sunglasses: break
        case .glasses: break
        case .headphones, .galaxyHeadset: headset(p); if outfit.style == .galaxyHeadset { star(65, 126, radius: 7, fill: gold); star(198, 126, radius: 7, fill: white); star(132, 61, radius: 6, fill: s) }
        case .sleepCap: poly([(91, 88), (106, 56), (143, 53), (169, 78), (174, 96), (158, 86), (146, 70), (163, 88)], p); box(90, 83, 73, 11, 4, white); oval(164, 88, 15, 15, white); star(121, 69, radius: 5, fill: gold)
        case .chef: box(103, 65, 58, 29, 5, white, stroke: color(0xD7C7BC)); oval(93, 49, 31, 30, white, stroke: color(0xD7C7BC)); oval(118, 44, 31, 34, white, stroke: color(0xD7C7BC)); oval(142, 49, 30, 30, white, stroke: color(0xD7C7BC)); box(104, 77, 56, 13, 3, white); line([(113, 80), (113, 89)], color(0xDBD0C5), width: 1.2); line([(151, 80), (151, 89)], color(0xDBD0C5), width: 1.2)
        case .doctor: box(80, 85, 104, 8, 3, color(0xC3D8D6)); oval(117, 66, 30, 30, color(0xD8E2E7), stroke: color(0x96AFB9)); oval(125, 74, 14, 14, white, stroke: color(0x9AB4BE))
        case .nurse: poly([(101, 65), (163, 65), (171, 87), (94, 87)], white, stroke: color(0xD7BBC2)); box(129, 68, 6, 17, 1, color(0xCF7E8C)); box(123, 73, 18, 6, 1, color(0xCF7E8C))
        case .firefighter: cap(color(0xCC7870), brim: color(0xB4615B), high: 30); box(125, 52, 14, 35, 5, gold); poly([(124, 76), (140, 76), (141, 88), (132, 94), (123, 88)], gold); star(132, 83, radius: 5, fill: white)
        case .sheriff: poly([(105, 88), (112, 54), (131, 62), (152, 54), (160, 88)], color(0xC8A26C)); oval(80, 82, 104, 14, color(0xC8A26C)); box(104, 76, 56, 8, 2, color(0x957456)); star(132, 78, radius: 9, fill: gold, points: 6)
        case .hardhat: cap(gold, high: 30); box(128, 51, 8, 38, 3, color(0xF1D397)); line([(109, 64), (106, 85)], color(0xC79B4D), width: 2); line([(155, 64), (158, 85)], color(0xC79B4D), width: 2)
        case .astronaut:
            cap(white,brim:color(0xA3BEC4),high:24);box(111,70,42,17,6,color(0xD3E1DF));oval(119,76,6,5,p);oval(132,76,6,5,gold);star(148,80,radius:4,fill:gold)
        case .captain: cap(white, brim: color(0x73869A), high: 22); box(99, 79, 67, 10, 3, color(0x73869A)); line([(132, 63), (132, 78)], gold, width: 2.5); arc(123, 65, 18, 12, gold, width: 2.5); oval(129, 60, 6, 6, gold)
        case .topHat, .ribbonTopHat: box(104, 50, 56, 38, 5, color(0x7D7186)); oval(87, 82, 90, 13, color(0x7D7186)); box(104, 74, 56, 9, 1, p); if outfit.style == .ribbonTopHat { bow(161, 79, s, scale: 0.6) } else { star(132, 67, radius: 6, fill: gold) }
        case .graduate: poly([(83, 71), (132, 51), (181, 71), (132, 91)], color(0x797487), stroke: ink); box(105, 77, 54, 14, 2, color(0x797487)); line([(133, 69), (171, 76), (171, 99)], gold, width: 2); box(167, 96, 8, 13, 2, gold)
        case .crown, .goldenCrown, .crystalCrown, .jewelCrown:
            let c = outfit.style == .crystalCrown ? color(0xB7D9E9) : (outfit.style == .jewelCrown ? color(0xCBAAD1) : gold)
            crown(c, crystal: outfit.style == .crystalCrown)
            if outfit.style == .goldenCrown { star(132, 61, radius: 8, fill: white); oval(105, 87, 7, 7, color(0xD18A78)); oval(152, 87, 7, 7, color(0xD18A78)) }
            if outfit.style == .jewelCrown { poly([(123, 77), (132, 65), (141, 77), (132, 87)], color(0x8F90BF)); oval(102, 82, 7, 7, white); oval(156, 82, 7, 7, white) }
        case .tiara: arc(94, 63, 76, 24, color(0xC1B7CD), width: 3); for x: CGFloat in [104, 118, 132, 146, 160] { oval(x - 3, 70 - abs(x - 132) * 0.25, 6, 6, white, stroke: color(0xC2B4CA)) }; poly([(126, 65), (132, 53), (138, 65), (132, 73)], p)
        case .wizard, .witch, .neonWizard: wizard(outfit.style == .witch ? color(0x8D829A) : p, bent: outfit.style == .witch); if outfit.style == .neonWizard { line([(108, 73), (117, 70), (114, 80), (122, 77)], color(0xA4E0D5), width: 2.3); star(150, 78, radius: 4, fill: color(0xD8A5DD)) }
        case .warrior: box(78, 84, 108, 10, 3, color(0xC5A583)); leaf(155, 47, 18, 41, p); line([(153, 89), (169, 49)], color(0xE7D9BB), width: 1.3); oval(126, 85, 12, 12, gold)
        case .knight: box(73, 84, 118, 17, 7, color(0xBAC6D5)); line([(91, 91), (173, 91)], color(0x8998AA), width: 2); poly([(126, 62), (132, 52), (138, 62), (132, 74)], s)
        case .pirate: poly([(79, 86), (100, 58), (132, 66), (165, 58), (185, 86)], color(0x7D747F), stroke: ink); oval(126, 72, 12, 10, white); line([(122, 84), (142, 77)], white, width: 1.7); line([(122, 77), (142, 84)], white, width: 1.7)
        case .ninja: box(72, 87, 120, 11, 3, color(0x7B899C)); poly([(190, 88), (215, 83), (204, 96), (218, 104), (191, 98)], p); oval(124, 86, 16, 14, color(0xCCD5DF)); line([(129, 89), (135, 95), (129, 95), (135, 89)], ink, width: 1)
        case .elf: leaf(109, 55, 44, 32); line([(115, 83), (147, 59)], color(0xD6E4BE), width: 1.4); oval(153, 83, 8, 8, gold)
        case .dragon: poly([(86, 83), (96, 52), (109, 82)], color(0x9BBD9D)); poly([(155, 82), (168, 52), (178, 83)], color(0x9BBD9D)); for x: CGFloat in [118, 132, 146] { poly([(x - 6, 84), (x, 74), (x + 6, 84)], color(0x82A687)) }
        case .strawberry: poly([(109, 68), (155, 68), (149, 88), (132, 99), (115, 88)], color(0xD98E95)); for x: CGFloat in [120, 132, 144] { oval(x - 1, 78, 2, 4, gold) }; leaf(120, 58, 17, 16); leaf(135, 58, 15, 16)
        case .cherry: arc(116, 48, 31, 24, green, width: 2); line([(130, 55), (146, 78)], green, width: 2); oval(104, 72, 24, 24, color(0xCB7C87)); oval(136, 73, 24, 24, color(0xD7909B)); leaf(132, 49, 23, 10)
        case .watermelon: poly([(95, 68), (169, 68), (132, 99)], color(0xDE9391), stroke: green); line([(98, 69), (166, 69)], color(0xB6C8A4), width: 6); for x: CGFloat in [116, 132, 148] { oval(x, 77, 2.5, 4, ink) }
        case .lemon: oval(108, 61, 49, 32, color(0xE5C969), stroke: color(0xC6AE62)); oval(119, 68, 26, 18, color(0xF1D984)); leaf(147, 55, 21, 13); line([(130, 70), (130, 84)], white.withAlphaComponent(0.7), width: 1.3)
        case .peach: oval(109, 64, 30, 31, color(0xE6ACA4)); oval(127, 64, 30, 31, color(0xE9B7A4)); arc(128, 68, 8, 23, color(0xCA8F8B), width: 1.4); leaf(136, 53, 25, 15)
        case .grape: for (x,y): (CGFloat,CGFloat) in [(119,66),(136,66),(111,79),(128,79),(145,79),(120,91),(136,91),(128,101)] { oval(x, y, 14, 14, color(0xB49BBC), stroke: color(0x9B80A8)) }; leaf(132, 53, 25, 15)
        case .pineapple: oval(111, 64, 42, 36, gold, stroke: color(0xC59B5B)); for x: CGFloat in [115, 127, 139] { line([(x, 70), (x + 10, 90)], color(0xB58E4F), width: 1) }; poly([(126, 69), (114, 48), (130, 57), (135, 45), (141, 59), (156, 50), (144, 72)], green)
        case .donut: oval(103, 55, 58, 41, color(0xCBA882)); oval(107, 58, 50, 33, color(0xDCA8BC)); oval(124, 68, 16, 14, creamColor); for (x,y): (CGFloat,CGFloat) in [(116,64),(140,65),(114,80),(148,79),(132,87)] { line([(x,y),(x+3,y+2)], white, width: 2) }
        case .cupcake: poly([(111, 76), (154, 76), (148, 100), (118, 100)], p); for x: CGFloat in [121, 132, 143] { line([(x, 80), (x, 96)], white.withAlphaComponent(0.6), width: 1.5) }; oval(107, 64, 51, 21, white); oval(117, 54, 32, 22, white); oval(128, 49, 9, 9, color(0xD38C97))
        case .icecream: poly([(119, 78), (147, 78), (133, 105)], color(0xCBAA7C)); oval(107, 62, 27, 28, color(0xB9D0BB)); oval(132, 62, 27, 28, color(0xE8B1C2)); oval(120, 48, 27, 28, color(0xDED0A3)); line([(128, 88), (138, 85)], color(0xAA8B64), width: 1)
        case .sunflower: flower(132, 74, 25, petals: 12, fill: gold, center: color(0xA58C68)); leaf(155, 83, 19, 12)
        case .daisy: flower(132, 76, 23, petals: 8, fill: white); leaf(151, 85, 22, 12)
        case .rose: leaf(103, 78, 20, 13); leaf(147, 78, 20, 13); flower(132, 73, 22, petals: 7, fill: color(0xD699AB), center: color(0xBD7F95)); arc(120, 61, 23, 16, color(0xF1C7D1), width: 2)
        case .tulip: line([(132, 97), (132, 75)], green, width: 4); poly([(113, 56), (124, 65), (132, 52), (142, 65), (152, 56), (148, 81), (132, 89), (117, 80)], p); leaf(134, 83, 19, 11)
        case .clover: for (x,y): (CGFloat,CGFloat) in [(115,59),(133,59),(115,77),(133,77)] { oval(x, y, 20, 20, green) }; line([(132, 78), (143, 101)], color(0x719A70), width: 3)
        case .mushroom: box(122, 77, 21, 23, 7, color(0xE3CCAF)); let m = NSBezierPath(); m.move(to: NSPoint(x: 101,y:81)); m.curve(to: NSPoint(x:164,y:81), controlPoint1:NSPoint(x:105,y:40), controlPoint2:NSPoint(x:160,y:40)); m.close(); p.setFill(); m.fill(); oval(113, 64, 10, 8, white); oval(139, 61, 9, 9, white); oval(137, 77, 6, 5, white)
        case .cactus: box(121, 52, 22, 45, 11, green); box(104, 68, 16, 20, 8, green); box(145, 62, 16, 24, 8, green); line([(112, 82), (128, 82)], green, width: 8); line([(140, 78), (153, 78)], green, width: 8); flower(137, 54, 7, petals: 5, fill: p); line([(127, 63), (127, 88)], white.withAlphaComponent(0.7), width: 1.2)
        case .pinecone: oval(114, 54, 36, 48, color(0xB79B7D)); for row in 0..<4 { for col in 0..<3 { arc(117 + CGFloat(col) * 9, 61 + CGFloat(row) * 9, 10, 5, color(0x927A64), width: 1.4) } }; leaf(145, 57, 20, 12)
        case .sprout: line([(132, 91), (132, 67)], green, width: 3); leaf(108, 51, 25, 24); leaf(133, 51, 25, 24, color(0xA6C698)); box(121, 86, 22, 8, 4, color(0xC5AA8F))
        case .lotus: oval(91, 77, 82, 20, color(0x9AB895)); for dx: CGFloat in [-17, 0, 17] { leaf(121 + dx, 54 + abs(dx) * 0.3, 22, 36, color(0xE2B8C9)) }; oval(127, 81, 12, 6, gold)
        case .sun: star(132, 74, radius: 30, fill: gold, points: 12); oval(113, 55, 38, 38, color(0xF0D591)); oval(123, 70, 3, 4, ink); oval(138, 70, 3, 4, ink); arc(125, 77, 14, 5, ink, width: 1.4)
        case .moon: oval(111, 50, 43, 43, color(0xE7D394)); oval(127, 45, 37, 35, creamColor); star(160, 81, radius: 8, fill: gold)
        case .saturn: oval(115, 58, 35, 35, p); NSGraphicsContext.saveGraphicsState(); let tr = NSAffineTransform(); tr.translateX(by:132,yBy:76);tr.rotate(byDegrees:-18);tr.concat(); oval(-39, -8, 78, 16, .clear, stroke: gold, line: 4); NSGraphicsContext.restoreGraphicsState(); oval(123, 63, 12, 5, white.withAlphaComponent(0.4))
        case .star: star(132, 73, radius: 29, fill: gold); star(132, 73, radius: 14, fill: white.withAlphaComponent(0.4)); oval(121, 72, 3, 4, ink); oval(140, 72, 3, 4, ink)
        case .comet: poly([(99, 87), (157, 49), (143, 75), (169, 63), (133, 95)], color(0xE5C48A)); star(115, 83, radius: 19, fill: gold); line([(149, 54), (163, 46)], s, width: 2)
        case .rainbow: arc(95, 48, 74, 40, color(0xDAA1AE), width: 7); arc(103, 58, 58, 30, gold, width: 7); arc(111, 68, 42, 20, color(0x9DC3AD), width: 7); oval(89, 81, 24, 14, white); oval(151, 81, 24, 14, white)
        case .cloud: oval(98, 65, 67, 28, white, stroke: color(0xC5D4DE)); oval(109, 51, 31, 32, white); oval(131, 57, 27, 28, white); for x: CGFloat in [118, 132, 146] { line([(x, 97), (x - 3, 105)], color(0xA4C5D7), width: 2) }
        case .lightning: poly([(131, 46), (112, 77), (130, 77), (121, 104), (153, 65), (135, 65), (146, 46)], gold, stroke: color(0xCAA65E)); star(103, 74, radius: 5, fill: s)
        case .snowflake: for i in 0..<6 { let a = Double(i) * .pi / 3; let x = 132 + CGFloat(cos(a)) * 28, y = 75 + CGFloat(sin(a)) * 28; line([(132,75),(x,y)], color(0xA5C9DE), width: 2.5); let bx = 132 + CGFloat(cos(a)) * 19, by = 75 + CGFloat(sin(a)) * 19; for sign: Double in [-1,1] { line([(bx,by),(bx + CGFloat(cos(a + sign * 0.8)) * 9,by + CGFloat(sin(a + sign * 0.8)) * 9)], color(0xA5C9DE), width: 2) } }
        case .drop: let d = NSBezierPath();d.move(to:NSPoint(x:132,y:49));d.curve(to:NSPoint(x:111,y:84),controlPoint1:NSPoint(x:126,y:64),controlPoint2:NSPoint(x:107,y:72));d.curve(to:NSPoint(x:154,y:84),controlPoint1:NSPoint(x:112,y:108),controlPoint2:NSPoint(x:152,y:108));d.curve(to:NSPoint(x:132,y:49),controlPoint1:NSPoint(x:161,y:73),controlPoint2:NSPoint(x:137,y:63));color(0xAED0E3).setFill();d.fill();line([(124,72),(119,82)],white,width:3)
        case .santa: poly([(95, 86), (107, 57), (142, 49), (168, 67), (179, 86), (159, 76), (148, 65), (161, 87)], color(0xCF7B79)); box(92, 81, 73, 13, 5, white); oval(170, 80, 17, 17, white)
        case .reindeer: box(87, 84, 91, 10, 4, color(0xCB7D78)); flower(132, 83, 9, petals: 5, fill: white); oval(127, 80, 10, 10, gold)
        case .pumpkin: oval(103, 58, 58, 37, color(0xDCAA75)); oval(114, 58, 36, 37, color(0xE3B780)); line([(132, 58), (135, 48)], green, width: 5); poly([(115,76),(121,68),(125,76)], ink); poly([(139,76),(145,68),(150,76)], ink); line([(121,84),(132,88),(144,84)], ink, width: 2)
        case .ghost: star(181, 80, radius: 8, fill: s); oval(122, 65, 6, 8, color(0xAA9DB7)); oval(137, 65, 6, 8, color(0xAA9DB7))
        case .party: poly([(107,91),(132,47),(158,91)],p); line([(120,68),(145,76)],white,width:5); line([(114,80),(151,88)],s,width:4); oval(126,43,12,12,gold); oval(94,76,5,5,s); star(170,64,radius:5,fill:gold)
        case .mask: poly([(109,83),(101,59),(125,73),(133,51),(145,73),(164,59),(155,85)],p); oval(124,67,16,13,gold); line([(170,93),(186,69)],gold,width:2)
        case .wreath: for i in 0..<9 { let x = CGFloat(89 + i * 10), y = 78 + abs(CGFloat(i - 4)) * 1.4; leaf(x,y,17,10,green); if i % 2 == 0 { flower(x + 6,y - 1,7,petals:5,fill:i % 4 == 0 ? p : white) } }
        case .lantern: box(114,57,37,38,13,color(0xCE8582)); line([(111,57),(154,57)],gold,width:4); line([(114,95),(151,95)],gold,width:3); for x: CGFloat in [122,132,142] { arc(x-3,61,6,29,gold.withAlphaComponent(0.65),width:1) }; line([(132,95),(132,106)],gold,width:2);box(129,102,6,10,2,gold)
        case .ingot: poly([(101,65),(118,75),(145,75),(164,65),(158,88),(132,99),(108,88)],gold,stroke:color(0xC7A05B)); oval(114,65,36,18,color(0xF0D391)); star(132,79,radius:6,fill:white.withAlphaComponent(0.6))
        case .hibiscus: flower(176,84,24,petals:5,fill:color(0xDEA5B6),center:color(0xD7B45F)); line([(176,84),(188,68)],gold,width:2); leaf(149,88,26,12)
        case .keycap: box(107,55,51,40,8,p,stroke:ink.withAlphaComponent(0.4)); box(113,60,39,24,5,white); line([(124,72),(139,72),(135,67)],p,width:2); line([(139,72),(135,77)],p,width:2)
        case .gear: star(132,75,radius:29,fill:color(0xB7B1A6),points:10); oval(113,56,38,38,color(0xD6C5A8)); oval(124,67,16,16,color(0x8E9A9C)); oval(129,72,6,6,white)
        case .pencil: NSGraphicsContext.saveGraphicsState(); let pen = NSAffineTransform();pen.translateX(by:132,yBy:77);pen.rotate(byDegrees:-22);pen.concat();box(-34,-8,58,16,3,gold);box(-34,-8,10,16,2,p);poly([(24,-8),(39,0),(24,8)],color(0xD6BA93));poly([(33,-3),(39,0),(33,3)],ink);line([(-18,-3),(19,-3)],white,width:2);NSGraphicsContext.restoreGraphicsState()
        case .camera: box(106,62,54,32,6,color(0x88939D),stroke:ink);box(115,56,18,9,3,color(0x88939D));oval(121,66,24,24,color(0xBCCDD6),stroke:ink);oval(127,72,12,12,color(0x6F8393));box(148,67,7,5,1,gold)
        case .postman: cap(color(0x8CA5BA),brim:color(0x6E879C),high:24);box(118,68,28,18,3,white);line([(118,69),(132,78),(146,69)],color(0xA7BCCB),width:1.4)
        case .musician: box(80,85,104,8,3,p); line([(122,77),(122,54),(145,49),(145,73)],ink,width:3); oval(112,74,12,8,ink);oval(135,70,12,8,ink);line([(122,59),(145,54)],ink,width:3)
        case .cyber: box(84,85,96,8,3,color(0x9393AF));star(132,77,radius:9,fill:color(0xB8DDD6));line([(93,88),(82,78),(74,78)],color(0xB8DDD6),width:2)
        case .steampunk: cap(color(0xB69B7D),brim:color(0x8D7C69),high:25);oval(109,69,20,17,gold,stroke:ink);oval(138,69,20,17,gold,stroke:ink);line([(129,77),(138,77)],ink,width:2);star(176,89,radius:10,fill:gold,points:8)
        case .aurora: poly([(111,83),(122,60),(132,72),(143,52),(153,84)],color(0xB9CEDD),stroke:color(0x98AFC9));star(132,80,radius:10,fill:white);star(102,61,radius:6,fill:color(0xB9D7CC));star(165,63,radius:5,fill:color(0xD5BADF))
        }
    }

    private static let creamColor = color(0xFFFAEF)

    static func drawFaceAndCollar(_ outfit: Outfit) { drawFace(outfit); drawCollar(outfit) }

    static func drawFace(_ outfit: Outfit) {
        let p = color(outfit.primary)
        switch outfit.style {
        case .sunglasses: glasses(color(0x7C7B92), shaded: true, square: true)
        case .glasses: glasses(color(0x9A8C7B))
        case .cyber: box(84,112,96,18,6,color(0xB6D5D8,alpha:0.12),stroke:color(0x9596B9));line([(93,115),(117,115)],color(0xB8DDD6),width:2);line([(145,126),(169,126)],color(0xD4B9DF),width:2)
        case .steampunk: glasses(color(0xB29567), shaded: false)
        case .mask: poly([(86,111),(105,106),(124,116),(132,113),(141,116),(159,106),(180,111),(172,134),(154,137),(132,128),(111,137),(92,132)],p.withAlphaComponent(0.22),stroke:p);oval(96,115,20,12,.clear,stroke:gold);oval(149,115,20,12,.clear,stroke:gold)
        case .pirate: oval(92,110,27,24,color(0x817787,alpha:0.16),stroke:color(0x817787));line([(80,107),(184,137)],color(0x817787),width:1.7)
        case .fox: for side: CGFloat in [-1,1] { let x = 132 + side * 44; line([(x,138),(x + side * 9,135)],color(0xD18B5B),width:2);line([(x,144),(x + side * 8,144)],color(0xD18B5B),width:2) }
        case .dragon: for x: CGFloat in [84,175] { poly([(x,138),(x+5,134),(x+10,139)],color(0xA3C0A0)) }
        case .astronaut: break
        default: break
        }
    }

    static func drawCollar(_ outfit: Outfit) {
        let p = color(outfit.primary), s = color(outfit.secondary)
        switch outfit.collar {
        case 0: bow(132,178,p,scale:0.80)
        case 1: poly([(126,170),(138,170),(136,177),(142,188),(132,192),(122,188),(128,177)],p); line([(126,171),(138,171)],s,width:2)
        case 2: box(103,169,58,10,4,p); poly([(144,175),(156,175),(164,189),(150,187)],p); line([(149,179),(158,182)],white.withAlphaComponent(0.5),width:1.2)
        case 3: poly([(101,168),(163,168),(132,190)],p);star(132,178,radius:4,fill:white)
        case 4: box(100,169,64,9,4,p); oval(126,174,12,12,gold);oval(130,177,4,5,white)
        case 5: line([(101,170),(111,180),(132,183),(153,180),(163,170)],p,width:4);oval(126,178,12,12,s)
        case 6: bow(132,177,p,scale:0.65);poly([(128,181),(119,191),(130,187)],s);poly([(135,181),(145,191),(133,187)],s)
        case 7: poly([(99,168),(116,173),(132,187),(148,173),(165,168),(163,185),(144,183),(132,190),(119,183),(101,185)],p.withAlphaComponent(0.85));oval(129,171,6,6,gold)
        case 8: poly([(101,168),(121,170),(132,181),(143,170),(163,168),(153,183),(132,186),(111,183)],white,stroke:p);line([(107,171),(121,179)],p,width:2);line([(157,171),(143,179)],p,width:2);bow(132,182,p,scale:0.4)
        default: for i in 0..<9 { let a = .pi * (0.15 + Double(i) * 0.0875);oval(129 + CGFloat(cos(a))*31,164 + CGFloat(sin(a))*18,6,6,i % 2 == 0 ? p : s) }
        }
    }
}
