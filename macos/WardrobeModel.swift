import Foundation

enum OutfitStyle: String, CaseIterable {
    case bear, bunny, fox, antlers, devil, halo, frog, bee, butterfly, unicorn
    case cap, beret, bucket, beanie, aviator, detective, sunglasses, glasses, headphones, sleepCap
    case chef, doctor, nurse, firefighter, sheriff, hardhat, astronaut, captain, topHat, graduate
    case crown, tiara, wizard, witch, warrior, knight, pirate, ninja, elf, dragon
    case strawberry, cherry, watermelon, lemon, peach, grape, pineapple, donut, cupcake, icecream
    case sunflower, daisy, rose, tulip, clover, mushroom, cactus, pinecone, sprout, lotus
    case sun, moon, saturn, star, comet, rainbow, cloud, lightning, snowflake, drop
    case santa, reindeer, pumpkin, ghost, party, mask, wreath, lantern, ingot, hibiscus
    case keycap, gear, pencil, painter, camera, postman, musician, sport, gardener, barista
    case cyber, steampunk, goldenCrown, crystalCrown, ribbonTopHat, jewelCrown, galaxyHeadset, spacePilot, neonWizard, aurora
}

struct Outfit: Identifiable {
    let id: Int
    let name: String
    let theme: Int
    let style: OutfitStyle
    let primary: UInt32
    let secondary: UInt32
    let collar: Int
    var requiredKeys: Int { (id + 1) * WardrobeModel.keysPerOutfit }
}

enum OutfitCatalog {
    static let themes = ["动物派对", "日常穿搭", "职业猫猫", "奇幻冒险", "甜品小铺", "自然花园", "星空旅行", "节庆派对", "桌面工坊", "限定收藏"]
    static let names = [
        "奶糖小熊", "棉花小兔", "枫叶小狐", "森林小鹿", "淘气小恶魔", "云端小天使", "荷塘小青蛙", "蜂蜜小蜜蜂", "蝶翼小精灵", "梦境独角兽",
        "薄荷棒球帽", "莓果贝雷帽", "海盐渔夫帽", "云朵毛线帽", "复古飞行帽", "格纹小侦探", "夏日墨镜", "圆框小书虫", "音乐耳机", "星星睡帽",
        "奶油小厨师", "温柔小医生", "元气小护士", "勇敢消防员", "西部小警长", "认真建筑师", "月球宇航员", "远航小船长", "礼帽魔术师", "毕业小博士",
        "蜂蜜小国王", "珍珠小公主", "星月小法师", "南瓜小女巫", "翎羽小勇士", "银甲小骑士", "寻宝小海盗", "月影小忍者", "叶语小精灵", "翡翠小龙",
        "草莓奶昔", "樱桃汽水", "西瓜冰沙", "柠檬苏打", "蜜桃乌龙", "葡萄果冻", "菠萝假日", "糖霜甜甜圈", "奶油纸杯糕", "彩虹冰淇淋",
        "向日葵早安", "雏菊午后", "玫瑰来信", "郁金香春日", "幸运四叶草", "森林小蘑菇", "沙漠仙人掌", "秋日小松果", "发芽啦", "荷叶小雨衣",
        "暖阳小太阳", "晚安小月亮", "土星旅行家", "闪闪小星星", "许愿小流星", "雨后彩虹", "软绵小云朵", "能量小闪电", "初雪小雪花", "晶莹小雨滴",
        "圣诞小红帽", "圣诞小麋鹿", "万圣小南瓜", "害羞小幽灵", "生日快乐帽", "月光舞会", "春日花环", "元宵小灯笼", "招财小元宝", "海边扶桑花",
        "键盘小工匠", "齿轮工程师", "铅笔小作家", "调色小画家", "快门摄影师", "云朵小邮差", "旋律小乐手", "活力运动员", "阳台小园丁", "拿铁咖啡师",
        "霓虹护目镜", "蒸汽时钟匠", "日曜金王冠", "冰晶小王冠", "蝴蝶结绅士", "宝石小女王", "银河电台", "星际飞行员", "极夜小巫师", "极光守护者"
    ]
    static let all: [Outfit] = {
        precondition(names.count == 100 && OutfitStyle.allCases.count == 100)
        let colors: [UInt32] = [0xD993A5, 0x8FB9A8, 0xAAA0CC, 0x89B6D0, 0xDBB86D, 0xDA977A, 0x7DA8A3, 0x75859F, 0xB293AF, 0xC7AC8F]
        return OutfitStyle.allCases.enumerated().map { id, style in
            Outfit(id: id, name: names[id], theme: id / 10, style: style, primary: colors[(id * 3 + id / 10) % colors.count], secondary: colors[(id * 7 + 4) % colors.count], collar: (id + id / 10) % 10)
        }
    }()
}

struct SavedWardrobe: Codable {
    var selectedID: Int?
    var automatic: Bool
    var lastMilestone: Int
}

struct WardrobeUpdate {
    var newUnlocks = 0
    var equippedChanged = false
    var milestoneAdvanced = false
}

final class WardrobeModel {
    static let keysPerOutfit = 100
    private(set) var total: Int
    private(set) var selectedID: Int?
    private(set) var automatic: Bool
    private(set) var changedAt = Date.distantPast
    var unlockedCount: Int { min(OutfitCatalog.all.count, total / Self.keysPerOutfit) }
    var selected: Outfit? { selectedID.map { OutfitCatalog.all[$0] } }
    var keysToNext: Int { Self.keysPerOutfit - total % Self.keysPerOutfit }

    init(total: Int, saved: SavedWardrobe? = nil) {
        self.total = max(0, total)
        automatic = saved?.automatic ?? true
        let currentMilestone = self.total / Self.keysPerOutfit
        let validSaved = saved?.selectedID.flatMap { (0..<min(100, currentMilestone)).contains($0) ? $0 : nil }
        if let saved = saved, !automatic || saved.lastMilestone >= currentMilestone {
            selectedID = validSaved
        } else {
            selectedID = currentMilestone > 0 ? (currentMilestone - 1) % 100 : nil
        }
    }

    func isUnlocked(_ id: Int) -> Bool { (0..<unlockedCount).contains(id) }

    @discardableResult
    func synchronize(total newTotal: Int, at now: Date = Date()) -> WardrobeUpdate {
        guard newTotal >= total else { return WardrobeUpdate() }
        let oldCount = unlockedCount, oldMilestone = total / Self.keysPerOutfit
        total = newTotal
        let milestone = total / Self.keysPerOutfit
        var update = WardrobeUpdate(newUnlocks: unlockedCount - oldCount, milestoneAdvanced: milestone > oldMilestone)
        if automatic && milestone > oldMilestone && milestone > 0 {
            let next = (milestone - 1) % 100
            update.equippedChanged = selectedID != next
            selectedID = next
            if update.equippedChanged { changedAt = now }
        }
        return update
    }

    @discardableResult
    func equip(_ id: Int?, at now: Date = Date()) -> Bool {
        if let id = id, !isUnlocked(id) { return false }
        selectedID = id; changedAt = now
        return true
    }

    func setAutomatic(_ enabled: Bool, at now: Date = Date()) {
        automatic = enabled
        if enabled, total >= Self.keysPerOutfit { _ = equip((total / Self.keysPerOutfit - 1) % 100, at: now) }
    }

    func saved() -> SavedWardrobe {
        SavedWardrobe(selectedID: selectedID, automatic: automatic, lastMilestone: total / Self.keysPerOutfit)
    }
}

@discardableResult
func runWardrobeTests() -> Bool {
    var failures: [String] = []; var count = 0
    func check(_ value: @autoclosure () -> Bool, _ label: String) { count += 1; if !value() { failures.append(label) } }
    check(OutfitCatalog.all.count == 100, "exactly one hundred outfits")
    check(Set(OutfitCatalog.all.map(\.id)).count == 100 && Set(OutfitCatalog.names).count == 100, "unique stable IDs and names")
    check(Set(OutfitCatalog.all.map(\.style)).count == 100, "one hundred distinct primary costume designs")
    check(OutfitCatalog.themes.count == 10 && (0..<10).allSatisfy { theme in OutfitCatalog.all.filter { $0.theme == theme }.count == 10 }, "ten themes of ten outfits")
    check(OutfitCatalog.all.first?.requiredKeys == 100 && OutfitCatalog.all.last?.requiredKeys == 10000, "unlock thresholds are explicit")
    let w = WardrobeModel(total: 0)
    check(w.unlockedCount == 0 && w.selected == nil && w.keysToNext == 100, "starts as original avatar")
    check(w.synchronize(total: 99).newUnlocks == 0 && w.selected == nil, "no premature unlock")
    let first = w.synchronize(total: 100)
    check(first.newUnlocks == 1 && first.equippedChanged && w.selectedID == 0, "hundredth key unlocks and auto equips first outfit")
    check(w.synchronize(total: 100).newUnlocks == 0, "same milestone cannot grant twice")
    check(w.synchronize(total: 199).equippedChanged == false && w.selectedID == 0, "keeps outfit between milestones")
    check(w.synchronize(total: 200).newUnlocks == 1 && w.selectedID == 1, "next milestone changes outfit")
    check(!w.equip(99) && w.selectedID == 1, "locked outfit cannot be equipped")
    check(w.equip(0) && w.selectedID == 0, "owned outfit can be selected manually")
    w.synchronize(total: 300)
    check(w.selectedID == 2, "manual selection preserves next automatic change")
    w.setAutomatic(false)
    let fourth = w.synchronize(total: 400)
    check(fourth.newUnlocks == 1 && !fourth.equippedChanged && w.selectedID == 2, "manual mode still unlocks without changing outfit")
    w.setAutomatic(true)
    check(w.selectedID == 3, "enabling auto equips current milestone")
    check(w.equip(nil) && w.selected == nil, "original appearance is selectable")
    let restore = WardrobeModel(total: w.total, saved: w.saved())
    check(restore.selectedID == nil && restore.automatic, "original appearance selection survives restart")
    w.synchronize(total: 10000)
    check(w.unlockedCount == 100 && w.selectedID == 99, "all one hundred unlock at ten thousand")
    let cycle = w.synchronize(total: 10100)
    check(cycle.newUnlocks == 0 && w.selectedID == 0, "after collecting all outfits auto continues cycling")
    w.synchronize(total: 10200)
    check(w.selectedID == 1 && w.unlockedCount == 100, "cycling does not create phantom outfits")
    check(w.synchronize(total: 0).newUnlocks == 0 && w.total == 10200, "progress cannot be relocked by a stale count")
    let recover = WardrobeModel(total: 700, saved: SavedWardrobe(selectedID: 1, automatic: true, lastMilestone: 2))
    check(recover.selectedID == 6, "incomplete old save recovers missed auto equip")
    let manual = WardrobeModel(total: 700, saved: SavedWardrobe(selectedID: 1, automatic: false, lastMilestone: 2))
    check(manual.selectedID == 1, "manual preference is preserved across upgrades")
    let invalid = WardrobeModel(total: 100, saved: SavedWardrobe(selectedID: 999, automatic: false, lastMilestone: 1))
    check(invalid.selected == nil, "invalid saved ID is safely ignored")
    let data = try! JSONEncoder().encode(w.saved())
    check((try? JSONDecoder().decode(SavedWardrobe.self, from: data))?.selectedID == 1, "wardrobe save round trip")
    // Drive all 100 rewards through the actual counter, crossing midnight and
    // restoring both save records periodically, without touching user preferences.
    var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = utc.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 23, minute: 59, second: 50))!
    var counter = CounterModel(now: start, calendar: utc)
    var collection = WardrobeModel(total: 0)
    var earned: [Int] = [], restoreOK = true
    for i in 0..<10000 {
        let time = start.addingTimeInterval(Double(i) * 0.02)
        if counter.record(keyCode: 0, at: time) {
            let update = collection.synchronize(total: counter.lifetimeCount, at: time)
            if update.newUnlocks > 0, let id = collection.selectedID { earned.append(id) }
        }
        if (i + 1) % 1000 == 0 {
            let oldID = collection.selectedID
            let c = try! JSONDecoder().decode(SavedCounter.self, from: JSONEncoder().encode(counter.saved()))
            let s = try! JSONDecoder().decode(SavedWardrobe.self, from: JSONEncoder().encode(collection.saved()))
            counter = CounterModel(now: time, saved: c, calendar: utc)
            collection = WardrobeModel(total: counter.lifetimeCount, saved: s)
            restoreOK = restoreOK && collection.selectedID == oldID
        }
    }
    check(earned == Array(0..<100), "all 100 thresholds award the correct outfit exactly once")
    check(counter.lifetimeCount == 10000 && counter.todayCount < counter.lifetimeCount && collection.unlockedCount == 100, "midnight does not reset wardrobe progress during real counting")
    check(restoreOK && collection.selectedID == 99, "ten save/restore cycles preserve equipped outfit and progress")
    print("Wardrobe tests: \(count - failures.count)/\(count) passed")
    failures.forEach { print("FAIL: \($0)") }; return failures.isEmpty
}
