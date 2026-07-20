//
//  OpenAIClient.swift
//  Hex
//

import Dependencies
import DependenciesMacros
import Foundation
import HexCore

private let logger = HexLog.ai

extension AIProviderType {
	/// Keychain entry holding this provider's API key. Each provider keeps its own key.
	var apiKeyName: String {
		switch self {
		case .openai: return "openai-api-key"
		case .openaiCompatible: return "openai-compatible-api-key"
		}
	}
}

/// A client for transforming text using OpenAI's Responses API or any
/// OpenAI-compatible Chat Completions endpoint (e.g. Cerebras).
@DependencyClient
struct OpenAIClient: Sendable {
	/// Transform text using a custom prompt.
	///
	/// - Parameters:
	///   - text: The transcribed text to transform
	///   - customPrompt: The transformation prompt
	///   - provider: Which backend to call
	///   - baseURL: Base URL for the OpenAI-compatible provider (ignored for OpenAI)
	///   - modelName: The model to use (e.g., "gpt-5.6-luna", "gpt-oss-120b")
	///   - maxOutputTokens: Maximum tokens for the response
	/// - Returns: The transformed text
	var transformText: @Sendable (_ text: String, _ customPrompt: String, _ provider: AIProviderType, _ baseURL: String, _ modelName: String, _ maxOutputTokens: Int) async throws -> String

	/// Check if the given provider's API key is configured.
	var isConfigured: @Sendable (_ provider: AIProviderType) async -> Bool = { _ in false }
}

extension OpenAIClient: DependencyKey {
	static var liveValue: Self {
		let live = OpenAIClientLive()
		return Self(
			transformText: { try await live.transformText($0, customPrompt: $1, provider: $2, baseURL: $3, modelName: $4, maxOutputTokens: $5) },
			isConfigured: { await live.isConfigured($0) }
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
	case invalidBaseURL
	case invalidResponse
	case apiError(statusCode: Int, message: String?)
	case parsingFailed

	var errorDescription: String? {
		switch self {
		case .apiKeyNotConfigured:
			return "AI provider API key not configured"
		case .invalidBaseURL:
			return "AI provider base URL is missing or invalid"
		case .invalidResponse:
			return "Invalid response from AI provider"
		case let .apiError(code, message):
			if let message {
				return "AI provider error (\(code)): \(message)"
			}
			return "AI provider error (status \(code))"
		case .parsingFailed:
			return "Failed to parse AI provider response"
		}
	}
}

// MARK: - Live Implementation

actor OpenAIClientLive {
	@Dependency(\.keychain) var keychain

	func isConfigured(_ provider: AIProviderType) async -> Bool {
		await keychain.load(provider.apiKeyName) != nil
	}

	func transformText(_ text: String, customPrompt: String, provider: AIProviderType, baseURL: String, modelName: String, maxOutputTokens: Int) async throws -> String {
		guard let apiKey = await keychain.load(provider.apiKeyName) else {
			throw OpenAIError.apiKeyNotConfigured
		}

		let instructions = """
		Transform the following text according to these instructions:
		\(customPrompt)

		Only output the transformed text, nothing else.
		"""
		let userInput = "Rewrite the following text:\n\n\(text)"

		logger.info("Transforming text with \(provider.rawValue, privacy: .public) (model: \(modelName, privacy: .public))")

		let url: URL
		let body: [String: Any]
		switch provider {
		case .openai:
			url = URL(string: "https://api.openai.com/v1/responses")!
			body = [
				"model": modelName,
				"instructions": instructions,
				"input": userInput,
				"reasoning": ["effort": "low"],
				"max_output_tokens": maxOutputTokens
			]
		case .openaiCompatible:
			let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
			let root = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
			guard !root.isEmpty,
			      let endpoint = URL(string: root + "/chat/completions"),
			      endpoint.scheme != nil, endpoint.host != nil
			else {
				throw OpenAIError.invalidBaseURL
			}
			url = endpoint
			body = [
				"model": modelName,
				"messages": [
					["role": "system", "content": instructions],
					["role": "user", "content": userInput]
				],
				"max_completion_tokens": maxOutputTokens
			]
		}

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try JSONSerialization.data(withJSONObject: body)

		let (data, response) = try await URLSession.shared.data(for: request)

		guard let httpResponse = response as? HTTPURLResponse else {
			throw OpenAIError.invalidResponse
		}

		guard httpResponse.statusCode == 200 else {
			// Try to extract error message from response
			var errorMessage: String?
			if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			   let error = json["error"] as? [String: Any],
			   let message = error["message"] as? String
			{
				errorMessage = message
			}
			logger.error("AI provider error: status \(httpResponse.statusCode), message: \(errorMessage ?? "unknown", privacy: .public)")
			throw OpenAIError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
		}

		switch provider {
		case .openai:
			return try parseResponsesAPIOutput(data)
		case .openaiCompatible:
			return try parseChatCompletionsOutput(data)
		}
	}

	/// Parse the Responses API response.
	private func parseResponsesAPIOutput(_ data: Data) throws -> String {
		guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			throw OpenAIError.parsingFailed
		}

		// The Responses API returns output in a different format
		// Look for output_text in the response
		if let outputText = json["output_text"] as? String {
			let result = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
			logger.info("Successfully transformed text (\(result.count) chars)")
			return result
		}

		// Alternative: check for output array with items
		if let output = json["output"] as? [[String: Any]] {
			for item in output {
				if item["type"] as? String == "message",
				   let content = item["content"] as? [[String: Any]]
				{
					for contentItem in content {
						if contentItem["type"] as? String == "output_text",
						   let text = contentItem["text"] as? String
						{
							let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
							logger.info("Successfully transformed text (\(result.count) chars)")
							return result
						}
					}
				}
			}
		}

		logger.error("Failed to parse Responses API response: \(String(data: data, encoding: .utf8) ?? "nil", privacy: .private)")
		throw OpenAIError.parsingFailed
	}

	/// Parse a Chat Completions response (OpenAI-compatible providers).
	private func parseChatCompletionsOutput(_ data: Data) throws -> String {
		guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			throw OpenAIError.parsingFailed
		}

		if let choices = json["choices"] as? [[String: Any]],
		   let message = choices.first?["message"] as? [String: Any],
		   let content = message["content"] as? String
		{
			let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
			logger.info("Successfully transformed text (\(result.count) chars)")
			return result
		}

		logger.error("Failed to parse Chat Completions response: \(String(data: data, encoding: .utf8) ?? "nil", privacy: .private)")
		throw OpenAIError.parsingFailed
	}

}
