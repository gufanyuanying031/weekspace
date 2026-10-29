import Foundation

// Only workbook XML is read. No macros, formulas, links, or embedded code are executed.
enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
struct ImportCandidate: Identifiable {
    var id = UUID()
    var rule: CourseRule
    var warning = ""
}
struct SheetTable {
    var name: String
    var rows: [[String]]
    var text: String { (["工作表：" + name] + rows.map { row in row.map { cell in
        cell.contains("\n") || cell.contains("\t") || cell.contains("\"") ? "\"" + cell.replacingOccurrences(of:"\"",with:"\"\"") + "\"" : cell
    }.joined(separator:"\t") }).joined(separator:"\n") }
}
final class WorkbookXML: NSObject, XMLParserDelegate {
    var shared: [String] = []
    var cells: [String:String] = [:]
    var merges: [String] = []
    var mode = "", element = "", cell = "", cellType = "", value = "", item = ""
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String:String]) {
        element = name
        if name == "si" { item = "" }
        if name == "c" { cell = attributes["r"] ?? ""; cellType = attributes["t"] ?? ""; value = "" }
        if name == "mergeCell", let ref = attributes["ref"] { merges.append(ref) }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if mode == "strings" && element == "t" { item += string }
        if mode == "sheet" && (element == "v" || (element == "t" && cellType == "inlineStr")) { value += string }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "si" { shared.append(item) }
        if name == "c" {
            cells[cell] = cellType == "s" ? (Int(value).flatMap { shared.indices.contains($0) ? shared[$0] : nil } ?? "") : value
        }
        element = ""
    }
}
enum CourseImporter {
    static func unzip(_ url: URL, member: String) throws -> Data {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = member.isEmpty ? ["-Z1", url.path] : ["-p", url.path, member]
        let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0, data.count <= 16_000_000 else { throw AppError.message("无法解压这个工作簿，或工作表过大。请另存为精简的 .xlsx 文件。") }
        return data
    }
    static func coordinates(_ ref: String) -> (Int,Int)? {
        let letters = ref.prefix { $0.isLetter }; let digits = ref.dropFirst(letters.count)
        guard let row = Int(digits), row > 0 else { return nil }
        let col = letters.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 }
        return col > 0 ? (row - 1, col - 1) : nil
    }
    static func read(_ url: URL) throws -> [SheetTable] {
        guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) <= 12_000_000 else { throw AppError.message("文件超过 12 MB，请先导出仅含课表的工作簿。") }
        if ["csv","tsv","txt"].contains(url.pathExtension.lowercased()) {
            let data = try Data(contentsOf: url)
            guard let text = String(data:data,encoding:.utf8) ?? String(data:data,encoding:.utf16) else { throw AppError.message("请将文本表格另存为 UTF-8 CSV。") }
            return [SheetTable(name:url.lastPathComponent,rows:delimited(text.replacingOccurrences(of:"\u{FEFF}",with:""), separator:url.pathExtension.lowercased() == "tsv" || text.contains("\t") ? "\t" : ","))]
        }
        guard url.pathExtension.lowercased() == "xlsx" else { throw AppError.message("支持 .xlsx、.csv、.tsv。旧版 .xls 请先另存为 .xlsx。") }
        let listing = String(data:try unzip(url,member:""),encoding:.utf8) ?? ""
        if listing.components(separatedBy:.newlines).contains("xl/workbook.xml") {
            let workbook = String(data:try unzip(url,member:"xl/workbook.xml"),encoding:.utf8) ?? ""
            if workbook.contains("date1904=\"1\"") || workbook.contains("date1904=\"true\"") {throw AppError.message("此工作簿使用 1904 日期系统，请另存为 CSV 后导入，以免日期偏移。")}
        }
        let members = listing.components(separatedBy:.newlines)
        let sheets = members.filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }.sorted()
        guard !sheets.isEmpty, sheets.count <= 20 else { throw AppError.message("没有可读取的工作表，或工作表超过 20 张。") }
        var strings: [String] = []
        if members.contains("xl/sharedStrings.xml") {
            let delegate = WorkbookXML(); delegate.mode = "strings"
            let parser = XMLParser(data:try unzip(url,member:"xl/sharedStrings.xml")); parser.shouldResolveExternalEntities = false; parser.delegate = delegate
            guard parser.parse() else { throw AppError.message("共享字符串解析失败。") }; strings = delegate.shared
        }
        return try sheets.map { name in
            let delegate = WorkbookXML(); delegate.mode = "sheet"; delegate.shared = strings
            let parser = XMLParser(data:try unzip(url,member:name)); parser.shouldResolveExternalEntities = false; parser.delegate = delegate
            guard parser.parse() else { throw AppError.message("工作表 XML 解析失败。") }
            let refs = delegate.cells.keys.compactMap(coordinates)
            let height = (refs.map(\.0).max() ?? 0) + 1, width = (refs.map(\.1).max() ?? 0) + 1
            guard height <= 1000, width <= 80 else { throw AppError.message("课表区域超过 1000 行或 80 列，请先移除无关区域。") }
            var rows = Array(repeating:Array(repeating:"",count:width),count:height)
            for (key,value) in delegate.cells { if let (r,c) = coordinates(key), r < height, c < width { rows[r][c] = value } }
            // Spread merged weekday/period headings, but keep course cells anchored to avoid duplicates.
            for ref in delegate.merges {
                let parts = ref.split(separator:":").map(String.init)
                if parts.count == 2, let (r,c) = coordinates(parts[0]), let (r2,c2) = coordinates(parts[1]), r < height,c < width {
                    let value = rows[r][c]
                    if weekday(value) != nil || ["上午","下午","晚上"].contains(value) {
                        for rr in r...min(r2,height-1) { for cc in c...min(c2,width-1) { rows[rr][cc] = value } }
                    }
                }
            }
            return SheetTable(name:name, rows:rows)
        }
    }
    static func delimited(_ text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], cell = "", quoted = false
        let chars = Array(text.replacingOccurrences(of:"\r\n",with:"\n")); var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "\"" {
                if quoted && i+1 < chars.count && chars[i+1] == "\"" { cell.append("\""); i += 1 } else { quoted.toggle() }
            } else if ch == separator && !quoted { row.append(cell); cell = "" }
            else if ch == "\n" && !quoted { row.append(cell); rows.append(row); row = []; cell = "" }
            else { cell.append(ch) }
            i += 1
        }
        if !cell.isEmpty || !row.isEmpty { row.append(cell); rows.append(row) }
        return rows
    }
    static func weekday(_ value: String) -> Int? {
        let v = value.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        let names = [2:["周一","星期一","monday","mon","1"],3:["周二","星期二","tuesday","tue","2"],4:["周三","星期三","wednesday","wed","3"],5:["周四","星期四","thursday","thu","4"],6:["周五","星期五","friday","fri","5"],7:["周六","星期六","saturday","sat","6"],1:["周日","周天","星期日","星期天","sunday","sun","7"]]
        return names.first { $0.value.contains(v) }?.key
    }
    static func normalTime(_ value:String)->String {
        if let n = Double(value),n >= 0,n < 1 {return ClockTime.label(Int((n*1440).rounded()) % 1440)}
        if let minutes = ClockTime.parse(value) {return ClockTime.label(minutes)};return value
    }
    static func normalDate(_ value:String)->String {
        if let serial = Int(value),serial > 20000,serial < 100000 {return Dates.key(Dates.add(serial,to:Dates.date("1899-12-30")))}
        let parts = value.replacingOccurrences(of:"/",with:"-").split(separator:"-")
        if parts.count == 3,let y = Int(parts[0]),let m = Int(parts[1]),let d = Int(parts[2]) {return String(format:"%04d-%02d-%02d",y,m,d)};return value
    }
    static func slot(_ value: String) -> Slot? {
        if value.contains("上午") || value.lowercased() == "morning" { return .morning }
        if value.contains("下午") || value.lowercased() == "afternoon" { return .afternoon }
        if value.contains("晚") || value.lowercased() == "evening" { return .evening }
        if let time = ClockTime.parse(value.components(separatedBy:CharacterSet(charactersIn:"–—-~至")).first ?? "") { return time < 12*60 ? .morning : time < 18*60 ? .afternoon : .evening }
        return nil
    }
    static func timeRange(_ text:String)->String {
        let regex = try! NSRegularExpression(pattern:"[0-2]?[0-9]:[0-5][0-9]")
        let ns = text as NSString
        let matches = regex.matches(in:text,range:NSRange(location:0,length:ns.length))
        guard matches.count >= 2,let a = ClockTime.parse(ns.substring(with:matches[0].range)),let b = ClockTime.parse(ns.substring(with:matches[1].range)),b > a else{return ""}
        return ClockTime.label(a)+"–"+ClockTime.label(b)
    }
    static func normalizedTitle(_ value:String)->String {
        let first = value.components(separatedBy:"·").first ?? value
        return first.replacingOccurrences(of:"（秋冬）",with:"").replacingOccurrences(of:"（秋）",with:"").replacingOccurrences(of:"（冬）",with:"").trimmingCharacters(in:.whitespacesAndNewlines)
    }
    static func teachingWeeks(_ text:String)->[Int]? {
        if text.contains("每周") || text.trimmingCharacters(in:.whitespaces).isEmpty {return nil}
        let regex = try! NSRegularExpression(pattern:"([0-9]{1,2})(?:[ ]*[-–~至][ ]*([0-9]{1,2}))?")
        let ns = text as NSString;var weeks = Set<Int>()
        for match in regex.matches(in:text,range:NSRange(location:0,length:ns.length)) {
            guard let start = Int(ns.substring(with:match.range(at:1))),(1...60).contains(start) else{continue}
            let end = match.range(at:2).location == NSNotFound ? start:(Int(ns.substring(with:match.range(at:2))) ?? start)
            guard end >= start,end <= 60 else{continue};for week in start...end {weeks.insert(week)}
        }
        return weeks.isEmpty ? nil:weeks.sorted()
    }
    static func weekdayName(_ value:Int)->String {["","周日","周一","周二","周三","周四","周五","周六"][value]}
    static func parse(tables:[SheetTable],anchor:Date)->[ImportCandidate] {
        var results:[ImportCandidate] = []
        let weekOne = Dates.week(anchor)
        for table in tables {
            let rows = table.rows
            let listHeader = rows.firstIndex {row in row.contains(where:{["课程","课程名称","课程名","title","course"].contains($0.trimmingCharacters(in:.whitespaces).lowercased())}) && row.contains(where:{["星期","星期几","weekday","周几"].contains($0.trimmingCharacters(in:.whitespaces).lowercased())})}
            if let h = listHeader {
                let header = rows[h].map{$0.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()}
                for row in rows.dropFirst(h+1) {
                    func field(_ names:[String])->String {guard let i = header.firstIndex(where:{names.contains($0)}),i < row.count else{return ""};return row[i].trimmingCharacters(in:.whitespacesAndNewlines)}
                    let title = field(["课程","课程名称","课程名","title","course"])
                    let days = field(["星期","星期几","weekday","周几"]).components(separatedBy:CharacterSet(charactersIn:",，、;/ ")).compactMap(weekday)
                    guard !title.isEmpty,!days.isEmpty else{continue}
                    let begin = normalTime(field(["开始时间","开始","starttime","start_time"])),end = normalTime(field(["结束时间","结束","endtime","end_time"]))
                    let rawSlot = field(["时段","slot"])
                    let range = !begin.isEmpty && !end.isEmpty ? begin+"–"+end:timeRange(field(["时间","time"]))
                    var rule = CourseRule(title:title,weekdays:Array(Set(days)).sorted(),slot:slot(rawSlot) ?? slot(range) ?? .morning,time:range,location:field(["地点","教室","location"]),start:Dates.key(weekOne),end:Dates.key(Dates.add(111,to:weekOne)),anchor:Dates.key(weekOne))
                    let repeatValue = field(["单双周","重复","cadence"]);rule.cadence = repeatValue.contains("双") ? 2:repeatValue.contains("单") ? 1:0
                    let start = field(["开始日期","生效日期"]),stop = field(["结束日期"])
                    if !start.isEmpty {rule.start = normalDate(start)};if !stop.isEmpty {rule.end = normalDate(stop)}
                    rule.weeks = teachingWeeks(field(["周次","教学周"]))
                    results.append(ImportCandidate(rule:rule,warning:slot(rawSlot) == nil && slot(range) == nil ? "缺少时段，暂放上午，请核对。":""))
                }
                continue
            }
            guard let h = rows.firstIndex(where:{$0.filter{weekday($0) != nil && ($0.contains("周") || $0.contains("星期") || $0.count > 2)}.count >= 3}) else{continue}
            let dayColumns = rows[h].enumerated().compactMap{i,v in weekday(v).map{(i,$0)}}
            let firstDay = dayColumns.map(\.0).min() ?? 1
            var groups:[ImportCandidate] = [],lastRows:[Int:Int] = [:],lastIndexes:[Int:Int] = [:]
            var started = false
            for r in (h+1)..<rows.count {
                let row = rows[r]
                if row.allSatisfy({$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}) {if started {break}else{continue}}
                let labels = row.prefix(firstDay).joined(separator:" ")
                // A new table or prose section terminates the weekly grid, rather than becoming courses.
                if labels.contains("课程明细") || labels.contains("说明") || row.contains("课程名称") {break}
                let times = timeRange(labels)
                guard let period = slot(labels) else{if started {break}else{continue}}
                started = true
                for (col,day) in dayColumns where col < row.count {
                    let content = row[col].trimmingCharacters(in:.whitespacesAndNewlines)
                    if content.isEmpty {lastRows.removeValue(forKey:col);lastIndexes.removeValue(forKey:col);continue}
                    let parts = content.components(separatedBy:.newlines).filter{!$0.isEmpty}
                    let dotParts = (parts.first ?? content).components(separatedBy:"·")
                    let title = normalizedTitle(dotParts.first ?? content)
                    let note = (Array(dotParts.dropFirst())+Array(parts.dropFirst())).joined(separator:" · ")
                    if let oldIndex = lastIndexes[col],lastRows[col] == r-1,groups[oldIndex].rule.title == title,groups[oldIndex].rule.slot == period,groups[oldIndex].rule.location == note {
                        if !times.isEmpty {
                            let oldTime = groups[oldIndex].rule.time
                            let start = oldTime.components(separatedBy:"–").first ?? ""
                            let end = times.components(separatedBy:"–").last ?? ""
                            groups[oldIndex].rule.time = start.isEmpty ? times:start+"–"+end
                        }
                        lastRows[col] = r
                    } else {
                        let rule = CourseRule(title:title,weekdays:[day],slot:period,time:times,location:note,start:Dates.key(weekOne),end:Dates.key(Dates.add(111,to:weekOne)),anchor:Dates.key(weekOne))
                        groups.append(ImportCandidate(rule:rule,warning:times.isEmpty ? "原表缺少具体上课时间，请核对。":"已合并连续节次，请核对学期起点与周次。"))
                        lastIndexes[col] = groups.count-1;lastRows[col] = r
                    }
                }
            }
            // Enrich the grid only from a positively identified detail table.
            if let detailHeader = rows.firstIndex(where:{$0.contains("课程名称") && $0.contains("上课时间") && $0.contains("周次")}) {
                let header = rows[detailHeader]
                for row in rows.dropFirst(detailHeader+1) {
                    func field(_ name:String)->String {guard let i = header.firstIndex(of:name),i < row.count else{return ""};return row[i].trimmingCharacters(in:.whitespacesAndNewlines)}
                    let title = field("课程名称");if title.isEmpty {continue}
                    let indexes = groups.indices.filter{normalizedTitle(groups[$0].rule.title) == normalizedTitle(title)}
                    if indexes.isEmpty {continue}
                    let rawWeeks = field("周次"),rawSchedule = field("上课时间"),location = field("上课地点"),teacher = field("任课老师")
                    for i in indexes {
                        groups[i].rule.title = title
                        if !location.isEmpty {groups[i].rule.location = location+(teacher.isEmpty ? "":" · "+teacher)}
                        let explicitTime = timeRange(rawSchedule)
                        if !explicitTime.isEmpty {groups[i].rule.time = explicitTime}
                        let pieces = rawWeeks.components(separatedBy:CharacterSet(charactersIn:";；"))
                        let dayName = weekdayName(groups[i].rule.weekdays[0])
                        let byDay = pieces.first{$0.contains(dayName)}
                        let weekText:String
                        if let byDay {weekText = byDay.replacingOccurrences(of:dayName,with:"")}
                        else {weekText = pieces.first ?? rawWeeks}
                        groups[i].rule.weeks = teachingWeeks(weekText)
                        if let weeks = groups[i].rule.weeks,let maxWeek = weeks.max() {groups[i].rule.end = Dates.key(Dates.add(maxWeek*7-1,to:weekOne))}
                        groups[i].warning = "已匹配课程明细；请核对教学第1周，限定周次不会按每周重复。"
                    }
                    let exception = try! NSRegularExpression(pattern:"第[ ]*([0-9]{1,2})[ ]*周[^；;]*?(周[一二三四五六日天])")
                    let ns = rawWeeks as NSString
                    for match in exception.matches(in:rawWeeks,range:NSRange(location:0,length:ns.length)) {
                        guard let week = Int(ns.substring(with:match.range(at:1))),(1...60).contains(week),let day = weekday(ns.substring(with:match.range(at:2))),let base = indexes.first else{continue}
                        var extra = groups[base].rule;extra.id = UUID();extra.weekdays = [day];extra.weeks = [week]
                        extra.end = Dates.key(Dates.add(week*7-1,to:weekOne))
                        groups.append(ImportCandidate(rule:extra,warning:"特殊安排：第\(week)周\(weekdayName(day))。请与学院通知核对。"))
                    }
                }
            }
            results += groups
        }
        var seen = Set<String>()
        return results.filter{seen.insert($0.rule.title+$0.rule.weekdays.description+$0.rule.slot.rawValue.description+$0.rule.time+$0.rule.location+($0.rule.weeks?.description ?? "")).inserted}
    }
    static func jsonArray(_ text: String) throws -> [[String:Any]] {
        guard let first = text.firstIndex(of:"["), let last = text.lastIndex(of:"]"), first <= last,
              let data = String(text[first...last]).data(using:.utf8), let array = try JSONSerialization.jsonObject(with:data) as? [[String:Any]] else { throw AppError.message("模型输出不是可用的 JSON 数组，请调整输入后重试。") }
        guard array.count <= 200 else { throw AppError.message("结果超过 200 项，请分批处理。") }; return array
    }
    static func validDate(_ key: String) -> Bool { Dates.key(Dates.date(key)) == key && key.count == 10 }
    static func parseAI(_ text: String, anchor: Date) throws -> [ImportCandidate] {
        try jsonArray(text).map { row in
            guard let title = row["title"] as? String, !title.isEmpty, title.count <= 200,
                  let days = row["weekdays"] as? [Int], !days.isEmpty, days.allSatisfy({(1...7).contains($0)}),
                  let slotValue = row["slot"] as? Int, let period = Slot(rawValue:slotValue) else { throw AppError.message("部分课程缺少有效名称、星期或时段。请核对模型识别结果。") }
            let start = row["start"] as? String ?? Dates.key(anchor), end = row["end"] as? String ?? Dates.key(Dates.add(111,to:Dates.week(anchor)))
            guard validDate(start),validDate(end),start <= end else { throw AppError.message("课程的生效或结束日期无效。") }
            let cadence = row["cadence"] as? Int ?? 0
            guard (0...2).contains(cadence) else { throw AppError.message("单双周字段无效。") }
            var rule = CourseRule(title:title,weekdays:Array(Set(days)).sorted(),slot:period,time:row["time"] as? String ?? "",location:row["location"] as? String ?? "",start:start,end:end,cadence:cadence,anchor:Dates.key(Dates.week(anchor)))
            if let weeks = row["weeks"] as? [Int] {
                guard !weeks.isEmpty,weeks.allSatisfy({(1...60).contains($0)}) else{throw AppError.message("教学周次无效。")};rule.weeks = Array(Set(weeks)).sorted()
            }
            return ImportCandidate(rule:rule,warning:"AI 识别草稿，请核对星期、周次和上课时间。")
        }
    }
}
enum ClockTime {
    static func validRange(_ time:String)->Bool {
        if time.isEmpty {return true};let pieces = time.components(separatedBy:CharacterSet(charactersIn:"–—-~至"))
        guard pieces.count == 2,let a = parse(pieces[0]),let b = parse(pieces[1]) else{return false};return b > a
    }
    static func parse(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in:.whitespacesAndNewlines).split(separator:":")
        guard parts.count == 2,let h = Int(parts[0]),let m = Int(parts[1]),(0...23).contains(h),(0...59).contains(m) else { return nil }; return h*60+m
    }
    static func label(_ minutes: Int) -> String { String(format:"%02d:%02d",minutes/60,minutes%60) }
    static func bounds(_ time: String, slot: Slot = .morning) -> (Int,Int) {
        let parts = time.components(separatedBy:CharacterSet(charactersIn:"–—-~至"))
        if parts.count == 2,let a = parse(parts[0]),let b = parse(parts[1]) { return (a,b) }
        let start = [9*60,14*60,19*60][slot.rawValue]; return (start,start+60)
    }
}
