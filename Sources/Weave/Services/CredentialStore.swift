import Foundation
import Security
import WeaveCore

/// 연결 정보 보관소 — 증권사 키와 지갑 주소. 테스트는 메모리 보관소로 바꿔 끼운다.
protocol CredentialStoring: Sendable {
    /// 없으면 nil. 잠김·접근 거부는 오류로 구분한다 — "키 없음"으로 보이면 연결을 지우게 된다.
    func data(for sourceID: UUID) throws -> Data?
    func save(_ data: Data, for sourceID: UUID) throws
    func delete(for sourceID: UUID)
}

extension CredentialStoring {
    func tossCredentials(for sourceID: UUID) throws -> TossCredentials? {
        try data(for: sourceID).map { try JSONDecoder().decode(TossCredentials.self, from: $0) }
    }

    func save(_ credentials: TossCredentials, for sourceID: UUID) throws {
        try save(JSONEncoder().encode(credentials), for: sourceID)
    }

    func walletConfig(for sourceID: UUID) throws -> WalletConfig? {
        try data(for: sourceID).map { try JSONDecoder().decode(WalletConfig.self, from: $0) }
    }

    func save(_ config: WalletConfig, for sourceID: UUID) throws {
        try save(JSONEncoder().encode(config), for: sourceID)
    }
}

/// 앱이 켜져 있는 동안만 쥐는 보관소 — 시드 문서(WEAVE_STORE)로 띄운 데모·스크린샷이 실제 키체인을 건드리지 않게.
final class EphemeralCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [UUID: Data] = [:]

    func data(for sourceID: UUID) throws -> Data? { lock.withLock { items[sourceID] } }
    func save(_ data: Data, for sourceID: UUID) throws { lock.withLock { items[sourceID] = data } }
    func delete(for sourceID: UUID) { lock.withLock { items[sourceID] = nil } }
}

enum CredentialStoreError: Error {
    case keychain(OSStatus)
}

/// macOS 키체인(이 Mac 전용). portfolio.json과 백업 파일엔 들어가지 않는다.
///
/// 연결 전부를 키체인 항목 하나에 담는다. 키체인은 앱 서명이 바뀌면(개발 빌드는 빌드마다) 항목마다 허용 창을
/// 띄우는데, 항목이 하나면 한 번만 묻는다. 한 번 읽으면 앱이 켜져 있는 동안 메모리에 둔다.
final class KeychainCredentialStore: CredentialStoring, @unchecked Sendable {
    static let service = "app.weave.linked-source"
    private static let account = "links"

    private let lock = NSLock()
    private var cache: [UUID: Data]?

    func data(for sourceID: UUID) throws -> Data? {
        try lock.withLock {
            var all = try loadAll()
            if let data = all[sourceID] { return data }
            // 항목을 하나로 합치기 전 개발 빌드가 연결마다 따로 남긴 항목 — 찾으면 합쳐 둔다.
            guard let legacy = try Self.read(account: sourceID.uuidString) else { return nil }
            all[sourceID] = legacy
            try writeAll(all)
            return legacy
        }
    }

    func save(_ data: Data, for sourceID: UUID) throws {
        try lock.withLock {
            var all = try loadAll()
            all[sourceID] = data
            try writeAll(all)
        }
    }

    func delete(for sourceID: UUID) {
        lock.withLock {
            guard var all = try? loadAll(), all.removeValue(forKey: sourceID) != nil else { return }
            try? writeAll(all)
        }
    }

    private func loadAll() throws -> [UUID: Data] {
        if let cache { return cache }
        let stored = try Self.read(account: Self.account)
            .map { try JSONDecoder().decode([UUID: Data].self, from: $0) } ?? [:]
        cache = stored
        return stored
    }

    private func writeAll(_ all: [UUID: Data]) throws {
        try Self.write(JSONEncoder().encode(all), account: Self.account)
        cache = all
    }

    // MARK: - 키체인 항목

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func read(account: String) throws -> Data? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw CredentialStoreError.keychain(status)
        }
        return data
    }

    private static func write(_ data: Data, account: String) throws {
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw CredentialStoreError.keychain(status) }

        var item = query(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrLabel as String] = "Weave linked accounts"
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw CredentialStoreError.keychain(added) }
    }
}
