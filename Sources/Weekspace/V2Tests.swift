import Foundation
func runV2Tests() throws {
    var count = 0
    func check(_ value:Bool,_ name:String) throws {guard value else {throw AppError.message(name)};count += 1;print("PASS v002 \(name)")}
    let start = Dates.date("2026-10-28")
    try check(Dates.days(start).map(Dates.key) == ["2026-10-28","2026-10-29","2026-10-30","2026-10-31","2026-11-01","2026-11-02","2026-11-03"],"arbitrary seven days cross month")
    var db = Database()
    for key in ["2026-10-26","2026-10-28","2026-11-03","2026-11-04"] {db.tasks.append(PlanTask(day:key,slot:.morning,title:key))}
    try check(db.tasks(in:start).map(\.day) == ["2026-10-28","2026-11-03"],"summary range excludes outside days")
    try check(db.report(week:start).contains("2026-10-28 — 2026-11-03") && !db.report(week:start).contains("## 10月26日"),"report uses exact selected range")
    db.courses = [CourseRule(title:"课程",weekdays:[2,5],start:"2026-10-26",end:"2026-12-31",anchor:"2026-10-26")]
    db.materialize(start,now:start)
    try check(db.tasks.contains{$0.day == "2026-11-02" && $0.courseID != nil} && db.tasks.contains{$0.day == "2026-10-29" && $0.courseID != nil},"course generation across calendar weeks")
    var legacy = try JSONSerialization.jsonObject(with:JSONEncoder().encode(db)) as! [String:Any]
    legacy.removeValue(forKey:"pool");legacy.removeValue(forKey:"quote");legacy["schemaVersion"] = 1
    let migrated = try JSONDecoder().decode(Database.self,from:JSONSerialization.data(withJSONObject:legacy))
    try check(migrated.tasks == db.tasks && migrated.pool.isEmpty && migrated.schemaVersion == 2,"v001 database migration")
    let csv = "课程名称,星期,时段,开始时间,结束时间,教室,单双周\n数据结构,周一,上午,08:00,09:40,A203,单周\n算法,周四,下午,14:00,15:40,B101,每周"
    let table = SheetTable(name:"列表",rows:CourseImporter.delimited(csv,separator:","))
    let parsed = CourseImporter.parse(tables:[table],anchor:Dates.date("2026-09-07"))
    try check(parsed.count == 2 && parsed[0].rule.weekdays == [2] && parsed[0].rule.cadence == 1,"CSV weekday and teaching cadence")
    try check(parsed[0].rule.time == "08:00–09:40" && parsed[1].rule.slot == .afternoon,"CSV times and periods")
    let multiline = CourseImporter.delimited("课程,备注\n论文,\"第一行\n第二行,含逗号\"",separator:",")
    try check(multiline.count == 2 && multiline[1][1] == "第一行\n第二行,含逗号","quoted multiline CSV")
    let grid = SheetTable(name:"网格",rows:[["时段","周一","周二","周三","周四","周五"],["上午","数学","","英语","",""],["晚上","","算法","","",""]])
    let gridParsed = CourseImporter.parse(tables:[grid],anchor:start)
    try check(gridParsed.count == 3 && gridParsed.last?.rule.slot == .evening,"weekday grid table")
    try check(CourseImporter.normalTime("0.375") == "09:00" && CourseImporter.normalDate("2026/9/7") == "2026-09-07","Excel numeric time and date normalization")
    try check(ClockTime.validRange("09:00–10:00") && !ClockTime.validRange("10:00–09:00") && !ClockTime.validRange("26:00–27:00"),"time picker range validation")
    let response = "[{\"title\":\"阅读\",\"day\":\"2026-10-29\",\"slot\":1,\"note\":\"先看摘要\"}]"
    try check(try AssistMode.suggestions(response,start:start).count == 1,"AI schedule draft parsed")
    do {_ = try AssistMode.suggestions(response,start:Dates.date("2026-11-01"));throw AppError.message("outside dates accepted")}
    catch {try check(error.localizedDescription != "outside dates accepted","AI out-of-range date rejected")}
    do {_ = try AssistMode.suggestions("[{\"title\":\"x\",\"day\":\"2026-10-29\",\"slot\":8}]",start:start);throw AppError.message("invalid slot accepted")}
    catch {try check(error.localizedDescription != "invalid slot accepted","AI invalid period rejected")}
    let coursesJSON = "[{\"title\":\"算法\",\"weekdays\":[2,5],\"slot\":0,\"start\":\"2026-09-07\",\"end\":\"2026-12-27\",\"cadence\":1}]"
    try check(try CourseImporter.parseAI(coursesJSON,anchor:start).first?.rule.cadence == 1,"AI course draft schema")
    let xml = "<sst><si><t>课程</t></si><si><r><t>知识</t></r><r><t>表示</t></r></si></sst>"
    let delegate = WorkbookXML();delegate.mode = "strings";let parser = XMLParser(data:Data(xml.utf8));parser.delegate = delegate
    try check(parser.parse() && delegate.shared == ["课程","知识表示"],"XLSX rich shared strings")
    var gesture = HorizontalDayNavigation()
    try check(gesture.consume(dx:5,dy:30,momentum:false) == nil,"vertical scroll does not change dates")
    try check(gesture.consume(dx:35,dy:1,momentum:false) == nil && gesture.consume(dx:30,dy:1,momentum:false) == -1,"two-finger horizontal motion advances by accumulated threshold")
    gesture.reset()
    try check(gesture.consume(dx:-70,dy:1,momentum:false) == 1 && gesture.consume(dx:-100,dy:1,momentum:true) == nil,"horizontal direction and momentum suppression")
    print("All \(count) v002 checks passed.")
}
