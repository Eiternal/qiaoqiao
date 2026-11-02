import AppKit

enum OutfitThumbnails {
    private static var cache: [String: NSImage] = [:]
    static func image(for outfit: Outfit, size: NSSize = NSSize(width: 128, height: 104)) -> NSImage {
        let key = "\(outfit.id)-\(size.width)-\(size.height)"
        if let image = cache[key] { return image }
        let image = NSImage(size: size)
        image.lockFocus()
        NSGraphicsContext.saveGraphicsState()
        let scale = min(size.width / 204, size.height / 154)
        let transform = NSAffineTransform()
        transform.translateX(by: size.width / 2, yBy: size.height / 2)
        transform.scaleX(by: scale, yBy: -scale)
        transform.translateX(by: -132, yBy: -119)
        transform.concat()
        let now = Date(timeIntervalSince1970: 1_800_000_004)
        let view = PetView(model: CounterModel(now: now))
        view.previewOutfit = outfit; view.showsCounter = false; view.showsSpeech = false; view.now = now
        // The thumbnail's transform already establishes a top-down drawing space.
        // Tell NSImage about it too, so raster cels share the vector outfit orientation.
        if let context = NSGraphicsContext.current?.cgContext { NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true) }
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        image.unlockFocus()
        cache[key] = image
        return image
    }
    static func menuImage(for outfit: Outfit) -> NSImage {
        let image = self.image(for: outfit, size: NSSize(width: 40, height: 32)).copy() as! NSImage
        image.size = NSSize(width: 25, height: 20)
        return image
    }
    static func write(_ image: NSImage, to path: String) throws {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try png.write(to: URL(fileURLWithPath: path))
    }
}

private func wardrobeText(_ value: String, in rect: NSRect, font: CGFloat, color: NSColor = OutfitRenderer.ink, weight: NSFont.Weight = .regular, align: NSTextAlignment = .left) {
    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = align; paragraph.lineBreakMode = .byTruncatingTail
    (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: font, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph])
}

final class OutfitTileButton: NSButton {
    var hoverChanged: ((Bool) -> Void)?
    private var area: NSTrackingArea?
    override func updateTrackingAreas() {
        if let area = area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        self.area = area; addTrackingArea(area); super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { hoverChanged?(false) }
}

final class WardrobeGridView: NSView {
    let wardrobe: WardrobeModel
    let onChoose: (Int) -> Void
    let columns: Int
    let tileWidth: CGFloat
    private let themeHeight: CGFloat
    private var buttons: [OutfitTileButton] = []
    private var hoveredID: Int?
    override var isFlipped: Bool { true }

    init(wardrobe: WardrobeModel, width: CGFloat, onChoose: @escaping (Int) -> Void) {
        self.wardrobe = wardrobe; self.onChoose = onChoose
        columns = max(3, min(5, Int((width - 32) / 156)))
        tileWidth = (width - 32 - CGFloat(columns - 1) * 12) / CGFloat(columns)
        themeHeight = 30 + CGFloat((10 + columns - 1) / columns) * 146 + 16
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 82 + themeHeight * 10))
        for outfit in OutfitCatalog.all {
            let button = OutfitTileButton(frame: cardRect(outfit.id))
            button.title = ""; button.isBordered = false; button.isTransparent = true
            button.target = self; button.action = #selector(choose(_:)); button.tag = outfit.id
            button.hoverChanged = { [weak self] entered in self?.hoveredID = entered ? outfit.id : nil; self?.needsDisplay = true }
            addSubview(button); buttons.append(button)
        }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func cardRect(_ id: Int) -> NSRect {
        let local = id % 10
        return NSRect(x: 16 + CGFloat(local % columns) * (tileWidth + 12), y: 82 + CGFloat(id / 10) * themeHeight + 30 + CGFloat(local / columns) * 146, width: tileWidth, height: 134)
    }
    func refresh() {
        for outfit in OutfitCatalog.all {
            let button = buttons[outfit.id], owned = wardrobe.isUnlocked(outfit.id)
            button.isEnabled = owned
            button.setAccessibilityLabel("\(outfit.id + 1) \(outfit.name)，\(owned ? (wardrobe.selectedID == outfit.id ? "已穿戴" : "已解锁，点击换装") : "累计\(outfit.requiredKeys)次解锁")")
        }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        OutfitRenderer.color(0xFFFDF9).setFill(); bounds.fill()
        wardrobeText("小衣柜", in: NSRect(x: 20, y: 17, width: 160, height: 31), font: 23, weight: .semibold)
        wardrobeText("\(wardrobe.unlockedCount) / 100", in: NSRect(x: bounds.width - 170, y: 22, width: 146, height: 24), font: 17, color: OutfitRenderer.color(0xA08AA9), weight: .medium, align: .right)
        let progress = wardrobe.unlockedCount < 100 ? "下一套还需 \(wardrobe.keysToNext) 次" : "下一次自动换装还需 \(wardrobe.keysToNext) 次"
        wardrobeText("累计 \(wardrobe.total) 次 · \(progress) · 点击已拥有的装扮试穿", in: NSRect(x: 20, y: 51, width: bounds.width - 40, height: 20), font: 11, color: .secondaryLabelColor)
        for theme in 0..<10 {
            let y = 82 + CGFloat(theme) * themeHeight
            wardrobeText(OutfitCatalog.themes[theme], in: NSRect(x: 20, y: y, width: 260, height: 23), font: 14, weight: .semibold)
            for outfit in OutfitCatalog.all[(theme * 10)..<(theme * 10 + 10)] {
                let rect = cardRect(outfit.id)
                guard rect.intersects(dirtyRect) else { continue }
                let owned = wardrobe.isUnlocked(outfit.id), selected = wardrobe.selectedID == outfit.id
                let path = NSBezierPath(roundedRect: rect, xRadius: 15, yRadius: 15)
                OutfitRenderer.color(selected ? 0xEEE4F2 : (hoveredID == outfit.id ? 0xF6EEF1 : 0xF8F5F0)).setFill(); path.fill()
                OutfitRenderer.color(selected ? 0xBA9CC9 : (hoveredID == outfit.id ? 0xD7C2CF : 0xE9E1DA)).setStroke(); path.lineWidth = selected ? 2 : 1; path.stroke()
                let image = OutfitThumbnails.image(for: outfit)
                image.draw(in: NSRect(x: rect.midX - 58, y: rect.minY + 4, width: 116, height: 92), from: .zero, operation: .sourceOver, fraction: owned ? 1 : 0.42, respectFlipped: true, hints: nil)
                wardrobeText(outfit.name, in: NSRect(x: rect.minX + 5, y: rect.minY + 95, width: rect.width - 10, height: 19), font: 11, color: owned ? OutfitRenderer.ink : .secondaryLabelColor, weight: .medium, align: .center)
                let state = selected ? "已穿戴" : (owned ? "点击换装" : "\(outfit.requiredKeys) 次解锁")
                wardrobeText(state, in: NSRect(x: rect.minX + 5, y: rect.minY + 114, width: rect.width - 10, height: 17), font: 10, color: selected ? OutfitRenderer.color(0xA07FAE) : .secondaryLabelColor, align: .center)
                if !owned { NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?.draw(in: NSRect(x: rect.maxX - 20, y: rect.minY + 9, width: 10, height: 12), from: .zero, operation: .sourceOver, fraction: 0.45, respectFlipped: true, hints: nil) }
            }
        }
    }
    @objc private func choose(_ sender: NSButton) {
        guard wardrobe.isUnlocked(sender.tag) else { return }
        onChoose(sender.tag); refresh()
    }
}

final class WardrobeWindowController: NSWindowController, NSWindowDelegate {
    let grid: WardrobeGridView
    var onClose: (() -> Void)?
    init(wardrobe: WardrobeModel, onChoose: @escaping (Int) -> Void) {
        let area = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = NSSize(width: min(820, max(520, area.width * 0.84)), height: min(650, max(350, area.height * 0.83)))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: size))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay; scroll.drawsBackground = false
        grid = WardrobeGridView(wardrobe: wardrobe, width: size.width, onChoose: onChoose)
        scroll.documentView = grid
        super.init(window: window)
        window.title = "敲敲 · 小衣柜"; window.isReleasedWhenClosed = false; window.delegate = self; window.acceptsMouseMovedEvents = true
        window.contentView = scroll; window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func refresh() { grid.refresh() }
    func windowWillClose(_ notification: Notification) { onClose?() }
}

final class OutfitSheetView: NSView {
    let outfits: [Outfit]
    let title: String
    override var isFlipped: Bool { true }
    init(outfits: [Outfit], title: String) {
        self.outfits = outfits; self.title = title
        super.init(frame: NSRect(x: 0, y: 0, width: 1680, height: 112 + CGFloat((outfits.count + 9) / 10) * 168 + 20))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ dirtyRect: NSRect) {
        OutfitRenderer.color(0xFFFDF9).setFill(); bounds.fill()
        wardrobeText(title, in: NSRect(x: 26, y: 23, width: 1500, height: 40), font: 27, weight: .semibold)
        wardrobeText("100 套独立造型 · 每累计 100 次有效输入解锁下一套 · 10,000 次集齐后继续轮换", in: NSRect(x: 28, y: 65, width: 1600, height: 25), font: 14, color: .secondaryLabelColor)
        for (index, outfit) in outfits.enumerated() {
            let x = 20 + CGFloat(index % 10) * 164, y = 112 + CGFloat(index / 10) * 168
            if index % 10 == 0 { wardrobeText(OutfitCatalog.themes[outfit.theme], in: NSRect(x: 26, y: y - 19, width: 400, height: 19), font: 12, color: OutfitRenderer.color(0xA88A9C), weight: .semibold) }
            let tile = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 153, height: 143), xRadius: 13, yRadius: 13)
            OutfitRenderer.color(index % 2 == 0 ? 0xF7F0EB : 0xF2EFF5).setFill(); tile.fill()
            OutfitThumbnails.image(for: outfit).draw(in: NSRect(x: x + 12, y: y + 2, width: 128, height: 104), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            wardrobeText(outfit.name, in: NSRect(x: x + 3, y: y + 107, width: 147, height: 18), font: 12, weight: .medium, align: .center)
            wardrobeText(String(format: "%03d", outfit.id + 1) + "  ·  \(outfit.requiredKeys) 次", in: NSRect(x: x + 3, y: y + 126, width: 147, height: 15), font: 10, color: .secondaryLabelColor, align: .center)
        }
    }
}

func exportWardrobe(to directory: String) throws {
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let grouped = directory + "/分组总览"
    try FileManager.default.createDirectory(atPath: grouped, withIntermediateDirectories: true)
    for outfit in OutfitCatalog.all {
        let name = String(format: "%03d", outfit.id + 1) + "_" + outfit.name + ".png"
        try OutfitThumbnails.write(OutfitThumbnails.image(for: outfit), to: directory + "/" + name)
    }
    func sheet(_ view: OutfitSheetView, path: String) {
        let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        renderPreview(view, to: path)
    }
    sheet(OutfitSheetView(outfits: OutfitCatalog.all, title: "敲敲 · 100 套装扮总览"), path: directory + "/100套装扮总览.png")
    for theme in 0..<10 {
        sheet(OutfitSheetView(outfits: Array(OutfitCatalog.all[(theme * 10)..<(theme * 10 + 10)]), title: "敲敲 · " + OutfitCatalog.themes[theme]), path: grouped + "/" + String(format: "%02d", theme + 1) + "_" + OutfitCatalog.themes[theme] + ".png")
    }
    let metadata: [[String: Any]] = OutfitCatalog.all.map { ["id": $0.id, "name": $0.name, "theme": OutfitCatalog.themes[$0.theme], "design": $0.style.rawValue, "requiredKeys": $0.requiredKeys] }
    try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: directory + "/装扮目录.json"))
    print("Rendered 100 costumes, 10 theme sheets and a full catalog to \(directory)")
}
