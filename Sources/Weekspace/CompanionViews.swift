import SwiftUI
import AppKit

struct QuoteView:View {
    @ObservedObject var store:PlanStore
    var compact = false
    var body:some View {
        let q = store.displayedQuote
        VStack(alignment:.leading,spacing:8) {
            Text(q.text).font(.system(size:compact ? 18:22,weight:.regular)).tracking(-0.4).lineSpacing(4).lineLimit(2).textSelection(.enabled)
            HStack(spacing:8) {
                Text("— " + q.author + " · " + q.source).lineLimit(1)
                Spacer()
                if !compact {
                    if let url = URL(string:q.link),!q.link.isEmpty {Link(q.day == Dates.key(Date()) ? "今日哲思 · 一言":"上次缓存 · 一言",destination:url).foregroundStyle(muted)}
                    else {Text("离线精选")}
                    Button {Task {await store.refreshQuote(force:true)}} label:{Image(systemName:store.quoteLoading ? "hourglass":"arrow.clockwise")}.buttonStyle(.plain).disabled(store.quoteLoading).help(store.quoteStatus.isEmpty ? "每天联网更新一句哲思；网络失败时保留缓存。":store.quoteStatus)
                }
            }.font(.system(size:10)).foregroundStyle(muted)
        }
    }
}
struct TimeRangePicker:View {
    @Binding var time:String
    var slot:Slot
    @ViewState<Bool> private var enabled = false
    @ViewState<Int> private var start = 540
    @ViewState<Int> private var end = 600
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            Toggle("安排具体时间",isOn:$enabled).toggleStyle(.checkbox).font(.system(size:12))
            if enabled {
                HStack(spacing:10) {
                    clock("开始",value:$start)
                    Text("—").foregroundStyle(muted)
                    clock("结束",value:$end)
                }
                if end <= start {Text("结束时间需要晚于开始时间；跨天任务请分别安排。").font(.system(size:10)).foregroundStyle(.red)}
            }
        }.onAppear {let bounds = ClockTime.bounds(time,slot:slot);start = bounds.0;end = bounds.1;enabled = !time.isEmpty}
            .onChange(of:start){_,_ in publish()}.onChange(of:end){_,_ in publish()}
            .onChange(of:enabled){_,value in if value {publish()} else {time = ""} }
    }
    func clock(_ title:String,value:Binding<Int>)->some View {
        HStack(spacing:3) {
            Text(title).font(.system(size:11)).foregroundStyle(muted)
            Picker(title + "小时",selection:Binding(get:{value.wrappedValue/60},set:{value.wrappedValue = $0*60+value.wrappedValue%60})) {ForEach(0..<24,id:\.self){Text(String(format:"%02d",$0)).tag($0)}}.labelsHidden().frame(width:65)
            Text(":")
            Picker(title + "分钟",selection:Binding(get:{value.wrappedValue%60},set:{value.wrappedValue = value.wrappedValue/60*60+$0})) {ForEach(0..<60,id:\.self){Text(String(format:"%02d",$0)).tag($0)}}.labelsHidden().frame(width:65)
        }
    }
    func publish(){if enabled {time = ClockTime.label(start) + "–" + ClockTime.label(end)}}
}
struct PoolView:View {
    @ObservedObject var store:PlanStore
    @ViewState<String> private var draft = ""
    @ViewState<UUID?> private var editing:UUID? = nil
    @ViewState<String> private var editedTitle = ""
    @ViewState<PoolItem?> private var removed:PoolItem? = nil
    var body:some View {
        VStack(alignment:.leading,spacing:11) {
            HStack {Text("随心安排").font(.system(size:15,weight:.medium));Spacer();Image(systemName:"tray").foregroundStyle(muted)}
            Text("先收下想法，拖到合适的时段。可重复拖动。").font(.system(size:10)).foregroundStyle(muted)
            HStack {
                TextField("写一个待安排的任务…",text:$draft).font(.system(size:12)).textFieldStyle(.plain).onSubmit{add()}.accessibilityLabel("随心安排新任务")
                Button(action:add){Image(systemName:"plus.circle.fill").foregroundStyle(ink)}.buttonStyle(.plain).disabled(draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }.padding(10).background(Color.white).clipShape(RoundedRectangle(cornerRadius:8))
            ScrollView {
                VStack(spacing:7) {
                    ForEach(store.db.pool) {item in
                        HStack(spacing:7) {
                            Image(systemName:"line.3.horizontal").font(.system(size:10)).foregroundStyle(muted.opacity(0.6))
                            if editing == item.id {
                                TextField("任务名称",text:$editedTitle).textFieldStyle(.plain).onSubmit {
                                    if let i = store.db.pool.firstIndex(where:{$0.id == item.id}),!editedTitle.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {store.db.pool[i].title = editedTitle;store.save()};editing = nil
                                }
                            } else {Text(item.title).font(.system(size:12)).lineLimit(2)}
                            Spacer(minLength:0)
                            Button {remove(item)} label:{Image(systemName:"xmark").font(.system(size:10)).foregroundStyle(muted.opacity(0.65))}.buttonStyle(.plain).help("快捷删除此模板").accessibilityLabel("删除模板："+item.title)
                        }.padding(10).frame(maxWidth:.infinity,alignment:.leading).background(Color.white.opacity(0.75)).clipShape(RoundedRectangle(cornerRadius:7))
                            .onDrag {NSItemProvider(object:("pool:"+item.id.uuidString) as NSString)}
                            .contextMenu {
                                Button("修改模板名称"){editing = item.id;editedTitle = item.title}
                                Menu("安排到今天") {ForEach(Slot.allCases){slot in Button(slot.title){store.placePool(item.id,day:Date(),slot:slot)}}}
                                Button("移除模板",role:.destructive){remove(item)}
                            }
                    }
                    if store.db.pool.isEmpty {Text("阅读、运动、写报告…\n还没想好放在哪天，也可以先写在这里。").font(.system(size:11)).foregroundStyle(muted.opacity(0.65)).frame(maxWidth:.infinity,alignment:.leading).padding(.top,8)}
                }
            }.scrollIndicators(.hidden)
            if let last = removed {
                HStack {Text("已移除模板").foregroundStyle(muted);Spacer();Button("撤销") {if !store.db.pool.contains(where:{$0.id == last.id}) {store.db.pool.append(last);store.save()};removed = nil}.buttonStyle(.plain)}.font(.system(size:10))
            }
        }
    }
    func remove(_ item:PoolItem){removed = item;store.db.pool.removeAll{$0.id == item.id};store.save()}
    func add(){store.addPool(draft);draft = ""}
}
struct DesktopPlannerView:View {
    @ObservedObject var store:PlanStore
    @ViewState<Int> private var offset = 0
    @ViewState<String> private var draft = ""
    @ViewState<Slot> private var slot = .morning
    @ViewState<Bool> private var floating = false
    var day:Date {Dates.add(offset,to:Date())}
    var body:some View {
        VStack(alignment:.leading,spacing:15) {
            HStack {
                Label("周间",systemImage:"square.grid.2x2").font(.system(size:13,weight:.semibold))
                Spacer()
                Button {floating.toggle();AppDelegate.shared?.desktopWindow?.level = floating ? .floating : NSWindow.Level(rawValue:Int(CGWindowLevelForKey(.desktopIconWindow))+1)} label:{Image(systemName:floating ? "pin.fill":"pin")}.help("切换置顶或贴在桌面")
                Button {AppDelegate.shared?.show()} label:{Image(systemName:"arrow.up.right")}.help("打开完整计划")
                Button {AppDelegate.shared?.desktopWindow?.orderOut(nil)} label:{Image(systemName:"xmark")}.help("隐藏桌面视图")
            }.buttonStyle(.plain).foregroundStyle(muted)
            HStack {
                Button {offset -= 1} label:{Image(systemName:"chevron.left")}
                Spacer();Text(Dates.label(day,"M月d日 EEEE")).font(.system(size:18,weight:.medium));Spacer()
                Button {offset += 1} label:{Image(systemName:"chevron.right")}
            }.buttonStyle(.plain)
            HStack(spacing:0) {
                ForEach(0..<7,id:\.self) {i in
                    let d = Dates.add(i,to:Date())
                    Button {offset = i} label:{VStack(spacing:5){Text(Dates.label(d,"EEEEE")).font(.system(size:9));Text(Dates.label(d,"d")).font(.system(size:12,weight:.medium))}.frame(maxWidth:.infinity).padding(.vertical,8).background(i == offset ? ink:Color.clear).foregroundStyle(i == offset ? Color.white:muted).clipShape(RoundedRectangle(cornerRadius:7))}.buttonStyle(.plain)
                }
            }
            ScrollView {
                VStack(alignment:.leading,spacing:13) {
                    ForEach(Slot.allCases) {slot in
                        HStack {Image(systemName:slot.icon);Text(slot.title)}.font(.system(size:11)).foregroundStyle(muted)
                        let items = store.items(day:day,slot:slot)
                        if items.isEmpty {Text("留一点空白").font(.system(size:11)).foregroundStyle(muted.opacity(0.5)).padding(.leading,20)}
                        ForEach(items) {task in
                            HStack(alignment:.top,spacing:8) {
                                Button{store.toggle(task)} label:{Image(systemName:task.completed ? "checkmark.circle.fill":"circle").foregroundStyle(task.completed ? green:muted.opacity(0.6))}.buttonStyle(.plain).help("切换任务完成状态")
                                VStack(alignment:.leading,spacing:3) {Text(task.title).strikethrough(task.completed).font(.system(size:12));if !task.time.isEmpty {Text(task.time).font(.system(size:9)).foregroundStyle(muted)}}
                            }
                        }
                        line.frame(height:1)
                    }
                }
            }.scrollIndicators(.hidden)
            HStack(spacing:8) {
                Picker("时段",selection:$slot){ForEach(Slot.allCases){Text($0.title).tag($0)}}.labelsHidden().frame(width:72)
                TextField("快速添加…",text:$draft).textFieldStyle(.plain).font(.system(size:12)).onSubmit{add()}.accessibilityLabel("桌面视图快速添加")
                Button(action:add){Image(systemName:"plus.circle.fill")}.buttonStyle(.plain)
            }.padding(10).background(Color.white.opacity(0.7)).clipShape(RoundedRectangle(cornerRadius:8))
            Text("直接勾选与添加 · 与主面板同步").font(.system(size:9)).foregroundStyle(muted)
        }.padding(20).frame(minWidth:340,maxWidth:.infinity,minHeight:500,maxHeight:.infinity).background(paper).foregroundStyle(ink).preferredColorScheme(.light)
            .onChange(of:offset){_,_ in store.db.materialize(day);store.save()}
    }
    func add(){let title = draft.trimmingCharacters(in:.whitespacesAndNewlines);guard !title.isEmpty else{return};store.put(PlanTask(day:Dates.key(day),slot:slot,title:title));draft = ""}
}
