import SwiftUI
import AppKit
import UniformTypeIdentifiers

typealias ViewState<Value> = SwiftUI.State<Value>

let ink = Color(red: 0.10, green: 0.11, blue: 0.10)
let muted = Color(red: 0.47, green: 0.48, blue: 0.46)
let line = Color.black.opacity(0.075)
let paper = Color(red: 0.975, green: 0.975, blue: 0.963)
let green = Color(red: 0.24, green: 0.43, blue: 0.34)

struct QuietButton: ButtonStyle {
    var filled = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13).padding(.vertical, 9)
            .foregroundStyle(filled ? Color.white : ink)
            .background(filled ? ink.opacity(configuration.isPressed ? 0.8 : 1) : Color.black.opacity(configuration.isPressed ? 0.08 : 0.035))
            .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

struct TaskDraft: Identifiable { var id: UUID { task.id }; var task: PlanTask }
enum PanelSheet: String, Identifiable { case courses, settings, history, assistant, importer; var id: String { rawValue } }

struct MainView: View {
    @ObservedObject var store: PlanStore
    @ViewState<TaskDraft?> private var taskDraft: TaskDraft? = nil
    @ViewState<PanelSheet?> private var sheet: PanelSheet? = nil
    @ViewState<Bool> private var showSummary: Bool = true
    @ViewState<Bool> private var pinned: Bool = false
    @ViewState<Bool> private var locked: Bool = false
    @ViewState<Bool> private var compact: Bool = false
    @ViewState<Bool> private var choosingStart: Bool = false
    private var rangeTasks: [PlanTask] { store.db.tasks(in: store.selectedWeek) }
    var body: some View {
        VStack(spacing:0) {
            topBar
            HStack(alignment:.top,spacing:0) {
                VStack(alignment:.leading,spacing:0) {
                    heading.padding(.horizontal,26).padding(.top,22).padding(.bottom,18)
                    if compact { todayBoard } else { weekBoard }
                }
                if showSummary && !compact { summaryPanel.frame(width:290) }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
            footer
        }.background(Color.white).foregroundStyle(ink)
            .frame(minWidth:compact ? 520 : 1100,minHeight:650).preferredColorScheme(.light)
            .background(SevenDayScrollCapture {steps in if !compact {store.navigate(steps)} })
            .sheet(item:$taskDraft) { TaskEditor(store:store,original:$0.task) }
            .sheet(item:$sheet) { active in
                switch active {
                case .courses: CoursesView(store:store)
                case .settings: SettingsView(store:store)
                case .history: HistoryView(store:store)
                case .assistant: AssistantView(store:store)
                case .importer: CourseImportView(store:store)
                }
            }
            .alert("需要留意",isPresented:Binding(get:{store.error != nil},set:{if !$0 {store.error = nil}})) { Button("知道了") {store.error = nil} } message: {Text(store.error ?? "")}
            .onReceive(NotificationCenter.default.publisher(for:.newPlanTask)) { _ in taskDraft = TaskDraft(task:PlanTask(day:Dates.key(Date()),slot:.morning,title:"")) }
            .onReceive(NotificationCenter.default.publisher(for:.openPlanSettings)) { _ in sheet = .settings }
            .task { await store.refreshQuote() }
    }
    var topBar: some View {
        HStack(spacing:10) {
            Image(systemName:"square.grid.2x2").font(.system(size:17,weight:.medium))
            Text("周间").font(.system(size:16,weight:.semibold))
            Text("W E E K S P A C E").font(.system(size:9,weight:.medium)).foregroundStyle(muted).padding(.leading,5)
            if store.demo { Text("演示").font(.system(size:10)).foregroundStyle(green) }
            Spacer()
            Button { AppDelegate.shared?.toggleDesktop() } label: { Image(systemName:"macwindow") }.help("显示或隐藏桌面小面板").accessibilityLabel("桌面小面板")
            Button {compact.toggle();AppDelegate.shared?.setCompact(compact)} label:{Image(systemName:compact ? "rectangle.expand.vertical":"rectangle.compress.vertical")}.help(compact ? "展开七日视图":"仅看今天")
            Button {locked.toggle();AppDelegate.shared?.window.isMovable = !locked} label:{Image(systemName:locked ? "lock.fill":"lock.open")}.help("锁定或解锁位置")
            Button {pinned.toggle();AppDelegate.shared?.setPinned(pinned)} label:{Image(systemName:pinned ? "pin.fill":"pin")}.help("窗口置顶")
            Button {showSummary.toggle()} label:{Image(systemName:"sidebar.right")}.help("随心安排与复盘")
            Rectangle().fill(line).frame(width:1,height:16).padding(.horizontal,5)
            Button {sheet = .settings} label:{Image(systemName:"slider.horizontal.3")}.help("设置")
        }.buttonStyle(.plain).font(.system(size:14)).padding(.horizontal,26).frame(height:54).overlay(alignment:.bottom){line.frame(height:1)}
    }
    var heading: some View {
        VStack(alignment:.leading,spacing:16) {
            QuoteView(store:store,compact:compact)
            HStack(spacing:12) {
                if compact { Text(Dates.label(Date(),"M月d日 EEEE")).font(.system(size:12)).foregroundStyle(muted) }
                else {
                    Button {store.navigate(-1)} label:{Image(systemName:"chevron.left")}.help("向前一天")
                    Button {choosingStart = true} label:{Text(Dates.label(store.selectedWeek,"M月d日")).foregroundStyle(muted)}
                        .buttonStyle(.plain).help("点击更改七日视图起始日").accessibilityLabel("更改起始日："+Dates.label(store.selectedWeek,"yyyy年M月d日"))
                        .popover(isPresented:$choosingStart,arrowEdge:.bottom) {
                            VStack(alignment:.leading,spacing:12) {
                                Text("从哪天开始？").font(.system(size:15,weight:.medium))
                                DatePicker("起始日",selection:Binding(get:{store.selectedWeek},set:{store.selectStart($0);choosingStart = false}),displayedComponents:.date).datePickerStyle(.graphical).labelsHidden()
                                Text("选定后展示连续七天").font(.system(size:11)).foregroundStyle(muted)
                            }.padding(20).frame(width:300)
                        }
                    Text("— " + Dates.label(Dates.add(6,to:store.selectedWeek),"M月d日")).foregroundStyle(muted)
                    Button {store.navigate(1)} label:{Image(systemName:"chevron.right")}.help("向后一天")
                    Button("今天起") {store.today()}.foregroundStyle(muted)
                    Button("本周") {store.selectStart(Dates.week(Date()))}.foregroundStyle(ink)
                }
                Spacer(minLength:8)
                Menu {
                    Button("编辑固定课表") {sheet = .courses}
                    Button("导入 Excel / CSV 课表") {sheet = .importer}
                } label:{Label("固定课表",systemImage:"repeat")}.menuStyle(.borderlessButton).fixedSize()
            }.buttonStyle(.plain).font(.system(size:12))
        }
    }
    var weekBoard: some View {
        VStack(spacing:0) {
            HStack(spacing:0) {
                Text("时段").font(.system(size:10)).foregroundStyle(muted).frame(width:43)
                ForEach(Dates.days(store.selectedWeek),id:\.self) { day in
                    VStack(spacing:6) {
                        Text(Dates.label(day,"EEE")).font(.system(size:11)).foregroundStyle(muted)
                        Text(Dates.label(day,"dd")).font(.system(size:21,weight:.medium,design:.rounded)).foregroundStyle(isToday(day) ? Color.white:ink)
                            .frame(width:34,height:34).background(isToday(day) ? ink:Color.clear).clipShape(Circle())
                    }.frame(maxWidth:.infinity).frame(height:76).background(isToday(day) ? paper:Color.clear)
                }
            }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:24).onEnded { value in
                if abs(value.translation.width) > abs(value.translation.height) {
                    let days = max(1,min(7,Int(abs(value.translation.width)/100)))
                    store.navigate(value.translation.width < 0 ? days : -days)
                }
            }).help("左右拖动日期栏，以一天为单位移动七日窗口")
            line.frame(height:1)
            ScrollView {
                VStack(spacing:0) {
                    ForEach(Slot.allCases) { slot in
                        HStack(alignment:.top,spacing:0) {
                            VStack(spacing:9) {Image(systemName:slot.icon).font(.system(size:14));Text(slot.title).font(.system(size:11))}.foregroundStyle(muted).frame(width:43).padding(.top,19)
                            ForEach(Dates.days(store.selectedWeek),id:\.self) { day in
                                TaskCell(store:store,day:day,slot:slot,onEdit:{taskDraft = TaskDraft(task:$0)})
                                    .frame(maxWidth:.infinity,alignment:.topLeading).frame(minHeight:146,alignment:.topLeading)
                                    .background(isToday(day) ? paper.opacity(0.7):Color.clear).overlay(alignment:.leading){line.frame(width:1)}
                            }
                        }.fixedSize(horizontal:false,vertical:true)
                        line.frame(height:1)
                    }
                }
            }.scrollIndicators(.hidden)
            HStack {Text("双指横向滑动 · 任意连续七天");Spacer();Text("点击添加，直接输入 · 回车保存")}.font(.system(size:9)).foregroundStyle(muted.opacity(0.7)).padding(.top,12)
        }.padding(.horizontal,18).padding(.bottom,14)
    }
    var todayBoard: some View {
        ScrollView {
            VStack(spacing:0) {
                ForEach(Slot.allCases) {slot in
                    HStack(alignment:.top) {
                        Label(slot.title,systemImage:slot.icon).font(.system(size:12)).foregroundStyle(muted).frame(width:65).padding(.top,18)
                        TaskCell(store:store,day:Date(),slot:slot,onEdit:{taskDraft = TaskDraft(task:$0)})
                    }.frame(minHeight:145,alignment:.top)
                    line.frame(height:1)
                }
            }.padding(.horizontal,24)
        }
    }
    var summaryPanel: some View {
        VStack(alignment:.leading,spacing:0) {
            PoolView(store:store).frame(maxHeight:.infinity)
            Button {sheet = .assistant} label:{HStack{Image(systemName:"sparkles");Text("AI 工作台");Spacer();Image(systemName:"arrow.up.right")}}.buttonStyle(QuietButton(filled:true)).padding(.top,18)
            Text("七日总结与记录，收在这里。").font(.system(size:9)).foregroundStyle(muted).frame(maxWidth:.infinity).padding(.top,9)
        }.padding(22).frame(maxHeight:.infinity).background(paper).overlay(alignment:.leading){line.frame(width:1)}
    }
    var footer: some View {
        HStack(spacing:7) {
            Circle().fill(store.canWrite ? green:Color.red).frame(width:5,height:5);Text(store.message)
            if store.lastDeleted != nil {Button("撤销删除"){store.undoDelete()}.foregroundStyle(ink)}
            Spacer();Text("每日自动归档").foregroundStyle(muted.opacity(0.7));Text("·").padding(.horizontal,4)
            Button {sheet = .history} label:{Label("历史",systemImage:"clock.arrow.circlepath")}
            Menu {Button("导出这七天 Markdown"){store.exportMarkdown()};Button("导出全部数据 JSON"){store.exportJSON()}} label:{Label("导出",systemImage:"arrow.up.doc")}.menuStyle(.borderlessButton).fixedSize().padding(.leading,10)
        }.font(.system(size:10)).foregroundStyle(muted).buttonStyle(.plain).padding(.horizontal,26).frame(height:40).overlay(alignment:.top){line.frame(height:1)}
    }
    func isToday(_ day:Date)->Bool {Dates.calendar.isDateInToday(day)}
}

struct TaskCell: View {
    @ObservedObject var store:PlanStore
    var day:Date;var slot:Slot;var onEdit:(PlanTask)->Void
    @ViewState<Bool> private var adding = false
    @ViewState<String> private var input = ""
    @ViewState<Bool> private var dropTarget = false
    @FocusState private var focused:Bool
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            ForEach(store.items(day:day,slot:slot)) { task in InlineTaskRow(store:store,task:task,onDetails:{onEdit(task)}) }
            if adding {
                VStack(alignment:.leading,spacing:6) {
                    TextField("写下任务…",text:$input,axis:.vertical).font(.system(size:12)).textFieldStyle(.plain).focused($focused)
                        .onSubmit {commit(keepOpen:true)}.onExitCommand {input = "";adding = false}
                        .accessibilityLabel("\(Dates.key(day))\(slot.title)新任务")
                    HStack {
                        Button {commit(keepOpen:false)} label:{Image(systemName:"return")}.help("保存任务")
                        Spacer()
                        Button { let title = input;input = "";adding = false;onEdit(PlanTask(day:Dates.key(day),slot:slot,title:title)) } label:{Image(systemName:"clock")}.help("填写具体时间与备注")
                    }.font(.system(size:10)).foregroundStyle(muted).buttonStyle(.plain)
                }.padding(9).background(Color.white).overlay(RoundedRectangle(cornerRadius:7).stroke(ink.opacity(0.18))).clipShape(RoundedRectangle(cornerRadius:7))
            } else {
                Button {adding = true;focused = true} label:{HStack(spacing:4){Image(systemName:"plus");Text("添加")}.font(.system(size:10)).foregroundStyle(muted.opacity(0.65)).frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,7).padding(.horizontal,9).contentShape(Rectangle())}.buttonStyle(.plain).help("直接填写\(slot.title)任务")
            }
            Spacer(minLength:0)
        }.padding(7).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .background(dropTarget ? green.opacity(0.09):Color.clear)
            .onChange(of:focused) {_,value in if !value && adding {commit(keepOpen:false)} }
            .onDisappear { if !input.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {commit(keepOpen:false)} }
            .onDrop(of:[UTType.text],isTargeted:$dropTarget) {providers in
                guard let provider = providers.first else {return false}
                _ = provider.loadObject(ofClass:NSString.self) {object,_ in
                    guard let value = object as? String else {return}
                    Task {@MainActor in
                        if value.hasPrefix("pool:"),let id = UUID(uuidString:String(value.dropFirst(5))) {store.placePool(id,day:day,slot:slot)}
                        else if value.hasPrefix("task:"),let id = UUID(uuidString:String(value.dropFirst(5))),let t = store.db.tasks.first(where:{$0.id == id}) {
                            if t.day == Dates.key(day) && t.slot == slot {return}
                            var moved = t
                            if t.courseID != nil {store.delete(t);moved.id = UUID();moved.courseID = nil}
                            moved.day = Dates.key(day);moved.slot = slot;store.put(moved)
                        }
                    }
                };return true
            }
    }
    func commit(keepOpen:Bool) {
        let title = input.trimmingCharacters(in:.whitespacesAndNewlines)
        input = "";adding = keepOpen
        if !title.isEmpty {store.put(PlanTask(day:Dates.key(day),slot:slot,title:title))}
        if keepOpen {focused = true}
    }
}
struct InlineTaskRow:View {
    @ObservedObject var store:PlanStore;var task:PlanTask;var onDetails:()->Void
    @ViewState<Bool> private var editing = false
    @ViewState<String> private var title = ""
    @FocusState private var focused:Bool
    var body:some View {
        HStack(alignment:.top,spacing:6) {
            Button {store.toggle(task)} label:{Image(systemName:task.completed ? "checkmark.circle.fill":"circle").font(.system(size:13)).foregroundStyle(task.completed ? green:Color.black.opacity(0.25))}.buttonStyle(.plain).padding(.top,2).help("切换完成状态")
            VStack(alignment:.leading,spacing:5) {
                if !task.time.isEmpty {Text(task.time).font(.system(size:9,design:.monospaced)).foregroundStyle(muted)}
                if editing {
                    TextField("任务",text:$title,axis:.vertical).font(.system(size:12)).textFieldStyle(.plain).focused($focused).onSubmit{commit()}.onExitCommand{editing = false}
                } else {
                    Button {title = task.title;editing = true;focused = true} label:{Text(task.title).font(.system(size:12,weight:task.courseID == nil ? .regular:.medium)).strikethrough(task.completed).foregroundStyle(task.completed ? muted:ink).frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true).lineLimit(4)}.buttonStyle(.plain)
                }
                if task.courseID != nil {Text("固定课程").font(.system(size:8)).foregroundStyle(muted)}
                if !task.note.isEmpty {Text(task.note).font(.system(size:9)).foregroundStyle(muted).lineLimit(2)}
            }.frame(maxWidth:.infinity,alignment:.leading)
            Button(action:onDetails){Image(systemName:"ellipsis").font(.system(size:10)).foregroundStyle(muted.opacity(0.6))}.buttonStyle(.plain).help("时间、日期与备注")
        }.padding(8).background(task.courseID != nil ? Color.black.opacity(0.035):Color.white.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius:7))
            .onChange(of:focused){_,value in if !value && editing {commit()} }
            .onDrag {NSItemProvider(object:("task:"+task.id.uuidString) as NSString)}
            .contextMenu {
                Button("详细编辑",action:onDetails)
                Button(task.completed ? "设为未完成":"标记完成"){store.toggle(task)}
                Button("加入随心安排"){store.addPool(task.title)}
                if task.day < Dates.key(Date()) {Button("复制到今天"){store.moveToToday(task)}}
                Button("删除",role:.destructive){store.delete(task)}
            }
    }
    func commit(){var t = task;let value = title.trimmingCharacters(in:.whitespacesAndNewlines);if !value.isEmpty {t.title = value;store.put(t)};editing = false}
}

struct SheetHeader: View {
    var title: String; var subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 25, weight: .medium)).tracking(-0.5)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(muted)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 18)
    }
}

struct TaskEditor: View {
    @ObservedObject var store: PlanStore
    var original: PlanTask
    @Environment(\.dismiss) var dismiss
    @ViewState<String> private var title: String = ""
    @ViewState<Date> private var day: Date = Date()
    @ViewState<Slot> private var slot: Slot = Slot.morning
    @ViewState<String> private var time: String = ""
    @ViewState<String> private var note: String = ""
    @ViewState<Bool> private var done: Bool = false
    @FocusState private var focused: Bool
    var exists: Bool { store.db.tasks.contains { $0.id == original.id } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: exists ? "编辑安排" : "留下一件要做的事", subtitle: original.courseID == nil ? "安排可以调整，进展随时记录。" : "这里只修改本次课程；重复规则在固定课表中调整。")
            TextField("任务或课程名称", text: $title).textFieldStyle(.roundedBorder).font(.system(size: 18)).focused($focused)
            HStack {
                DatePicker("日期", selection: $day, displayedComponents: .date).frame(width: 220)
                Spacer()
                Picker("时段", selection: $slot) { ForEach(Slot.allCases) { Text($0.title).tag($0) } }.frame(width: 180)
            }
            TimeRangePicker(time:$time,slot:slot)
            Text("进展 / 备注 / 地点").font(.system(size: 12)).foregroundStyle(muted)
            TextEditor(text: $note).font(.system(size: 13)).frame(height: 115).padding(6).overlay(RoundedRectangle(cornerRadius: 6).stroke(line))
            Toggle(original.courseID == nil ? "已完成" : "已参加", isOn: $done).toggleStyle(.checkbox)
            if original.day < Dates.key(Date()) { Text("历史补记会保存到计划中，当天的原始归档快照仍然保留。").font(.system(size: 10)).foregroundStyle(muted) }
            HStack {
                if exists { Button("删除本次", role: .destructive) { store.delete(original); dismiss() }.buttonStyle(.plain) }
                Spacer(); Button("取消") { dismiss() }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction)
                Button("保存") {
                    var t = original; t.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    t.day = Dates.key(day); t.slot = slot; t.time = time; t.note = note; t.completed = done
                    // Moving a recurring instance leaves a tombstone on its original date.
                    if t.day != original.day && original.courseID != nil {
                        var tombstone = original; tombstone.deleted = true; store.put(tombstone)
                        t.id = UUID(); t.courseID = nil
                    }
                    store.put(t); dismiss()
                }.buttonStyle(QuietButton(filled: true)).keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !ClockTime.validRange(time))
            }.padding(.top, 6)
        }.padding(30).frame(width: 530).background(Color.white)
            .onAppear { title = original.title; day = Dates.date(original.day); slot = original.slot; time = original.time; note = original.note; done = original.completed; focused = true }
    }
}

struct CoursesView: View {
    @ObservedObject var store: PlanStore
    @Environment(\.dismiss) var dismiss
    @ViewState<CourseRule?> private var editing: CourseRule? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeader(title: "固定课表", subtitle: "填一次，按周重复。每次课程保留独立的参加记录。")
            if store.db.courses.isEmpty {
                VStack(spacing: 13) {
                    Image(systemName: "calendar.badge.plus").font(.system(size: 30, weight: .light)).foregroundStyle(muted)
                    Text("把固定的时间，先安排好。").font(.system(size: 16))
                    Text("支持每周、单双周，以及学期起止日期。").font(.system(size: 12)).foregroundStyle(muted)
                }.frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.db.courses) { course in
                            HStack {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(course.title).font(.system(size: 15, weight: .medium))
                                    Text(course.weekdays.sorted().map { ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"][$0] }.joined(separator: "、") + " · " + course.slot.title + " " + course.time).font(.system(size: 11)).foregroundStyle(muted)
                                    Text("\(course.start) 至 \(course.end) · \(["每周", "单周", "双周"][course.cadence])").font(.system(size: 10)).foregroundStyle(muted)
                                }
                                Spacer()
                                Button("编辑") { editing = course }.buttonStyle(QuietButton())
                            }.padding(.vertical, 16)
                            line.frame(height: 1)
                        }
                    }
                }.frame(height: 280)
            }
            HStack {
                Button { editing = CourseRule() } label: { Label("添加固定课程", systemImage: "plus") }.buttonStyle(QuietButton(filled: true))
                Spacer(); Button("完成") { dismiss() }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction)
            }
        }.padding(30).frame(width: 620).background(Color.white)
            .sheet(item: $editing) { course in CourseEditor(store: store, original: course) }
    }
}

struct CourseEditor: View {
    @ObservedObject var store: PlanStore
    var original: CourseRule
    @Environment(\.dismiss) var dismiss
    @ViewState<CourseRule> private var rule: CourseRule = CourseRule()
    @ViewState<Date> private var start: Date = Date()
    @ViewState<Date> private var end: Date = Dates.add(112, to: Date())
    @ViewState<Date> private var anchor: Date = Dates.week(Date())
    @ViewState<Bool> private var confirmDelete: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "安排一门固定课程", subtitle: "模板修改作用于今天及以后的未完成安排，过去的记录不变。")
            TextField("课程名称", text: $rule.title).textFieldStyle(.roundedBorder).font(.system(size: 17))
            HStack(spacing: 8) {
                ForEach([2,3,4,5,6,7,1], id: \.self) { weekday in
                    Button {
                        if rule.weekdays.contains(weekday) { rule.weekdays.removeAll { $0 == weekday } } else { rule.weekdays.append(weekday) }
                    } label: { Text(["", "日", "一", "二", "三", "四", "五", "六"][weekday]).frame(width: 41, height: 36).background(rule.weekdays.contains(weekday) ? ink : paper).foregroundStyle(rule.weekdays.contains(weekday) ? Color.white : ink).clipShape(RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain)
                }
            }
            HStack {
                Picker("时段", selection: $rule.slot) { ForEach(Slot.allCases) { Text($0.title).tag($0) } }
                Picker("重复", selection: $rule.cadence) { Text("每周").tag(0); Text("单周").tag(1); Text("双周").tag(2) }
            }
            TimeRangePicker(time:$rule.time,slot:rule.slot)
            TextField("上课地点或备注（可选）", text: $rule.location).textFieldStyle(.roundedBorder)
            DatePicker("生效日期", selection: $start, displayedComponents: .date)
            DatePicker("结束日期", selection: $end, in: start..., displayedComponents: .date)
            if let weeks = rule.weeks {
                HStack {Text("限定第 "+weeks.map(String.init).joined(separator:",")+" 教学周").font(.system(size:10)).foregroundStyle(muted);Spacer();Button("取消限定周次"){rule.weeks = nil}.buttonStyle(.plain)}
            }
            if rule.cadence != 0 {
                DatePicker("教学第 1 周内的任意一天", selection: $anchor, displayedComponents: .date)
                Text("单双周按教学周计算，从这个日期所在的周一开始计为第 1 周。").font(.system(size: 10)).foregroundStyle(muted)
            }
            HStack {
                if store.db.courses.contains(where: { $0.id == original.id }) {
                    Button("移除课程", role: .destructive) { confirmDelete = true }.buttonStyle(.plain)
                }
                Spacer(); Button("取消") { dismiss() }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction)
                Button("保存课表") {
                    rule.title = rule.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    rule.start = Dates.key(start); rule.end = Dates.key(end); rule.anchor = Dates.key(anchor)
                    store.putCourse(rule); dismiss()
                }.buttonStyle(QuietButton(filled: true)).disabled(rule.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || rule.weekdays.isEmpty || end < start || !ClockTime.validRange(rule.time))
            }.padding(.top, 12)
        }.padding(30).frame(width: 540).background(Color.white)
            .onAppear { rule = original; start = Dates.date(rule.start); end = Dates.date(rule.end); anchor = Dates.date(rule.anchor) }
            .onChange(of: start) { _, value in if end < value { end = value } }
            .confirmationDialog("移除这门课程及未来未完成的安排？历史记录继续保留。", isPresented: $confirmDelete) {
                Button("移除课程", role: .destructive) { store.deleteCourse(original.id); dismiss() }
            }
    }
}

struct SettingsView: View {
    @ObservedObject var store: PlanStore
    @Environment(\.dismiss) var dismiss
    @ViewState<String> private var base: String = ""
    @ViewState<String> private var model: String = ""
    @ViewState<String> private var key: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "保持简单，也留有余地。", subtitle: "任务存在本机。只有点击生成并确认后，才会发送七日记录。")
            HStack { Button("DeepSeek 配置") {base = "https://api.deepseek.com"; model = "deepseek-flash"}.buttonStyle(QuietButton());Text("保留现有密钥").font(.system(size:10)).foregroundStyle(muted) }
            Text("大模型接口").font(.system(size: 13, weight: .medium))
            TextField("基础地址，例如 https://api.openai.com/v1", text: $base).textFieldStyle(.roundedBorder)
            TextField("模型名称，填写服务商提供的模型 ID", text: $model).textFieldStyle(.roundedBorder)
            SecureField("API Key（本地模型可留空）", text: $key).textFieldStyle(.roundedBorder)
            Text("使用兼容 Chat Completions 的接口；地址填写到 /v1 等基础路径。密钥存在本机独立文件中，仅当前用户可读，不进入计划备份。").font(.system(size: 11)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            line.frame(height: 1).padding(.vertical, 8)
            Text("本地数据").font(.system(size: 13, weight: .medium))
            Text("每次编辑即时保存。跨天自动归档，休眠或退出后会在下次运行时补归档。导出 JSON 可完整备份课程、任务和归档。").font(.system(size: 11)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("打开数据目录") { NSWorkspace.shared.open(store.directory) }.buttonStyle(QuietButton())
                Button("导出备份") { store.exportJSON() }.buttonStyle(QuietButton())
            }
            HStack {
                Text("周间 · v0.2.0").font(.system(size: 10)).foregroundStyle(muted)
                Spacer(); Button("取消") { dismiss() }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction)
                Button("保存设置") {
                    do { try KeyStore.write(key); store.db.ai.baseURL = base; store.db.ai.model = model; store.save(); dismiss() }
                    catch { store.error = "密钥未能保存到本机配置：\(error.localizedDescription)" }
                }.buttonStyle(QuietButton(filled: true))
            }.padding(.top, 12)
        }.padding(30).frame(width: 580).background(Color.white)
            .onAppear { base = store.db.ai.baseURL; model = store.db.ai.model; key = KeyStore.read() }
    }
}

struct AIPreview: View {
    @ObservedObject var store: PlanStore
    var prompt: String; var week: Date
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "整理之前，先看一眼。", subtitle: "以下内容将发送到你设置的模型接口；现有复盘会保留。")
            Text("\(store.db.ai.baseURL) · \(store.db.ai.model.isEmpty ? "尚未设置模型" : store.db.ai.model)").font(.system(size: 11)).foregroundStyle(muted)
            ScrollView { Text(prompt).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16) }.frame(height: 320).background(paper).clipShape(RoundedRectangle(cornerRadius: 10))
            if store.db.ai.model.isEmpty { Text("请先关闭此窗口，在右上角设置中填写模型名称。").font(.system(size: 11)).foregroundStyle(muted) }
            HStack {
                Spacer(); Button("取消") { dismiss() }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction)
                Button("发送并生成") { dismiss(); Task { await store.generate(prompt: prompt, week: week) } }.buttonStyle(QuietButton(filled: true)).disabled(store.db.ai.model.isEmpty || store.isGenerating)
            }
        }.padding(30).frame(width: 650).background(Color.white)
    }
}

struct HistoryView: View {
    @ObservedObject var store: PlanStore
    @Environment(\.dismiss) var dismiss
    @ViewState<String?> private var selected: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            SheetHeader(title: "走过的每一天", subtitle: "这里是当天结束时的快照。后续补记不会覆盖它。")
            if store.db.archives.isEmpty {
                Text("还没有归档。第一天结束后，会自动出现在这里。").font(.system(size: 13)).foregroundStyle(muted).frame(maxWidth: .infinity, minHeight: 220)
            } else {
                HStack(alignment: .top, spacing: 20) {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(store.db.archives.sorted { $0.day > $1.day }) { archive in
                                Button { selected = archive.day } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(archive.day).font(.system(size: 13, weight: .medium))
                                        Text("\(archive.tasks.filter(\.completed).count) / \(archive.tasks.count) 已完成").font(.system(size: 10)).foregroundStyle(muted)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(selected == archive.day ? paper : Color.clear).clipShape(RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain)
                            }
                        }
                    }.frame(width: 160)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if let archive = store.db.archives.first(where: { $0.day == selected }) {
                                ForEach(Slot.allCases) { slot in
                                    Text(slot.title).font(.system(size: 12, weight: .medium)).foregroundStyle(muted)
                                    ForEach(archive.tasks.filter { $0.slot == slot }) { t in
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text("\(t.completed ? "✓" : "○") \(t.title)").font(.system(size: 13))
                                            if !t.note.isEmpty { Text(t.note).font(.system(size: 11)).foregroundStyle(muted) }
                                        }
                                    }
                                }
                                Button("查看这一周 / 补记") {
                                    store.followCurrentWeek = false; store.selectedWeek = Dates.date(archive.day); dismiss()
                                }.buttonStyle(QuietButton()).padding(.top, 12)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }.frame(height: 320)
            }
            HStack { Spacer(); Button("关闭") { dismiss() }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction) }
        }.padding(30).frame(width: 690).background(Color.white)
            .onAppear { selected = store.db.archives.sorted { $0.day > $1.day }.first?.day }
    }
}
