import Foundation

enum Slot: Int, Codable, CaseIterable, Identifiable {
    case morning, afternoon, evening
    var id: Int { rawValue }
    var title: String { ["上午", "下午", "晚上"][rawValue] }
    var icon: String { ["sunrise", "sun.max", "moon"][rawValue] }
}
enum Dates {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = .current
        c.firstWeekday = 2; c.minimumDaysInFirstWeek = 4; return c
    }
    static func key(_ date: Date) -> String {
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
    static func date(_ key: String) -> Date {
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"; return f.date(from: key) ?? calendar.startOfDay(for: Date())
    }
    static func week(_ date: Date) -> Date { calendar.dateInterval(of: .weekOfYear, for: date)!.start }
    static func add(_ days: Int, to date: Date) -> Date { calendar.date(byAdding: .day, value: days, to: date)! }
    static func days(_ date: Date) -> [Date] { (0..<7).map { add($0, to: calendar.startOfDay(for: date)) } }
    static func label(_ date: Date, _ format: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = format; return f.string(from: date)
    }
}
struct PlanTask: Codable, Identifiable, Equatable {
    var id = UUID()
    var day: String
    var slot: Slot
    var title: String
    var time = ""
    var note = ""
    var completed = false
    var courseID: UUID? = nil
    var deleted = false
    var createdAt = Date()
}
struct CourseRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var weekdays: [Int] = [2]
    var slot = Slot.morning
    var time = ""
    var location = ""
    var start = Dates.key(Date())
    var end = Dates.key(Dates.add(112, to: Date()))
    var cadence = 0
    var anchor = Dates.key(Dates.week(Date()))
    var weeks: [Int]? = nil
    func matches(_ day: Date) -> Bool {
        let key = Dates.key(day)
        guard key >= start, key <= end, weekdays.contains(Dates.calendar.component(.weekday, from: day)) else { return false }
        let delta = Dates.calendar.dateComponents([.day], from: Dates.week(Dates.date(anchor)), to: Dates.week(day)).day ?? 0
        let teachingWeek = delta / 7 + 1
        if let weeks {return teachingWeek > 0 && weeks.contains(teachingWeek)}
        return teachingWeek > 0 && (cadence == 0 || (cadence == 1 && teachingWeek % 2 == 1) || (cadence == 2 && teachingWeek % 2 == 0))
    }
}
struct DayArchive: Codable, Identifiable {
    var id: String { day }
    var day: String
    var archivedAt: Date
    var tasks: [PlanTask]
}
struct AIConfig: Codable { var baseURL = "https://api.deepseek.com"; var model = "deepseek-flash" }
struct PoolItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var note = ""
}
struct DailyQuote: Codable {
    var text: String
    var author: String
    var source: String
    var day: String
    var link: String
    var online: Bool
}
struct SuggestedTask: Codable, Identifiable {
    var id = UUID()
    var title: String
    var day: String
    var slot: Slot
    var note = ""
}
struct Database: Codable {
    var schemaVersion = 2
    var tasks: [PlanTask] = []
    var courses: [CourseRule] = []
    var archives: [DayArchive] = []
    var summaries: [String: String] = [:]
    var ai = AIConfig()
    var lastOpenedDay: String? = nil
    var followsToday = true
    var viewStart: String? = nil
    var pool: [PoolItem] = []
    var quote: DailyQuote? = nil
    enum CodingKeys: String, CodingKey { case schemaVersion, tasks, courses, archives, summaries, ai, lastOpenedDay, pool, quote, viewStart, followsToday }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = 2
        tasks = try c.decodeIfPresent([PlanTask].self, forKey: .tasks) ?? []
        courses = try c.decodeIfPresent([CourseRule].self, forKey: .courses) ?? []
        archives = try c.decodeIfPresent([DayArchive].self, forKey: .archives) ?? []
        summaries = try c.decodeIfPresent([String:String].self, forKey: .summaries) ?? [:]
        ai = try c.decodeIfPresent(AIConfig.self, forKey: .ai) ?? AIConfig()
        lastOpenedDay = try c.decodeIfPresent(String.self, forKey: .lastOpenedDay)
        followsToday = try c.decodeIfPresent(Bool.self, forKey: .followsToday) ?? true
        viewStart = try c.decodeIfPresent(String.self, forKey: .viewStart)
        pool = try c.decodeIfPresent([PoolItem].self, forKey: .pool) ?? []
        quote = try c.decodeIfPresent(DailyQuote.self, forKey: .quote)
    }
    mutating func materialize(_ week: Date, now: Date = Date()) {
        for day in Dates.days(week) where Dates.key(day) >= Dates.key(now) {
            for course in courses where course.matches(day) {
                let key = Dates.key(day)
                if !tasks.contains(where: { $0.day == key && $0.courseID == course.id }) {
                    tasks.append(PlanTask(day: key, slot: course.slot, title: course.title, time: course.time, note: course.location, courseID: course.id))
                }
            }
        }
    }
    mutating func rollover(now: Date = Date()) {
        let today = Dates.key(now)
        if let last = lastOpenedDay, last < today {
            for course in courses {
                var day = Dates.date(max(last, course.start))
                let stop = min(today, Dates.key(Dates.add(1, to: Dates.date(course.end))))
                while Dates.key(day) < stop {
                    let key = Dates.key(day)
                    if course.matches(day), !tasks.contains(where: { $0.day == key && $0.courseID == course.id }) {
                        tasks.append(PlanTask(day: key, slot: course.slot, title: course.title, time: course.time, note: course.location, courseID: course.id))
                    }
                    day = Dates.add(1, to: day)
                }
            }
        }
        let archived = Set(archives.map(\.day))
        let pastDays = Set(tasks.filter { $0.day < today }.map(\.day)).subtracting(archived)
        for day in pastDays.sorted() { archives.append(DayArchive(day: day, archivedAt: now, tasks: tasks.filter { $0.day == day && !$0.deleted })) }
        lastOpenedDay = today
        materialize(Dates.week(now), now: now)
    }
    mutating func updateCourse(_ rule: CourseRule, now: Date = Date()) {
        if let i = courses.firstIndex(where: { $0.id == rule.id }) { courses[i] = rule } else { courses.append(rule) }
        tasks.removeAll { $0.courseID == rule.id && $0.day >= Dates.key(now) && !$0.completed && !$0.deleted }
    }
    mutating func removeCourse(_ id: UUID, now: Date = Date()) {
        courses.removeAll { $0.id == id }
        tasks.removeAll { $0.courseID == id && $0.day >= Dates.key(now) && !$0.completed }
    }
    func tasks(in week: Date) -> [PlanTask] {
        let keys = Set(Dates.days(week).map(Dates.key)); return tasks.filter { keys.contains($0.day) && !$0.deleted }
    }
    func report(week: Date) -> String {
        var lines = ["# 周间 · 七日记录", "", "\(Dates.key(week)) — \(Dates.key(Dates.add(6, to: week)))", ""]
        for day in Dates.days(week) {
            lines.append("## \(Dates.label(day, "M月d日 EEEE"))")
            for slot in Slot.allCases {
                lines.append("### \(slot.title)")
                for t in tasks.filter({ $0.day == Dates.key(day) && $0.slot == slot && !$0.deleted }) {
                    lines.append("- [\(t.completed ? "x" : " ")] \(t.courseID == nil ? "" : "[课程] ")\(t.time) \(t.title)")
                    if !t.note.isEmpty { lines.append("  记录：\(t.note)") }
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
func runModelTests() throws {
    var count = 0
    func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
        if !condition() { throw NSError(domain: "TestFailure", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
        count += 1; print("PASS \(name)")
    }
    let monday = Dates.date("2026-10-26"), tuesday = Dates.date("2026-10-27")
    var db = Database()
    var rule = CourseRule(title: "高等数学", weekdays: [2, 4], start: "2026-10-26", end: "2026-11-30", anchor: "2026-10-26")
    db.courses = [rule]; db.rollover(now: monday)
    try check(db.tasks.count == 2, "weekly course instances")
    db.rollover(now: monday); try check(db.tasks.count == 2, "idempotent materialization")
    db.tasks[0].completed = true; db.rollover(now: tuesday)
    try check(db.archives.count == 1 && db.archives[0].tasks[0].completed, "midnight archives completion")
    db.tasks[0].title = "补记"
    try check(db.archives[0].tasks[0].title == "高等数学", "archive is immutable snapshot")
    db.rollover(now: tuesday); try check(db.archives.count == 1, "no duplicate archive")
    rule.title = "数学 · 新教室"; db.updateCourse(rule, now: tuesday); db.materialize(monday, now: tuesday)
    try check(db.tasks.first(where: { $0.day == "2026-10-26" })?.title == "补记", "course edit preserves history")
    try check(db.tasks.first(where: { $0.day == "2026-10-28" })?.title == "数学 · 新教室", "course edit updates future")
    let i = db.tasks.firstIndex(where: { $0.day == "2026-10-28" })!
    db.tasks[i].deleted = true; db.materialize(monday, now: tuesday)
    try check(db.tasks.filter { $0.day == "2026-10-28" && !$0.deleted }.isEmpty, "deleted occurrence stays deleted")
    db.materialize(Dates.add(7, to: monday), now: tuesday)
    try check(db.tasks.contains { $0.day == "2026-11-02" && $0.title == rule.title }, "new week repeats courses")
    rule.cadence = 1
    try check(rule.matches(monday) && !rule.matches(Dates.add(7, to: monday)), "odd teaching weeks")
    rule.cadence = 2
    try check(!rule.matches(monday) && rule.matches(Dates.add(7, to: monday)), "even teaching weeks")
    var missed = Database(); missed.courses = [CourseRule(title: "每日课", weekdays: [2,3,4,5,6], start: "2026-10-26", end: "2026-11-30", anchor: "2026-10-26")]
    missed.rollover(now: monday); missed.rollover(now: Dates.date("2026-11-04"))
    try check(missed.archives.contains { $0.day == "2026-11-03" }, "relaunch backfills missed days")
    let encoded = try JSONEncoder().encode(db), decoded = try JSONDecoder().decode(Database.self, from: JSONEncoder().encode(db))
    try check(!encoded.isEmpty && decoded.tasks == db.tasks && decoded.archives.count == db.archives.count, "JSON round trip")
    try check(Dates.key(Dates.week(Dates.date("2026-11-01"))) == "2026-10-26", "Sunday belongs to Monday week")
    try check(!rule.matches(Dates.date("2026-12-02")), "semester boundary")
    print("All \(count) model checks passed.")
}
