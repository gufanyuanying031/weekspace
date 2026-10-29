import Foundation
@main struct IntegrationTests {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("weekspace-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func check(_ ok: Bool, _ name: String) throws {
            guard ok else { throw NSError(domain:"Integration",code:1,userInfo:[NSLocalizedDescriptionKey:name]) }
            print("PASS \(name)")
        }
        let store = PlanStore(directoryOverride: root)
        let task = PlanTask(day: Dates.key(Date()), slot: .evening, title: "持久化测试")
        store.put(task); store.setSummary("人工复盘", week: store.selectedWeek)
        let restored = PlanStore(directoryOverride: root)
        try check(restored.db.tasks.contains(where: {$0.id == task.id}), "task survives store restart")
        try check(restored.summary(restored.selectedWeek) == "人工复盘", "summary survives store restart")
        try check(FileManager.default.fileExists(atPath: root.appendingPathComponent("planner.previous.json").path), "previous valid save retained")
        restored.delete(task); restored.undoDelete()
        try check(restored.db.tasks.first?.deleted == false, "delete undo persists")
        restored.addPool("重复安排模板")
        let template = restored.db.pool[0]
        restored.placePool(template.id,day:Date(),slot:.morning)
        restored.placePool(template.id,day:Date(),slot:.evening)
        let copies = restored.db.tasks.filter {$0.title == template.title}
        try check(copies.count == 2 && Set(copies.map(\.id)).count == 2 && restored.db.pool.count == 1,"repeated pool placement creates independent tasks")
        let currentDay = Dates.calendar.startOfDay(for:Date())
        restored.selectStart(Dates.add(-1,to:currentDay));restored.setSummary("自定义七日总结",week:restored.selectedWeek)
        restored.navigate(1)
        try check(Dates.key(restored.selectedWeek) == Dates.key(currentDay) && restored.summary(restored.selectedWeek) == "人工复盘","one-day navigation isolates summaries")
        restored.navigate(-1)
        try check(restored.summary(restored.selectedWeek) == "自定义七日总结","custom range summary retained")
        restored.setSummary("人工复盘",week:restored.selectedWeek)
        if CommandLine.arguments.count > 2 {
            let fixtureRoot = URL(fileURLWithPath:CommandLine.arguments[2])
            let workbook = try CourseImporter.read(fixtureRoot.appendingPathComponent("list.xlsx"))
            let rules = CourseImporter.parse(tables:workbook,anchor:Dates.date("2026-09-07"))
            try check(rules.count == 2 && rules.first?.rule.title == "数据结构" && rules.first?.rule.time == "09:00–10:40","real XLSX zip XML read")
            let grid = try CourseImporter.read(fixtureRoot.appendingPathComponent("grid.xlsx"))
            let gridRules = CourseImporter.parse(tables:grid,anchor:Dates.date("2026-09-07"))
            try check(gridRules.count == 2 && gridRules.first?.rule.title == "数学" && gridRules.last?.rule.slot == .evening,"XLSX grid and inline strings read")
        }
        let oldRoot = root.appendingPathComponent("legacy",isDirectory:true)
        try FileManager.default.createDirectory(at:oldRoot,withIntermediateDirectories:true)
        var oldJSON = try JSONSerialization.jsonObject(with:JSONEncoder().encode(restored.db)) as! [String:Any]
        oldJSON["schemaVersion"] = 1;oldJSON.removeValue(forKey:"pool");oldJSON.removeValue(forKey:"quote")
        let oldData = try JSONSerialization.data(withJSONObject:oldJSON)
        try oldData.write(to:oldRoot.appendingPathComponent("planner.json"))
        let updated = PlanStore(directoryOverride:oldRoot)
        try check(updated.canWrite && (try Data(contentsOf:oldRoot.appendingPathComponent("planner.pre-v002.json"))) == oldData,"migration preserves exact v001 backup")
        let credentialRoot = root.appendingPathComponent("private",isDirectory:true)
        try KeyStore.write("test-only-not-a-real-key",to:credentialRoot)
        let attributes = try FileManager.default.attributesOfItem(atPath:credentialRoot.appendingPathComponent("api-key").path)
        try check(KeyStore.read(from:credentialRoot) == "test-only-not-a-real-key" && (attributes[.posixPermissions] as? Int) == 0o600,"local credential file private permissions without Keychain")
        try KeyStore.write("",to:credentialRoot)
        try check(KeyStore.read(from:credentialRoot).isEmpty,"local credential removal without OS authentication")
        if CommandLine.arguments.count > 2 {
            let complex = URL(fileURLWithPath:CommandLine.arguments[2]).appendingPathComponent("complex.xlsx")
            let parsed = CourseImporter.parse(tables:try CourseImporter.read(complex),anchor:Dates.date("2026-09-07"))
            try check(parsed.count == 4 && Set(parsed.map{$0.rule.title}).count == 2,"complex grid excludes detail headers and prose")
            let workshops = parsed.filter{$0.rule.title == "创意工作坊"}
            try check(workshops.count == 2 && workshops.first?.rule.weeks != workshops.last?.rule.weeks,"weekday-specific sparse teaching weeks")
            try check(parsed.first{$0.rule.title == "学习分享" && $0.rule.weekdays == [7]}?.rule.weeks == [4],"exceptional Saturday teaching week")
            try check(workshops.allSatisfy{$0.rule.time == "09:00–10:40"},"consecutive periods retain full time range")
        }
        let rolling = PlanStore(directoryOverride:root.appendingPathComponent("rolling"))
        rolling.db.lastOpenedDay = "2026-10-29";rolling.followCurrentWeek = true
        rolling.selectedWeek = Dates.date("2026-10-29")
        rolling.db.courses = [CourseRule(title:"Thursday",weekdays:[5],start:"2026-10-26",end:"2026-12-31",anchor:"2026-10-26")]
        rolling.rollover(now:Dates.date("2026-10-30"))
        try check(rolling.db.tasks.contains{$0.day == "2026-11-05"},"rollover materializes newly visible seventh day")
        let port = CommandLine.arguments[1]
        restored.db.ai.baseURL = "http://127.0.0.1:\(port)/v1"
        restored.db.ai.model = "test-success"
        await restored.generate(prompt:"仅用于本机接口验证的虚构记录", week:restored.selectedWeek, apiKey:"")
        try check(restored.error == nil && restored.summary(restored.selectedWeek).contains("本地模拟复盘"), "compatible API success parsed")
        try check(restored.summary(restored.selectedWeek).hasPrefix("人工复盘"), "AI preserves manual summary")
        restored.db.ai.model = "test-error"; restored.error = nil
        let before = restored.summary(restored.selectedWeek)
        await restored.generate(prompt:"test",week:restored.selectedWeek,apiKey:"")
        try check(restored.error?.contains("HTTP 401") == true && restored.summary(restored.selectedWeek) == before, "HTTP error preserves data")
        restored.db.ai.model = "test-malformed"; restored.error = nil
        await restored.generate(prompt:"test",week:restored.selectedWeek,apiKey:"")
        try check(restored.error?.contains("未返回可用") == true, "malformed response handled")
        try Data("invalid data".utf8).write(to:root.appendingPathComponent("planner.json"))
        let broken = PlanStore(directoryOverride:root)
        broken.put(task)
        try check(!broken.canWrite && (try String(contentsOf:root.appendingPathComponent("planner.json"),encoding:.utf8)) == "invalid data", "unreadable database never overwritten")
        print("All integration checks passed. No external model called.")
    }
}
