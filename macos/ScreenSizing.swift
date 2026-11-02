import Foundation

/// AppKit screen geometry is in points. Retina backing pixels are handled by AppKit,
/// so a 2x backing scale must not be applied a second time to the window dimensions.
enum ScreenSizing {
    static let baseSize = CGSize(width: 264, height: 236)
    static let minimumPreference: CGFloat = 0.50
    static let maximumPreference: CGFloat = 1.80

    enum Anchor { case bottomRight, topLeft, center }

    static func preference(_ value: CGFloat) -> CGFloat {
        guard value.isFinite, value > 0 else { return 1 }
        return min(maximumPreference, max(minimumPreference, value))
    }

    static func recommendedScale(for area: CGSize) -> CGFloat {
        guard area.width.isFinite, area.height.isFinite, area.width > 0, area.height > 0 else { return 1 }
        // A compact avatar; use logical desktop dimensions, not physical Retina pixels.
        let proportional = min(area.width / 1440, area.height / 900) * 0.90
        return min(1.25, max(0.80, proportional))
    }

    static func scale(for area: CGSize, preference value: CGFloat) -> CGFloat {
        guard area.width > 0, area.height > 0, area.width.isFinite, area.height.isFinite else { return 1 }
        let margin = min(16, min(area.width, area.height) * 0.04)
        let fit = min((area.width - 2 * margin) / baseSize.width, (area.height - 2 * margin) / baseSize.height)
        return min(recommendedScale(for: area) * preference(value), fit)
    }

    static func frame(from old: CGRect, in area: CGRect, preference value: CGFloat, anchor: Anchor = .bottomRight) -> CGRect {
        let s = scale(for: area.size, preference: value)
        let size = CGSize(width: baseSize.width * s, height: baseSize.height * s)
        var origin: CGPoint
        switch anchor {
        case .bottomRight: origin = CGPoint(x: old.maxX - size.width, y: old.minY)
        case .topLeft: origin = CGPoint(x: old.minX, y: old.maxY - size.height)
        case .center: origin = CGPoint(x: old.midX - size.width / 2, y: old.midY - size.height / 2)
        }
        origin.x = min(max(origin.x, area.minX), max(area.minX, area.maxX - size.width))
        origin.y = min(max(origin.y, area.minY), max(area.minY, area.maxY - size.height))
        return CGRect(origin: origin, size: size)
    }

    static func screenIndex(for window: CGRect, screens: [CGRect], pointer: CGPoint? = nil) -> Int? {
        guard !screens.isEmpty else { return nil }
        if let pointer = pointer, let index = screens.firstIndex(where: { $0.contains(pointer) }) { return index }
        var bestIndex = 0
        var bestArea: CGFloat = 0
        for (index, screen) in screens.enumerated() {
            let overlap = screen.intersection(window)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > bestArea { bestIndex = index; bestArea = area }
        }
        if bestArea > 0 { return bestIndex }
        // If a monitor disappears, recover onto the closest remaining monitor.
        return screens.indices.min { lhs, rhs in
            func distance(_ index: Int) -> CGFloat {
                let rect = screens[index]
                let dx = max(rect.minX - window.midX, 0, window.midX - rect.maxX)
                let dy = max(rect.minY - window.midY, 0, window.midY - rect.maxY)
                return dx * dx + dy * dy
            }
            return distance(lhs) < distance(rhs)
        }
    }
}

@discardableResult
func runSizingTests() -> Bool {
    var failures: [String] = []
    var count = 0
    func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        count += 1
        if !condition() { failures.append(message) }
    }
    func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.0001 }
    let small = CGSize(width: 1280, height: 720)
    let standard = CGSize(width: 1920, height: 1080)
    let large = CGSize(width: 3840, height: 2160)
    check(ScreenSizing.recommendedScale(for: small) < ScreenSizing.recommendedScale(for: standard), "larger desktop gets larger recommended pet")
    check(ScreenSizing.recommendedScale(for: standard) < ScreenSizing.recommendedScale(for: large), "4K 1x desktop scales up")
    check(near(ScreenSizing.recommendedScale(for: large), 1.25), "large desktop size remains bounded")
    check(near(ScreenSizing.scale(for: standard, preference: 1.5), ScreenSizing.scale(for: standard, preference: 1) * 1.5), "manual preference multiplies automatic size")
    check(near(ScreenSizing.scale(for: standard, preference: 0.5), ScreenSizing.scale(for: standard, preference: 1) * 0.5), "manual minimum halves automatic size")
    check(near(ScreenSizing.preference(0), 1), "missing preference defaults to recommended")
    check(near(ScreenSizing.preference(.nan), 1), "NaN preference is rejected")
    check(near(ScreenSizing.preference(.infinity), 1), "infinite preference is rejected")
    check(near(ScreenSizing.preference(0.1), 0.5), "manual lower bound")
    check(near(ScreenSizing.preference(5), 1.8), "manual upper bound")
    check(near(ScreenSizing.recommendedScale(for: .zero), 1), "invalid display geometry has safe fallback")
    let area = CGRect(origin: CGPoint(x: 20, y: 40), size: standard)
    let old = CGRect(x: 1000, y: 300, width: 332, height: 350)
    let right = ScreenSizing.frame(from: old, in: area, preference: 1)
    check(near(right.maxX, old.maxX) && near(right.minY, old.minY), "menu scaling keeps bottom-right anchor")
    let top = ScreenSizing.frame(from: old, in: area, preference: 1.5, anchor: .topLeft)
    check(near(top.minX, old.minX) && near(top.maxY, old.maxY), "grip scaling keeps top-left anchor")
    let center = ScreenSizing.frame(from: old, in: area, preference: 1, anchor: .center)
    check(near(center.midX, old.midX) && near(center.midY, old.midY), "center anchor remains stable")
    check(near(right.width / right.height, ScreenSizing.baseSize.width / ScreenSizing.baseSize.height), "aspect ratio is preserved")
    let tinyArea = CGRect(x: 0, y: 0, width: 200, height: 160)
    let tiny = ScreenSizing.frame(from: old, in: tinyArea, preference: 1.8)
    check(tinyArea.contains(tiny), "large manual preference fits tiny screen")
    let microscopicArea = CGRect(x: 0, y: 0, width: 64, height: 40)
    check(microscopicArea.contains(ScreenSizing.frame(from: old, in: microscopicArea, preference: 1.8)), "fit guard handles unusually small workspace")
    let leftArea = CGRect(x: -1920, y: -400, width: 1920, height: 1080)
    let relocated = ScreenSizing.frame(from: old, in: leftArea, preference: 1)
    check(leftArea.contains(relocated), "negative screen coordinates remain in bounds")
    let portrait = CGRect(x: 0, y: 0, width: 1080, height: 1920)
    check(portrait.contains(ScreenSizing.frame(from: old, in: portrait, preference: 1.8)), "portrait display fits pet")
    let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: -200, width: 2560, height: 1440)]
    let crossing = CGRect(x: 1400, y: 300, width: 332, height: 350)
    check(ScreenSizing.screenIndex(for: crossing, screens: screens) == 1, "screen is selected by greatest overlap")
    check(ScreenSizing.screenIndex(for: crossing, screens: screens, pointer: CGPoint(x: 1430, y: 400)) == 0, "drag release follows cursor's target screen")
    check(ScreenSizing.screenIndex(for: old, screens: []) == nil, "no screens does not crash")
    check(ScreenSizing.screenIndex(for: CGRect(x: -900, y: 200, width: 332, height: 350), screens: screens) == 0, "disconnected monitor falls back to nearest display")
    let smallFrame = ScreenSizing.frame(from: old, in: CGRect(origin: .zero, size: small), preference: 1.25)
    let bigFrame = ScreenSizing.frame(from: old, in: CGRect(origin: .zero, size: large), preference: 1.25)
    check(bigFrame.width > smallFrame.width, "same preference adapts across monitors")
    let capped = ScreenSizing.frame(from: old, in: tinyArea, preference: 1.8)
    let recovered = ScreenSizing.frame(from: capped, in: area, preference: 1.8)
    check(near(recovered.width, ScreenSizing.baseSize.width * ScreenSizing.scale(for: standard, preference: 1.8)), "temporary fit cap does not lose saved preference")
    print("Sizing tests: \(count - failures.count)/\(count) passed")
    failures.forEach { print("FAIL: \($0)") }
    return failures.isEmpty
}
