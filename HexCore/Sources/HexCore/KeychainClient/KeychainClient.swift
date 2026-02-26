import Dependencies
import DependenciesMacros
import Foundation

/// A client for securely storing and retrieving sensitive data (like API keys) in the macOS Keychain.
@DependencyClient
public struct KeychainClient: Sendable {
	/// Save a value to the keychain.
	///
	/// - Parameters:
	///   - key: The key to store the value under
	///   - value: The string value to store
	public var save: @Sendable (_ key: String, _ value: String) async throws -> Void

	/// Load a value from the keychain.
	///
	/// - Parameter key: The key to retrieve
	/// - Returns: The stored value, or nil if not found
	public var load: @Sendable (_ key: String) async -> String?

	/// Delete a value from the keychain.
	///
	/// - Parameter key: The key to delete
	public var delete: @Sendable (_ key: String) async throws -> Void
}

extension DependencyValues {
	/// Access the keychain client dependency.
	public var keychain: KeychainClient {
		get { self[KeychainClient.self] }
		set { self[KeychainClient.self] = newValue }
	}
}

public enum KeychainError: Error, LocalizedError {
	case saveFailed(OSStatus)
	case deleteFailed(OSStatus)

	public var errorDescription: String? {
		switch self {
		case let .saveFailed(status):
			return "Failed to save to keychain: \(status)"
		case let .deleteFailed(status):
			return "Failed to delete from keychain: \(status)"
		}
	}
}
