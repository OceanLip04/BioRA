import Foundation
import Security
import XCTest
@testable import PersonalMac

private final class FakeKeychainAccess: KeychainAccess {
    var queries: [[String: Any]] = []
    var readStatus = errSecItemNotFound
    var updateStatus = errSecItemNotFound
    var addStatus = errSecSuccess
    var deleteStatus = errSecSuccess
    var data: Data?
    var updates: [[String: Any]] = []
    var added = 0
    func read(_ query: [String: Any]) -> (OSStatus, Data?) { queries.append(query); return (readStatus, data) }
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus { queries.append(query); updates.append(attributes); return updateStatus }
    func add(_ attributes: [String: Any]) -> OSStatus { queries.append(attributes); added += 1; return addStatus }
    func delete(_ query: [String: Any]) -> OSStatus { queries.append(query); return deleteStatus }
}

final class AssistantKeychainTests: XCTestCase {
    func testAllOperationsUseLoginKeychainWithoutRestrictedAttributes() throws {
        let access = FakeKeychainAccess(); let keychain = AssistantKeychain(access: access)
        XCTAssertNil(try keychain.read(account: "synthetic-account"))
        try keychain.save("synthetic-test-value", account: "synthetic-account")
        try keychain.delete(account: "synthetic-account")
        XCTAssertEqual(access.queries.count, 4)
        for query in access.queries {
            XCTAssertNil(query[kSecUseDataProtectionKeychain as String])
            XCTAssertNil(query[kSecAttrAccessGroup as String])
            XCTAssertNil(query[kSecAttrAccessible as String])
            XCTAssertNil(query[kSecAttrSynchronizable as String])
            XCTAssertEqual(query[kSecAttrService as String] as? String, "com.labmonitor.personal.assistant")
            XCTAssertEqual(query[kSecAttrAccount as String] as? String, "synthetic-account")
        }
        XCTAssertEqual(access.queries[2][kSecValueData as String] as? Data, Data("synthetic-test-value".utf8))
    }
    func testExistingKeyUpdatesWithoutAddingOrDeleting() throws {
        let access = FakeKeychainAccess(); access.updateStatus = errSecSuccess
        try AssistantKeychain(access: access).save("synthetic-replacement", account: "account")
        XCTAssertEqual(access.queries.count, 1); XCTAssertEqual(access.added, 0)
        XCTAssertEqual(access.updates[0][kSecValueData as String] as? Data, Data("synthetic-replacement".utf8))
    }
    func testFailureDoesNotFallBackToAnotherStoreOrExposeKey() throws {
        let access = FakeKeychainAccess(); access.updateStatus = errSecMissingEntitlement
        XCTAssertThrowsError(try AssistantKeychain(access: access).save("synthetic-private-value", account: "account")) { error in
            XCTAssertTrue(error.localizedDescription.contains("-34018"))
            XCTAssertTrue(error.localizedDescription.contains("签名"))
            XCTAssertFalse(error.localizedDescription.contains("synthetic-private-value"))
        }
        XCTAssertEqual(access.queries.count, 1); XCTAssertEqual(access.added, 0)
    }
    func testReadDecodeAndMissingDelete() throws {
        let access = FakeKeychainAccess(); access.readStatus = errSecSuccess; access.data = Data("synthetic-test-value".utf8)
        let keychain = AssistantKeychain(access: access)
        XCTAssertEqual(try keychain.read(account: "account"), "synthetic-test-value")
        access.data = Data([0xff]); XCTAssertThrowsError(try keychain.read(account: "account"))
        access.deleteStatus = errSecItemNotFound; XCTAssertNoThrow(try keychain.delete(account: "account"))
    }
    func testCancelledAddIsReportedWithoutFurtherWrites() throws {
        let access = FakeKeychainAccess(); access.addStatus = errSecUserCanceled
        XCTAssertThrowsError(try AssistantKeychain(access: access).save("synthetic-test-value", account: "account")) { error in XCTAssertTrue(error.localizedDescription.contains("取消")) }
        XCTAssertEqual(access.queries.count, 2)
    }
}
