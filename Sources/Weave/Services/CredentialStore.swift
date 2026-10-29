import Foundation
import Security
import WeaveCore

/// 연결한 계좌의 키 보관소. 테스트는 메모리 보관소로 바꿔 끼운다.
protocol CredentialStoring: Sendable {
    /// 없으면 nil. 잠김·접근 거부·손상은 오류로 구분한다 — "키 없음"으로 보이면 연결을 지우게 된다.
    func tossCredentials(for sourceID: UUID) throws -> TossCredentials?
    func save(_ credentials: TossCredentials, for sourceID: UUID) throws
    func delete(for sourceID: UUID)
}

enum CredentialStoreError: Error {
    case keychain(OSStatus)
}

/// macOS 키체인(이 Mac 전용). portfolio.json과 백업 파일엔 키가 들어가지 않는다.
struct KeychainCredentialStore: CredentialStoring {
    static let service = "app.weave.linked-source"

    func tossCredentials(for sourceID: UUID) throws -> TossCredentials? {
        var query = baseQuery(sourceID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw CredentialStoreError.keychain(status)
        }
        return try JSONDecoder().decode(TossCredentials.self, from: data)
    }

    func save(_ credentials: TossCredentials, for sourceID: UUID) throws {
        let data = try JSONEncoder().encode(credentials)
        let status = SecItemUpdate(
            baseQuery(sourceID) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw CredentialStoreError.keychain(status) }

        var item = baseQuery(sourceID)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrLabel as String] = "Weave linked account"
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw CredentialStoreError.keychain(added) }
    }

    func delete(for sourceID: UUID) {
        SecItemDelete(baseQuery(sourceID) as CFDictionary)
    }

    private func baseQuery(_ sourceID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: sourceID.uuidString
        ]
    }
}
