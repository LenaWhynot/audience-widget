import Foundation
var checks=0
func check(_ test:Bool,_ name:String){ if !test { fputs("FAIL: \(name)\n",stderr);exit(1) };checks+=1 }
var s=WidgetState()
let first=Engine.update(s,counts:["101":.value(10),"102":.value(20)],now:1000,day:"2026-11-19",quiet:false)
s=first.0;check(s.total==30 && first.1==nil,"first baseline")
let grown=Engine.update(s,counts:["101":.value(12),"102":.value(21)],now:2000,day:"2026-11-19",quiet:false)
s=grown.0;check(grown.1?.gain==3,"grouped gain")
let repeated=Engine.update(s,counts:["101":.value(12),"102":.value(21)],now:3000,day:"2026-11-19",quiet:false)
check(repeated.1==nil,"restart no repeat")
let failed=Engine.update(s,counts:["101":.unavailable,"102":.value(21)],now:3100,day:"2026-11-19",quiet:false)
check(failed.0.rows["101"]?.count==12 && failed.0.rows["101"]?.online==false,"offline preserve")
check(failed.0.attemptedAt==3100 && failed.0.observedAt(ids:["101","102"])==2000,"offline age stays at successful observation")
let scoped=Engine.update(s,counts:["101":.value(12)],now:3200,day:"2026-11-19",quiet:true)
check(scoped.0.total==12 && scoped.0.rows.count==1 && scoped.0.rows["101"]?.baseline==10,"scope preserve")
let down=Engine.update(scoped.0,counts:["101":.value(11)],now:4000,day:"2026-11-19",quiet:true)
let back=Engine.update(down.0,counts:["101":.value(12)],now:5000,day:"2026-11-19",quiet:false)
check(back.1==nil,"quiet never lowers highwater")
let gap=Engine.update(back.0,counts:["101":.value(15)],now:500000,day:"2026-11-22",quiet:true)
check(gap.0.rows["101"]?.partialDay==true && gap.0.rows["101"]?.delta==0,"multi day gap")
let rolled=Engine.update(back.0,counts:["101":.value(13)],now:90000,day:"2026-11-20",quiet:true)
check(rolled.0.rows["101"]?.partialDay==false && rolled.0.rows["101"]?.delta==1,"day rollover")
let waiting=Engine.update(grown.0,counts:["101":.value(13),"102":.value(21)],now:2100,day:"2026-11-19",quiet:false)
check(waiting.1==nil,"cooldown")
let later=Engine.update(waiting.0,counts:["101":.value(13),"102":.value(21)],now:3000,day:"2026-11-19",quiet:false)
check(later.1?.gain==1,"pending delta after cooldown")
let unknown=Engine.update(WidgetState(),counts:["101":.unavailable],now:1000,day:"2026-11-19",quiet:false)
check(unknown.0.total==nil,"unknown not zero")
let payload=Data("{\"response\":[{\"id\":101,\"type\":\"instagram_new\",\"short_name\":\"example.creator\",\"name\":\"Example\"}],\"after\":null}".utf8)
let page=try APIParsing.accounts(payload)
check(page.accounts.count==1 && page.accounts[0].id=="101" && page.accounts[0].platform=="instagram","anonymous accounts fixture")
check(try APIParsing.followers(Data("{\"response\":{\"followers\":123}}".utf8))==123,"count fixture")
check(try APIParsing.followers(Data("{\"response\":{\"followers\":null}}".utf8))==nil,"null metric")
check(try APIParsing.followers(Data("{\"response\":{\"followers\":true}}".utf8))==nil,"bool rejected")
check(try APIParsing.followers(Data("{\"response\":{\"followers\":-1}}".utf8))==nil,"negative rejected")
check(!APIClient.validID("../outside") && APIClient.validID("account_101"),"path IDs validated")
let req=try APIClient.request(path:"/accounts",query:[],token:"fixture")
check(req.httpMethod=="GET" && req.url?.host=="api.livedune.com" && req.url?.scheme=="https","pinned read-only request")
let roundTrip=try JSONDecoder().decode(WidgetState.self,from:JSONEncoder().encode(s))
check(roundTrip.rows["101"]?.notifiedHigh==12,"durable highwater")
final class FixtureProtocol:URLProtocol {
    static var pages=[Data("{\"response\":[{\"id\":201,\"type\":\"telegram\",\"short_name\":\"sample.one\"}],\"after\":123}".utf8),Data("{\"response\":[{\"id\":202,\"type\":\"youtube\",\"short_name\":\"sample.two\"}],\"after\":null}".utf8)]
    override class func canInit(with request:URLRequest)->Bool {true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading() {
        let data=Self.pages.removeFirst()
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[FixtureProtocol.self]
let fixtureClient=APIClient(configuration:config),done=DispatchSemaphore(value:0)
var paginationOK=false
Task.detached {
    do {let (accounts,calls)=try await fixtureClient.accounts(token:"fixture");paginationOK=accounts.count==2 && calls==2}
    catch {paginationOK=false}
    done.signal()
}
check(done.wait(timeout:.now()+5) == .success && paginationOK,"follows small page cursor until nil")
print("PASS \(checks) anonymous fixture checks")
