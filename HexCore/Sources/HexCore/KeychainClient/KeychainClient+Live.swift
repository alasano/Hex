import Dependencies
import Foundation
import Security

private let logger = HexLog.settings

extension KeychainClient: DependencyKey {
	public static var liveValue: Self {
		Self(
			save: { key, value in
				try await KeychainClientLive.save(key: key, value: value)
			},
			load: { key in
				await KeychainClientLive.load(key: key)
			},
			delete: { key in
				try await KeychainClientLive.delete(key: key)
			}
		)
	}
}

private enum KeychainClientLive {
	private static let serviceName = "com.alasano.Hex"

	static func save(key: String, value: String) async throws {
		logger.debug("Saving to keychain: \(key, privacy: .public)")

		guard let data = value.data(using: .utf8) else {
			throw KeychainError.saveFailed(errSecParam)
		}

		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: serviceName,
			kSecAttrAccount as String: key,
			kSecValueData as String: data
		]

		// Delete any existing item first
		SecItemDelete(query as CFDictionary)

		let status = SecItemAdd(query as CFDictionary, nil)
		guard status == errSecSuccess else {
			logger.error("Failed to save to keychain: \(status)")
			throw KeychainError.saveFailed(status)
		}

		logger.info("Successfully saved to keychain: \(key, privacy: .public)")
	}

	static func load(key: String) async -> String? {
		logger.debug("Loading from keychain: \(key, privacy: .public)")

		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: serviceName,
			kSecAttrAccount as String: key,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne
		]

		var result: AnyObject?
		let status = SecItemCopyMatching(query as CFDictionary, &result)

		guard status == errSecSuccess,
		      let data = result as? Data,
		      let string = String(data: data, encoding: .utf8)
		else {
			if status != errSecItemNotFound {
				logger.warning("Keychain load failed with status: \(status)")
			}
			return nil
		}

		logger.debug("Successfully loaded from keychain: \(key, privacy: .public)")
		return string
	}

	static func delete(key: String) async throws {
		logger.debug("Deleting from keychain: \(key, privacy: .public)")

		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: serviceName,
			kSecAttrAccount as String: key
		]

		let status = SecItemDelete(query as CFDictionary)
		guard status == errSecSuccess || status == errSecItemNotFound else {
			logger.error("Failed to delete from keychain: \(status)")
			throw KeychainError.deleteFailed(status)
		}

		logger.info("Successfully deleted from keychain: \(key, privacy: .public)")
	}
}
