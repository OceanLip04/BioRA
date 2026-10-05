import Foundation
import Security
import PersonalCore

protocol KeychainAccess {
    func read(_ query: [String: Any]) -> (OSStatus, Data?)
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func add(_ attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

private struct SystemKeychainAccess: KeychainAccess {
    func read(_ query: [String: Any]) -> (OSStatus, Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }
    func add(_ attributes: [String: Any]) -> OSStatus { SecItemAdd(attributes as CFDictionary, nil) }
    func delete(_ query: [String: Any]) -> OSStatus { SecItemDelete(query as CFDictionary) }
}

struct AssistantKeychain {
    private let service = "com.labmonitor.personal.assistant"
    private let access: any KeychainAccess
    init() { access = SystemKeychainAccess() }
    init(access: any KeychainAccess) { self.access = access }

    private func identity(_ account: String) -> [String: Any] {
        // Local builds are ad-hoc signed, without provisioned keychain access
        // groups. SecItem defaults to the macOS file-based login keychain.
        // Do not force the entitlement-dependent Data Protection keychain.
        // Keep the service/account identity; never fall back to a plain file.
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    func read(account: String) throws -> String? {
        var query = identity(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = access.read(query)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw failure("无法从钥匙串读取 API Key", status) }
        guard let data, let value = String(data: data, encoding: .utf8) else { throw failure("钥匙串条目无法解码", errSecDecode) }
        return value
    }
    func save(_ key: String, account: String) throws {
        var query = identity(account); let data = Data(key.utf8)
        let status = access.update(query, attributes: [kSecValueData as String: data])
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw failure("无法更新钥匙串", status) }
        query[kSecValueData as String] = data
        // kSecAttrAccessible is a Data Protection attribute, not a login-keychain
        // policy. The file-based keychain applies its own lock and access ACL.
        let added = access.add(query)
        guard added == errSecSuccess else { throw failure("无法保存 API Key 到钥匙串", added) }
    }
    func delete(account: String) throws {
        let status = access.delete(identity(account))
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure("无法移除钥匙串条目", status) }
    }
    private func failure(_ action: String, _ status: OSStatus) -> WorkspaceError {
        let hint: String
        switch status {
        case errSecMissingEntitlement: hint = "App 签名缺少所请求的钥匙串权限，请确认正在运行更新后的 App；无需授予完全磁盘访问。"
        case errSecUserCanceled: hint = "本次钥匙串授权已取消，已有 Key 未被删除。请重新尝试并处理 macOS 授权提示。"
        case errSecAuthFailed, errSecInteractionNotAllowed: hint = "请确认登录钥匙串已解锁，并由你本人处理 macOS 的授权提示。"
        default: hint = (SecCopyErrorMessageString(status, nil) as String?) ?? "请检查登录钥匙串状态。"
        }
        return .invalid("\(action)（\(status)）。\(hint)")
    }
}
