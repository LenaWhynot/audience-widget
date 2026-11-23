import Foundation
import CoreFoundation

enum APIError:Error {
    case denied,quota,unavailable,invalidData,invalidRequest,tooManyAccounts
    var message:String {
        switch self {
        case .denied:return "Проверьте ключ и доступ к API в вашем тарифе LiveDune."
        case .quota:return "Лимит запросов LiveDune исчерпан. Обновления приостановлены."
        case .invalidData:return "LiveDune вернул неподдерживаемый ответ. Последние данные сохранены."
        case .invalidRequest:return "Некорректные параметры подключения."
        case .tooManyAccounts:return "В кабинете больше2000аккаунтов. Эта версия рассчитана на меньший кабинет."
        case .unavailable:return "Нет связи с LiveDune. Последние данные сохранены."
        }
    }
}
struct AccountPage {let accounts:[SocialAccount];let after:String?}
enum APIParsing {
    static func integer(_ value:Any?)->Int? {
        guard let n=value as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),n.doubleValue.isFinite,n.doubleValue>=0,n.doubleValue.rounded()==n.doubleValue,n.doubleValue<=1_000_000_000_000 else{return nil}
        return n.intValue
    }
    static func object(_ data:Data)throws->[String:Any] {
        guard data.count<=5_000_000,let root=try JSONSerialization.jsonObject(with:data) as? [String:Any] else{throw APIError.invalidData};return root
    }
    static func accounts(_ data:Data)throws->AccountPage {
        let root=try object(data);guard let list=root["response"] as? [[String:Any]] else{throw APIError.invalidData}
        let values=list.compactMap { row -> SocialAccount? in
            let id=(row["id"] as? String) ?? integer(row["id"]).map(String.init)
            guard let id=id,APIClient.validID(id),let type=row["type"] as? String else{return nil}
            let handle=(row["short_name"] as? String) ?? (row["name"] as? String) ?? id
            return SocialAccount(id:id,platform:type.hasPrefix("instagram") ? "instagram" : type.hasPrefix("vk") ? "vk" : type,handle:String(handle.prefix(160)),name:String(((row["name"] as? String) ?? handle).prefix(160)))
        }
        let after=(root["after"] as? String) ?? integer(root["after"]).map(String.init)
        return AccountPage(accounts:values,after:after=="0" ? nil : after)
    }
    static func followers(_ data:Data)throws->Int? {
        let root=try object(data);guard let values=root["response"] as? [String:Any] else{throw APIError.invalidData};return integer(values["followers"])
    }
    static func quota(_ data:Data)throws->Int {
        let root=try object(data)
        guard let total=root["total"] as? [String:Any],let left=integer(total["left"]) else{throw APIError.invalidData};return left
    }
}
final class APIClient:NSObject,URLSessionTaskDelegate {
    private let suppliedConfiguration:URLSessionConfiguration?
    init(configuration:URLSessionConfiguration?=nil) {suppliedConfiguration=configuration;super.init()}
    lazy var session:URLSession = {
        let c=suppliedConfiguration ?? URLSessionConfiguration.ephemeral
        c.httpCookieStorage=nil;c.httpShouldSetCookies=false;c.urlCredentialStorage=nil;c.urlCache=nil
        c.timeoutIntervalForRequest=20;c.timeoutIntervalForResource=30
        return URLSession(configuration:c,delegate:self,delegateQueue:nil)
    }()
    static func validID(_ id:String)->Bool { id.range(of:"^[A-Za-z0-9_-]{1,128}$",options:.regularExpression) != nil }
    static func request(path:String,query:[URLQueryItem],token:String)throws->URLRequest {
        guard path=="/accounts" || path=="/info" || path.range(of:"^/accounts/[A-Za-z0-9_-]{1,128}/analytics$",options:.regularExpression) != nil,
              !token.isEmpty,token.count<=4096,!token.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}) else{throw APIError.invalidRequest}
        var c=URLComponents();c.scheme="https";c.host="api.livedune.com";c.path=path
        c.queryItems=query+[URLQueryItem(name:"access_token",value:token)]
        guard let url=c.url else{throw APIError.invalidRequest}
        var r=URLRequest(url:url,cachePolicy:.reloadIgnoringLocalAndRemoteCacheData,timeoutInterval:20)
        r.httpMethod="GET";r.setValue("application/json",forHTTPHeaderField:"Accept");r.setValue("curl/8.7.1",forHTTPHeaderField:"User-Agent")
        return r
    }
    func data(path:String,query:[URLQueryItem]=[],token:String)async throws->Data {
        #if QA
        throw APIError.invalidRequest
        #else
        let request=try Self.request(path:path,query:query,token:token)
        do {
            let (data,response)=try await session.data(for:request)
            guard let http=response as? HTTPURLResponse else{throw APIError.invalidData}
            switch http.statusCode {
            case 200..<300:return data
            case 401,403:throw APIError.denied
            case 429:throw APIError.quota
            default:throw APIError.unavailable
            }
        } catch let e as APIError {throw e} catch {throw APIError.unavailable}
        #endif
    }
    func accounts(token:String)async throws->([SocialAccount],Int) {
        var result:[SocialAccount]=[],after:String?,seen=Set<String>(),calls=0
        for _ in 0..<20 {
            let q=after.map{[URLQueryItem(name:"after",value:$0)]} ?? []
            let p=try APIParsing.accounts(await data(path:"/accounts",query:q,token:token));calls+=1
            result+=p.accounts
            if p.after==nil {return(Array(Dictionary(result.map{($0.id,$0)},uniquingKeysWith:{$1}).values).sorted{$0.handle<$1.handle},calls)}
            guard let cursor=p.after,!seen.contains(cursor) else{throw APIError.invalidData};seen.insert(cursor);after=cursor
        }
        throw APIError.tooManyAccounts
    }
    func quota(token:String)async throws->Int {try APIParsing.quota(await data(path:"/info",token:token))}
    func followers(account:SocialAccount,token:String)async throws->Int? {
        guard Self.validID(account.id) else{throw APIError.invalidRequest}
        let f=DateFormatter();f.dateFormat="yyyy-MM-dd";f.locale=Locale(identifier:"en_US_POSIX");f.timeZone=TimeZone(secondsFromGMT:0)
        let day=f.string(from:Date())
        return try APIParsing.followers(await data(path:"/accounts/\(account.id)/analytics",query:[URLQueryItem(name:"date_from",value:day),URLQueryItem(name:"date_to",value:day)],token:token))
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void) {
        completionHandler(request.url?.scheme=="https" && request.url?.host=="api.livedune.com" && request.httpMethod=="GET" ? request : nil)
    }
}
