import Foundation
import Security
import LocalAuthentication

enum KeyStore {
    static var service:String {Bundle.main.bundleIdentifier ?? "app.audiencewidget.desktop.share"}
    static let account="livedune-token"
    static func load()->String? {
        #if QA
        return nil
        #else
        let context=LAContext();context.interactionNotAllowed=true
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account,kSecMatchLimit as String:kSecMatchLimitOne,kSecReturnData as String:true,kSecUseAuthenticationContext as String:context]
        var result:CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary,&result)==errSecSuccess,let data=result as? Data else{return nil}
        return String(data:data,encoding:.utf8)
        #endif
    }
    static func save(_ token:String)throws {
        #if QA
        throw APIError.invalidRequest
        #else
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account]
        let value:[String:Any]=[kSecValueData as String:Data(token.utf8)]
        let updated=SecItemUpdate(query as CFDictionary,value as CFDictionary)
        if updated==errSecItemNotFound {
            var item=query;item[kSecValueData as String]=Data(token.utf8)
            item[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            item[kSecAttrSynchronizable as String]=false
            item[kSecAttrLabel as String]="Audience Widget · LiveDune"
            guard SecItemAdd(item as CFDictionary,nil)==errSecSuccess else{throw APIError.invalidRequest}
        } else if updated != errSecSuccess {throw APIError.invalidRequest}
        #endif
    }
    static func delete()throws {
        #if QA
        return
        #else
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account]
        let status=SecItemDelete(query as CFDictionary)
        guard status==errSecSuccess || status==errSecItemNotFound else{throw APIError.invalidRequest}
        #endif
    }

}
