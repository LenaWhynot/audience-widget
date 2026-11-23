import Foundation

struct SocialAccount: Codable,Identifiable,Hashable {
    let id:String
    let platform:String
    let handle:String
    let name:String
}
enum Observation { case value(Int);case unavailable }
struct CounterRow: Codable {
    var count:Int?
    var baseline:Int
    var baselineAt:Double
    var notifiedHigh:Int
    var day:String
    var partialDay:Bool
    var checkedAt:Double
    var online:Bool
    var delta:Int { (count ?? baseline)-baseline }
}
struct WidgetState: Codable {
    var rows:[String:CounterRow]=[:]
    var lastPopup:Double=0
    var lastHandledEvent:String?
    var attemptedAt:Double=0
    func observedAt(ids:[String])->Double {
        ids.compactMap {id -> Double? in guard let r=rows[id],r.count != nil,r.checkedAt>0 else{return nil};return r.checkedAt}.min() ?? 0
    }
    var remainingQuota:Int?
    var quotaCheckedAt:Double=0
    var total:Int? {
        let values=rows.values.compactMap{$0.count}
        guard !values.isEmpty else{return nil}
        var total=0
        for n in values {let (sum,overflow)=total.addingReportingOverflow(n);if overflow{return nil};total=sum}
        return total
    }
}
struct GrowthEvent { let id:String;let gain:Int;let changes:[String:Int] }
struct WidgetConfig: Codable {
    var selected:[SocialAccount]=[]
    var paused=false
    var notifications=true
}
enum Engine {
    static func update(_ previous:WidgetState,counts:[String:Observation],now:Double,day:String,quiet:Bool)->(WidgetState,GrowthEvent?) {
        var s=previous;s.rows=s.rows.filter{counts[$0.key] != nil};var changes:[String:Int]=[:]
        let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.dateFormat="yyyy-MM-dd";f.timeZone=TimeZone(secondsFromGMT:0)
        for (id,observation) in counts {
            guard case .value(let value)=observation,value>=0 else {
                if var old=s.rows[id]{old.online=false;s.rows[id]=old};continue
            }
            guard var row=s.rows[id],row.count != nil else {
                s.rows[id]=CounterRow(count:value,baseline:value,baselineAt:now,notifiedHigh:value,day:day,partialDay:true,checkedAt:now,online:true);continue
            }
            if row.day != day {
                let gap=(f.date(from:day)?.timeIntervalSince(f.date(from:row.day) ?? .distantPast) ?? .infinity)>86400
                row.baseline=gap ? value : row.count!;row.baselineAt=now;row.partialDay=gap;row.day=day
            }
            row.count=value;row.online=true;row.checkedAt=now
            if quiet {row.notifiedHigh=max(row.notifiedHigh,value)}
            if value>row.notifiedHigh {changes[id]=value-row.notifiedHigh}
            s.rows[id]=row
        }
        s.attemptedAt=now;var event:GrowthEvent?
        if !quiet,!changes.isEmpty,now-s.lastPopup>=900 {
            let id=String(format:"%.0f",now);event=GrowthEvent(id:id,gain:changes.values.reduce(0,+),changes:changes)
            s.lastPopup=now;s.lastHandledEvent=id
            for key in changes.keys {if var row=s.rows[key] {row.notifiedHigh=row.count ?? 0;s.rows[key]=row}}
        }
        return(s,event)
    }
}
enum Storage {
    static func load<T:Decodable>(_ type:T.Type,url:URL)->T? {
        guard let data=try? Data(contentsOf:url) else{return nil};return try? JSONDecoder().decode(type,from:data)
    }
    static func save<T:Encodable>(_ value:T,url:URL)throws {
        let fm=FileManager.default
        try fm.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let temporary=url.deletingLastPathComponent().appendingPathComponent(".write-"+UUID().uuidString)
        let data=try JSONEncoder().encode(value)
        guard fm.createFile(atPath:temporary.path,contents:data,attributes:[.posixPermissions:0o600]) else{throw CocoaError(.fileWriteUnknown)}
        defer {try? fm.removeItem(at:temporary)}
        if fm.fileExists(atPath:url.path){_ = try fm.replaceItemAt(url,withItemAt:temporary)}else{try fm.moveItem(at:temporary,to:url)}
        try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    }
}
