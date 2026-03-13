//
//  OpenAIClient.swift
//  Hex
//

import Dependencies
import DependenciesMacros
import Foundation
import HexCore

private let logger = HexLog.ai

/// A client for transforming text using an OpenAI-compatible API.
@DependencyClient
struct OpenAIClient: Sendable {
	/// Transform text using a custom prompt.
	///
	/// - Parameters:
	///   - text: The transcribed text to transform
	///   - customPrompt: The transformation prompt
	///   - modelName: The model to use (e.g., "gpt-5-nano", "gemma3:4b")
	///   - maxOutputTokens: Maximum tokens for the response
	///   - baseURL: The API base URL (e.g., "https://api.openai.com" or "http://localhost:11434")
	/// - Returns: The transformed text
	var transformText: @Sendable (_ text: String, _ customPrompt: String, _ modelName: String, _ maxOutputTokens: Int, _ baseURL: String) async throws -> String

	/// Check if the API is ready to use.
	/// For remote APIs, checks that an API key is configured.
	/// For local APIs (localhost), always returns true.
	var isConfigured: @Sendable (_ baseURL: String) async -> Bool = { _ in false }
}

extension OpenAIClient: DependencyKey {
	static var liveValue: Self {
		let live = OpenAIClientLive()
		return Self(
			transformText: { try await live.transformText($0, customPrompt: $1, modelName: $2, maxOutputTokens: $3, baseURL: $4) },
			isConfigured: { await live.isConfigured(baseURL: $0) }
		)
	}
}

extension DependencyValues {
	var openAI: OpenAIClient {
		get { self[OpenAIClient.self] }
		set { self[OpenAIClient.self] = newValue }
	}
}

// MARK: - Errors

enum OpenAIError: Error, LocalizedError {
	case apiKeyNotConfigured
	case invalidURL(String)
	case invalidResponse
	case apiError(statusCode: Int, message: String?)
	case parsingFailed

	var errorDescription: String? {
		switch self {
		case .apiKeyNotConfigured:
			return "API key not configured"
		case let .invalidURL(url):
			return "Invalid API base URL: \(url)"
		case .invalidResponse:
			return "Invalid response from API"
		case let .apiError(code, message):
			if let message {
				return "API error (\(code)): \(message)"
			}
			return "API error (status \(code))"
		case .parsingFailed:
			return "Failed to parse API response"
		}
	}
}

// MARK: - Live Implementation

actor OpenAIClientLive {
	@Dependency(\.keychain) var keychain

	private let apiKeyName = "openai-api-key"

	/// Returns true if the base URL points to a local server.
	private static func isLocalURL(_ baseURL: String) -> Bool {
		guard let url = URL(string: baseURL), let host = url.host else { return false }
		return host == "localhost" || host == "127.0.0.1" || host == "0.0.0.0" || host == "::1"
	}

	func isConfigured(baseURL: String) async -> Bool {
		if Self.isLocalURL(baseURL) {
			return true
		}
		return await keychain.load(apiKeyName) != nil
	}

	func transformText(_ text: String, customPrompt: String, modelName: String, maxOutputTokens: Int, baseURL: String) async throws -> String {
		let isLocal = Self.isLocalURL(baseURL)
		var apiKey: String? = nil

		if !isLocal {
			guard let key = await keychain.load(apiKeyName) else {
				throw OpenAIError.apiKeyNotConfigured
			}
			apiKey = key
		} else {
			// Local servers may still accept a key (optional)
			apiKey = await keychain.load(apiKeyName)
		}

		let systemPrompt = """
		Transform the following text according to these instructions:
		\(customPrompt)

		Only output the transformed text, nothing else.
		"""

		logger.info("Transforming text with AI (model: \(modelName, privacy: .public), base: \(baseURL, privacy: .public))")

		// Use /v1/chat/completions — supported by OpenAI, Ollama, LM Studio, and others
		guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
			throw OpenAIError.invalidURL(baseURL)
		}

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		if let apiKey {
			request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
		}
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")

		let body: [String: Any] = [
			"model": modelName,
			"messages": [
				["role": "system", "content": systemPrompt],
				["role": "user", "content": text]
			],
			"max_tokens": maxOutputTokens
		]

		request.httpBody = try JSONSerialization.data(withJSONObject: body)

		let (data, response) = try await URLSession.shared.data(for: request)

		guard let httpResponse = response as? HTTPURLResponse else {
			throw OpenAIError.invalidResponse
		}

		guard httpResponse.statusCode == 200 else {
			var errorMessage: String?
			if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			   let error = json["error"] as? [String: Any],
			   let message = error["message"] as? String
			{
				errorMessage = message
			}
			logger.error("API error: status \(httpResponse.statusCode), message: \(errorMessage ?? "unknown", privacy: .public)")
			throw OpenAIError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
		}

		// Parse chat completions response
		guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let choices = json["choices"] as? [[String: Any]],
		      let firstChoice = choices.first,
		      let message = firstChoice["message"] as? [String: Any],
		      let content = message["content"] as? String
		else {
			logger.error("Failed to parse API response: \(String(data: data, encoding: .utf8) ?? "nil", privacy: .private)")
			throw OpenAIError.parsingFailed
		}

		let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
		logger.info("Successfully transformed text (\(result.count) chars)")
		return result
	}
}
