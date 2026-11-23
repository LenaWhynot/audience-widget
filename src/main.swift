import AppKit
import SwiftUI

#if QA
let qaBuild=true
#else
let qaBuild=false
#endif
let dataRoot:URL = qaBuild ? Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("qa-data") : FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Audience Widget")
let stateURL=dataRoot.appendingPathComponent("state.json")
let configURL=dataRoot.appendingPathComponent("config.json")
let grey=Color(white:0.60),mint=Color(red:0.60,green:0.85,blue:0.68)
func formatted(_ n:Int)->String {let f=NumberFormatter();f.numberStyle = .decimal;f.groupingSeparator=" ";return f.string(from:NSNumber(value:n)) ?? String(n)}
func age(_ t:Double)->String {
    guard t>0 else{return "ещё нет снимка"};let seconds=max(0,Int(Date().timeIntervalSince1970-t))
    if seconds<60{return "только что"};if seconds<3600{return "\(seconds/60) мин назад"};if seconds<86400{return "\(seconds/3600) ч назад"}
    let f=DateFormatter();f.dateFormat="dd.MM HH:mm";return f.string(from:Date(timeIntervalSince1970:t))
}
func localDay()->String {let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.dateFormat="yyyy-MM-dd";return f.string(from:Date())}
func clock(_ t:Double)->String {let f=DateFormatter();f.dateFormat="HH:mm";return f.string(from:Date(timeIntervalSince1970:t))}
final class WidgetPanel:NSPanel {
    override var canBecomeKey:Bool {false}
    override var canBecomeMain:Bool {false}
}
final class ViewModel:ObservableObject {
    @Published var config=WidgetConfig()
    @Published var state=WidgetState()
    @Published var connected=false
    @Published var loading=false
    @Published var connecting=false
    @Published var available:[SocialAccount]=[]
    @Published var message=""
    var refresh:(()->Void)?
    var setup:(()->Void)?
    var settings:((NSView)->Void)?
    weak var gear:NSView?
}
struct Gear:NSViewRepresentable {
    let model:ViewModel
    func makeCoordinator()->Coordinator {Coordinator(model)}
    func makeNSView(context:Context)->NSButton {
        let b=NSButton(image:NSImage(systemSymbolName:"gearshape",accessibilityDescription:"Настройки")!,target:context.coordinator,action:#selector(Coordinator.click(_:)))
        b.isBordered=false;b.imageScaling = .scaleProportionallyDown;b.contentTintColor=NSColor(calibratedWhite:0.65,alpha:1);b.setAccessibilityLabel("Настройки")
        model.gear=b;return b
    }
    func updateNSView(_ v:NSButton,context:Context){model.gear=v}
    final class Coordinator:NSObject {
        weak var model:ViewModel?
        init(_ m:ViewModel){model=m}
        @objc func click(_ sender:NSButton){model?.settings?(sender)}
    }
}
struct Logo:View {
    let platform:String
    var body:some View {
        Group {
            if ["threads","tiktok"].contains(platform),let u=Bundle.main.url(forResource:platform,withExtension:"svg"),let image=NSImage(contentsOf:u) {Image(nsImage:image).renderingMode(.template).resizable().scaledToFit()}
            else {Image(systemName:symbol).font(.system(size:15))}
        }.frame(width:16,height:16).foregroundStyle(Color.white.opacity(0.78))
    }
    var symbol:String {
        switch platform {
        case "instagram":return "camera"
        case "telegram":return "paperplane.fill"
        case "youtube":return "play.rectangle.fill"
        case "x","twitter":return "xmark"
        case "vk":return "v.square"
        case "facebook":return "f.square"
        default:return "person.crop.circle"
        }
    }
}
struct TotalTiles:View {
    let total:Int?
    var characters:[Character] {Array(total.map(String.init) ?? "—")}
    var width:CGFloat {min(44,(300-CGFloat(max(0,characters.count-1))*4-CGFloat(max(0,(characters.count-1)/3))*8)/CGFloat(max(1,characters.count)))}
    var body:some View {
        HStack(spacing:4) {
            ForEach(Array(characters.enumerated()),id:\.offset) {index,digit in
                if index>0 && (characters.count-index)%3==0 {Color.clear.frame(width:4,height:1)}
                ZStack {
                    RoundedRectangle(cornerRadius:5).fill(LinearGradient(colors:[Color(white:0.17),Color(white:0.12)],startPoint:.top,endPoint:.bottom))
                    Text(String(digit)).font(.system(size:42,weight:.medium,design:.rounded)).monospacedDigit()
                    Rectangle().fill(.black.opacity(0.7)).frame(height:1)
                }.frame(width:width,height:64)
            }
        }.help("Сумма подписок, не уникальные люди")
        .accessibilityElement(children:.ignore).accessibilityLabel("Всего \(total.map(formatted) ?? "неизвестно") подписок. Люди могут повторяться.")
    }
}
struct Card:View {
    @ObservedObject var model:ViewModel
    var observedAt:Double {model.state.observedAt(ids:model.config.selected.map{$0.id})}
    var completeTotal:Int? {model.config.selected.allSatisfy{model.state.rows[$0.id]?.count != nil} ? model.state.total : nil}
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack {
                Text(qaBuild && !model.config.selected.isEmpty ? "ТЕСТОВЫЙ ПРОСМОТР" : "AUDIENCE").font(.system(size:10,weight:.semibold)).tracking(1.5).foregroundStyle(grey)
                Spacer()
                if !model.message.isEmpty {Image(systemName:"exclamationmark.circle").font(.system(size:10)).foregroundStyle(.orange).help(model.message)}
                Button{model.refresh?()}label:{Image(systemName:model.loading ? "ellipsis" : "arrow.clockwise").font(.system(size:11))}.buttonStyle(.plain).disabled(model.loading || !model.connected || model.config.selected.isEmpty)
                    .help("Последнее наблюдение: " + age(observedAt) + ". Время сбора LiveDune неизвестно. Интервал 15 мин.")
                    .accessibilityLabel("Обновить")
                Gear(model:model).frame(width:13,height:12).padding(.leading,3)
            }.frame(height:12).padding(.bottom,16)
            if model.config.selected.isEmpty {
                Text("Своя аудитория.\nНа рабочем столе.").font(.system(size:25,weight:.medium,design:.rounded)).padding(.vertical,10)
                Text("Подключите свой LiveDune и выберите аккаунты. Ключ останется в Связке ключей этого Mac.").font(.system(size:12)).foregroundStyle(grey).fixedSize(horizontal:false,vertical:true).padding(.top,7)
                Button("Подключить LiveDune"){model.setup?()}.buttonStyle(.borderedProminent).tint(Color(white:0.28)).padding(.top,20)
                Text("Нужен собственный доступ к API LiveDune").font(.system(size:9)).foregroundStyle(grey).padding(.top,12)
            } else {
                TotalTiles(total:completeTotal).padding(.bottom,16)
                Rectangle().fill(.white.opacity(0.10)).frame(height:1).padding(.bottom,8)
                ForEach(model.config.selected) {a in accountRow(a)}
                HStack {
                    Text(model.config.paused ? "На паузе" : "LiveDune · 15 мин").font(.system(size:9))
                    Spacer()
                    Text(age(observedAt)).font(.system(size:9))
                }.foregroundStyle(grey).padding(.top,12).help("Время проверки не означает время сбора провайдером. Дневной прирост — изменение общего счётчика по снимкам.")
            }
        }.padding(20).frame(width:340).background(Color(white:0.045)).clipShape(RoundedRectangle(cornerRadius:19))
        .overlay(RoundedRectangle(cornerRadius:19).stroke(.white.opacity(0.08),lineWidth:1))
        .foregroundStyle(Color(white:0.92)).preferredColorScheme(.dark)
    }
    func accountRow(_ a:SocialAccount)->some View {
        let row=model.state.rows[a.id]
        let delta=row.map{($0.delta>0 ? "+" : "")+formatted($0.delta)} ?? "—"
        let period=row.map{$0.partialDay ? "с " + clock($0.baselineAt) : "за день"} ?? ""
        return HStack(spacing:8) {
            Logo(platform:a.platform)
            Text(a.handle.hasPrefix("@") ? a.handle : "@"+a.handle).font(.system(size:12)).foregroundStyle(grey).lineLimit(1).truncationMode(.middle)
            Spacer(minLength:4)
            if row?.online==false {Circle().fill(Color.orange).frame(width:4,height:4)}
            Text(row?.online==true ? delta : "—").font(.system(size:11)).monospacedDigit().foregroundStyle((row?.delta ?? 0)>0 ? mint : grey)
            Text(row?.count.map(formatted) ?? "—").font(.system(size:15,weight:.semibold,design:.rounded)).monospacedDigit().frame(minWidth:55,alignment:.trailing)
        }.frame(height:24).help(a.name + " · " + delta + " " + period + " · наблюдение " + age(row?.checkedAt ?? 0) + ". Время сбора источником неизвестно.")
        .accessibilityElement(children:.combine)
    }
}
struct ActionStyle:ButtonStyle {
    @Environment(\.isEnabled) var enabled
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.system(size:12,weight:.medium)).foregroundStyle(Color.white.opacity(enabled ? 0.92 : 0.40)).padding(.horizontal,12).padding(.vertical,8).background(Color(white:enabled ? 0.23 : 0.13),in:RoundedRectangle(cornerRadius:7))
    }
}
struct ChecklistStyle:ToggleStyle {
    func makeBody(configuration:Configuration)->some View {
        Button {configuration.isOn.toggle()} label:{
            HStack(spacing:8){Image(systemName:configuration.isOn ? "checkmark.square.fill" : "square").foregroundStyle(configuration.isOn ? mint : grey);configuration.label}
        }.buttonStyle(.plain).accessibilityValue(configuration.isOn ? "выбран" : "не выбран")
    }
}
struct Setup:View {
    @ObservedObject var model:ViewModel
    let connect:(String)->Void
    let apply:([SocialAccount])->Void
    let forget:()->Void
    @State var token=""
    @State var chosen:Set<String>=[]
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("Подключить LiveDune").font(.system(size:24,weight:.semibold))
            Text("Ключ только вашего кабинета. Он отправляется по HTTPS только api.livedune.com и хранится в Связке ключей Mac.").font(.system(size:12)).foregroundStyle(.secondary)
            Link("Открыть LiveDune → Настройки → API",destination:URL(string:"https://pro.livedune.com/settings/api")!)
            SecureField("Ваш API-ключ",text:$token).textFieldStyle(.roundedBorder)
            HStack {
                Button(model.connecting ? "Проверяю…" : "Подключить"){let key=token;token="";chosen=[];connect(key)}.buttonStyle(ActionStyle()).disabled(model.connecting || token.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                if model.connecting {ProgressView().controlSize(.small)}
                if model.connected {Button("Удалить подключение",action:forget).buttonStyle(ActionStyle())}
            }
            if !model.message.isEmpty {Text(model.message).font(.system(size:11)).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)}
            if !model.available.isEmpty {
                Text("Выберите до 12 аккаунтов для виджета").font(.system(size:13,weight:.medium))
                ScrollView {
                    VStack(alignment:.leading,spacing:8) {
                        ForEach(model.available) {a in
                            Toggle(isOn:Binding(get:{chosen.contains(a.id)},set:{on in if on && chosen.count<12 {chosen.insert(a.id)} else {chosen.remove(a.id)}})) {
                                Text(a.platform + " · " + a.handle).lineLimit(1)
                            }.toggleStyle(ChecklistStyle())
                        }
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }.frame(maxHeight:190)
                Text("При 15 мин: до \(chosen.count*96) запросов/день,≈\(chosen.count*2880) за 30 дней. Остаток квоты: \(model.state.remainingQuota.map(formatted) ?? "неизвестен").").font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Button("Показать выбранные аккаунты"){apply(model.available.filter{chosen.contains($0.id)})}.buttonStyle(ActionStyle()).disabled(chosen.isEmpty)
            } else {
                Text("Аккаунты появятся после проверки ключа. Добавьте их в свой Dashboard LiveDune заранее. Лайки/просмотры в этой версии не показываются.").font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            Spacer(minLength:0)
        }.padding(24).frame(width:480,height:560).background(Color(white:0.07)).foregroundStyle(Color(white:0.90)).preferredColorScheme(.dark)
        .onAppear {chosen=Set(model.config.selected.map{$0.id})}
    }
}
final class Delegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
    let model=ViewModel(),api=APIClient()
    var window:WidgetPanel!
    var host:NSHostingView<Card>!
    var setupWindow:NSWindow?
    var timer:Timer?,ageTimer:Timer?
    var refreshTask:Task<Void,Never>?
    var connectionTask:Task<Void,Never>?
    var generation=0,failures=0
    var sessionActive=true
    var popup:WidgetPanel?
    func applicationDidFinishLaunching(_ note:Notification) {
        NSApp.setActivationPolicy(.accessory)
        if !qaBuild {
            model.config=Storage.load(WidgetConfig.self,url:configURL) ?? WidgetConfig()
            model.state=Storage.load(WidgetState.self,url:stateURL) ?? WidgetState()
            model.connected=KeyStore.load() != nil
        }
        #if QA
        if CommandLine.arguments.contains("--fixture-preview") {
            model.config.selected=[SocialAccount(id:"101",platform:"instagram",handle:"example.creator",name:"Example Creator"),SocialAccount(id:"102",platform:"telegram",handle:"example_channel",name:"Example Channel")]
            model.state=Engine.update(WidgetState(),counts:["101":.value(120),"102":.value(45)],now:Date().timeIntervalSince1970,day:localDay(),quiet:true).0
        }
        #endif
        model.setup={ [weak self] in self?.presentSetup() }
        model.refresh={ [weak self] in self?.refresh(quiet:false) }
        model.settings={ [weak self] a in self?.menu().popUp(positioning:nil,at:NSPoint(x:0,y:a.bounds.minY-3),in:a) }
        host=NSHostingView(rootView:Card(model:model));let h=host.fittingSize.height
        let f=NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1440,height:900)
        window=WidgetPanel(contentRect:NSRect(x:f.maxX-370,y:f.maxY-h-30,width:340,height:h),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        window.title="Audience Widget";window.isOpaque=false;window.backgroundColor = .clear;window.hasShadow=true
        window.level=NSWindow.Level(rawValue:Int(CGWindowLevelForKey(.desktopIconWindow))+1)
        window.collectionBehavior=[.canJoinAllSpaces,.stationary,.ignoresCycle];window.hidesOnDeactivate=false
        window.isMovableByWindowBackground=true;window.contentView=host;window.delegate=self
        if !qaBuild,let stored=UserDefaults.standard.string(forKey:"frame") {let rect=NSRectFromString(stored);if NSScreen.screens.contains(where:{$0.visibleFrame.intersects(rect)}){window.setFrameOrigin(NSPoint(x:rect.minX,y:rect.maxY-h))}}
        window.orderFrontRegardless()
        let nc=NSWorkspace.shared.notificationCenter
        nc.addObserver(self,selector:#selector(wake),name:NSWorkspace.didWakeNotification,object:nil)
        nc.addObserver(self,selector:#selector(inactive),name:NSWorkspace.sessionDidResignActiveNotification,object:nil)
        nc.addObserver(self,selector:#selector(active),name:NSWorkspace.sessionDidBecomeActiveNotification,object:nil)
        ageTimer=Timer.scheduledTimer(withTimeInterval:60,repeats:true){[weak self]_ in self?.model.objectWillChange.send();self?.savePosition()}
        if !qaBuild {refresh(quiet:true)}
        #if QA
        if CommandLine.arguments.contains("--setup-preview") {
            model.available=[SocialAccount(id:"101",platform:"instagram",handle:"example.creator",name:"Example Creator"),SocialAccount(id:"102",platform:"telegram",handle:"example_channel",name:"Example Channel")]
            model.state.remainingQuota=40000
            presentSetup()
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+1) {
            try? FileManager.default.createDirectory(at:dataRoot,withIntermediateDirectories:true)
            if CommandLine.arguments.contains("--setup-preview"),let setupView=self.setupWindow?.contentView {
                self.capture(setupView,to:dataRoot.appendingPathComponent("setup-preview.png"))
                let chosen=Array(self.model.available.prefix(1))
                self.select(chosen)
                let proof:[String:Any] = ["selection_handler_exercised":self.model.config.selected==chosen,"selected_count":self.model.config.selected.count,"selected_ids":self.model.config.selected.map{$0.id},"network_disabled":qaBuild,"keychain_disabled":qaBuild]
                if let data=try? JSONSerialization.data(withJSONObject:proof,options:[.prettyPrinted]) {try? data.write(to:dataRoot.appendingPathComponent("setup-selection-qa.json"))}
            } else {
                self.capture(self.host,to:dataRoot.appendingPathComponent(CommandLine.arguments.contains("--fixture-preview") ? "fixture-preview.png" : "first-launch.png"))
            }
            NSApp.terminate(nil)
        }
        #endif
    }
    func persist() {
        guard !qaBuild else{return}
        do {try Storage.save(model.config,url:configURL);try Storage.save(model.state,url:stateURL)}catch{model.message="Не удалось сохранить данные на этом Mac. Уведомления приостановлены.";model.config.paused=true}
    }
    func schedule(_ seconds:Double=900) {
        timer?.invalidate();guard !qaBuild,!model.config.paused else{return}
        timer=Timer.scheduledTimer(withTimeInterval:seconds,repeats:false){[weak self]_ in self?.refresh(quiet:false)};timer?.tolerance=10
    }
    func refresh(quiet:Bool) {
        guard !qaBuild,!model.loading,!model.config.paused,!model.config.selected.isEmpty else{return}
        guard let key=KeyStore.load() else{model.connected=false;model.message="Подключите свой ключ LiveDune через настройки.";return}
        model.loading=true;let version=generation;let accounts=model.config.selected
        refreshTask=Task { [weak self] in
            guard let self=self else{return}
            var quota=self.model.state.remainingQuota
            do {
                if Date().timeIntervalSince1970-self.model.state.quotaCheckedAt>86400 {
                    let fetchedQuota=try await self.api.quota(token:key);quota=fetchedQuota
                    await MainActor.run {if version==self.generation {self.model.state.remainingQuota=fetchedQuota;self.model.state.quotaCheckedAt=Date().timeIntervalSince1970}}
                }
                if let left=quota,left<accounts.count {throw APIError.quota}
                let reservedQuota=quota.map{max(0,$0-accounts.count)}
                await MainActor.run {if version==self.generation {self.model.state.remainingQuota=reservedQuota;self.persist()}}
                var counts=Dictionary(uniqueKeysWithValues:accounts.map{($0.id,Observation.unavailable)});var fatal:APIError?
                for start in stride(from:0,to:accounts.count,by:4) {
                    let chunk=Array(accounts[start..<min(start+4,accounts.count)])
                    await withTaskGroup(of:(String,Observation,APIError?).self) {group in
                        for a in chunk {group.addTask {
                            do {let n=try await self.api.followers(account:a,token:key);return(a.id,n.map{Observation.value($0)} ?? .unavailable,nil)}catch let e as APIError{return(a.id,.unavailable,e)}catch{return(a.id,.unavailable,.unavailable)}
                        }}
                        for await(id,observation,error) in group {counts[id]=observation;if error == .quota || error == .denied {fatal=error}}
                    }
                    if fatal != nil {break}
                }
                let finalCounts=counts,finalError=fatal
                await MainActor.run {
                    guard version==self.generation else{return};self.model.loading=false
                    let noPopup=quiet || !self.model.config.notifications || !self.sessionActive
                    let (state,event)=Engine.update(self.model.state,counts:finalCounts,now:Date().timeIntervalSince1970,day:localDay(),quiet:noPopup)
                    self.model.state=state
                    if let fatal=finalError {self.model.message=fatal.message;self.model.config.paused=true}
                    else {self.model.message=finalCounts.values.contains{if case .unavailable=$0{return true};return false} ? APIError.unavailable.message : ""}
                    self.failures=self.model.message.isEmpty ? 0 : self.failures+1
                    self.persist();self.resizeKeepingTop()
                    if let event=event,!self.model.config.paused {self.showGrowth(event)}
                    self.schedule(self.failures>0 ? min(900,60*pow(2,Double(min(4,self.failures-1)))) : 900)
                }
            } catch {
                await MainActor.run {
                    guard version==self.generation else{return};self.model.loading=false
                    let e=(error as? APIError) ?? .unavailable;self.model.message=e.message
                    if e == .quota || e == .denied {self.model.config.paused=true}
                    self.persist();self.schedule()
                }
            }
        }
    }
    @objc func presentSetup() {
        if let w=setupWindow {w.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);return}
        let setup=Setup(model:model,connect:{[weak self] key in self?.connect(key)},apply:{[weak self] accounts in self?.select(accounts)},forget:{[weak self] in self?.confirmDisconnect()})
        let w=NSWindow(contentRect:NSRect(x:0,y:0,width:480,height:560),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        w.title="Audience Widget · Подключение";w.contentView=NSHostingView(rootView:setup);w.isReleasedWhenClosed=false;w.center();setupWindow=w
        w.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        if !qaBuild,model.connected,let key=KeyStore.load() {
            model.connecting=true;let ticket=generation;connectionTask?.cancel()
            connectionTask=Task {
                do {
                    let (list,calls)=try await api.accounts(token:key)
                    await MainActor.run {
                        guard ticket==self.generation,!Task.isCancelled else{return}
                        self.model.available=list;self.model.state.remainingQuota=self.model.state.remainingQuota.map{max(0,$0-calls)};self.model.connecting=false;self.persist()
                    }
                } catch {await MainActor.run{
                    guard ticket==self.generation,!Task.isCancelled else{return}
                    self.model.message=((error as? APIError) ?? .unavailable).message;self.model.connecting=false
                }}
            }
        }
    }
    func connect(_ raw:String) {
        guard !qaBuild else{model.message="Тестовый запуск: сеть и Связка ключей отключены.";return}
        let key=raw.trimmingCharacters(in:.whitespacesAndNewlines);guard !key.isEmpty else{return}
        generation+=1;let ticket=generation;connectionTask?.cancel();refreshTask?.cancel();timer?.invalidate();model.loading=false
        model.connecting=true;model.message=""
        connectionTask=Task {
            do {
                let quota=try await api.quota(token:key);guard quota>1 else{throw APIError.quota}
                let (accounts,calls)=try await api.accounts(token:key)
                try await MainActor.run {
                    guard ticket==self.generation,!Task.isCancelled else{throw CancellationError()}
                    try KeyStore.save(key)
                }
                await MainActor.run {
                    guard ticket==self.generation else{return}
                    self.refreshTask?.cancel();self.timer?.invalidate();self.model.loading=false
                    self.model.config.selected=[];self.model.state=WidgetState();self.model.state.remainingQuota=max(0,quota-calls);self.model.state.quotaCheckedAt=Date().timeIntervalSince1970
                    self.model.available=accounts;self.model.connected=true;self.model.connecting=false
                    self.model.message=accounts.isEmpty ? "В Dashboard LiveDune нет доступных аккаунтов." : "";self.persist();self.resizeKeepingTop()
                }
            } catch {await MainActor.run{guard ticket==self.generation else{return};self.model.connecting=false;self.model.message=((error as? APIError) ?? .invalidRequest).message;self.schedule()}}
        }
    }
    @objc func confirmDisconnect() {
        let a=NSAlert();a.messageText="Удалить подключение LiveDune?";a.informativeText="Ключ этого виджета будет удалён из Связки ключей, локальный выбор и снимки очищены. Аккаунты в LiveDune останутся.";a.addButton(withTitle:"Удалить");a.addButton(withTitle:"Отмена")
        guard a.runModal() == .alertFirstButtonReturn else{return}
        generation+=1;refreshTask?.cancel();connectionTask?.cancel();timer?.invalidate();model.loading=false;model.connecting=false
        do {try KeyStore.delete()}catch{model.message="Не удалось удалить ключ из Связки ключей.";return}
        model.connected=false;model.config.selected=[];model.available=[];model.state=WidgetState();model.message=""
        setupWindow?.close();setupWindow=nil;persist();resizeKeepingTop();presentSetup()
    }
    func select(_ accounts:[SocialAccount]) {
        guard !accounts.isEmpty,accounts.count<=12 else{return}
        let allowed=Set(model.available.map{$0.id});guard accounts.allSatisfy({allowed.contains($0.id)}) else{return}
        generation+=1;refreshTask?.cancel();model.loading=false
        model.config.selected=accounts;let ids=Set(accounts.map{$0.id});model.state.rows=model.state.rows.filter{ids.contains($0.key)}
        model.config.paused=false;persist();resizeKeepingTop();setupWindow?.orderOut(nil);refresh(quiet:true)
    }
    func menu()->NSMenu {
        let m=NSMenu()
        let values:[(String,Selector)]=[("Обновить сейчас",#selector(manualRefresh)),("Подключение и аккаунты…",#selector(presentSetup)),(model.config.paused ? "Продолжить обновления" : "Пауза обновлений",#selector(pause)),(model.config.notifications ? "Выключить уведомления" : "Включить уведомления",#selector(notifications)),("Удалить подключение…",#selector(confirmDisconnect)),("Скрыть карточку",#selector(hide)),("Завершить",#selector(quit))]
        for(title,action) in values {let i=NSMenuItem(title:title,action:action,keyEquivalent:"");i.target=self;m.addItem(i)};return m
    }
    func resizeKeepingTop() {DispatchQueue.main.async {let top=self.window.frame.maxY;let h=self.host.fittingSize.height;self.window.setFrame(NSRect(x:self.window.frame.minX,y:top-h,width:340,height:h),display:true);self.savePosition()}}
    func savePosition(){if !qaBuild,let w=window {UserDefaults.standard.set(NSStringFromRect(w.frame),forKey:"frame")}}
    func windowDidMove(_ notification:Notification){savePosition()}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {window.orderFrontRegardless();return false}
    @objc func hide(){window.orderOut(nil)}
    @objc func manualRefresh(){if model.config.paused{model.config.paused=false;persist()};refresh(quiet:false)}
    @objc func pause(){model.config.paused.toggle();timer?.invalidate();persist();if !model.config.paused{refresh(quiet:true)}}
    @objc func notifications(){model.config.notifications.toggle();persist()}
    @objc func wake(){refresh(quiet:true)}
    @objc func inactive(){sessionActive=false;popup?.orderOut(nil)}
    @objc func active(){sessionActive=true;wake()}
    @objc func quit(){savePosition();timer?.invalidate();refreshTask?.cancel();connectionTask?.cancel();NSApp.terminate(nil)}
    func showGrowth(_ event:GrowthEvent) {
        guard !qaBuild,sessionActive,model.config.notifications else{return}
        let view=VStack(alignment:.leading,spacing:7){Text("Аудитория выросла на\(event.gain)").font(.system(size:14,weight:.semibold));Text("По новому снимку LiveDune").font(.system(size:11)).foregroundStyle(grey)}.padding(20).frame(width:300,alignment:.leading).background(Color(white:0.05)).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius:18))
        let h=NSHostingView(rootView:view),f=NSScreen.main?.visibleFrame ?? window.frame
        let p=WidgetPanel(contentRect:NSRect(x:f.maxX-320,y:f.minY+25,width:300,height:h.fittingSize.height),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        p.isOpaque=false;p.backgroundColor = .clear;p.contentView=h;p.level = .floating;p.hidesOnDeactivate=false;p.orderFrontRegardless();popup=p
        DispatchQueue.main.asyncAfter(deadline:.now()+5){[weak self,weak p] in p?.orderOut(nil);self?.popup=nil}
    }
    func capture(_ view:NSView,to url:URL) {
        view.layoutSubtreeIfNeeded();if let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds){view.cacheDisplay(in:view.bounds,to:rep);if let data=rep.representation(using:.png,properties:[:]){try? data.write(to:url)}}
    }
}
let application=NSApplication.shared
let delegate=Delegate();application.delegate=delegate
application.run()
