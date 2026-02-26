//
//  OpenAIClient.swift
//  Hex
//

import Dependencies
import DependenciesMacros
import Foundation
import HexCore

private let logger = HexLog.ai

/// A client for transforming text using OpenAI's Responses API.
@DependencyClient
struct OpenAIClient: Sendable {
	/// Transform text using a custom prompt.
	///
	/// - Parameters:
	///   - text: The transcribed text to transform
	///   - customPrompt: The transformation prompt
	///   - modelName: The OpenAI model to use (e.g., "gpt-5-nano")
	///   - maxOutputTokens: Maximum tokens for the response
	/// - Returns: The transformed text
	var transformText: @Sendable (_ text: String, _ customPrompt: String, _ modelName: String, _ maxOutputTokens: Int) async throws -> String

	/// Check if the OpenAI API key is configured.
	var isConfigured: @Sendable () async -> Bool = { false }
}

extension OpenAIClient: DependencyKey {
	static var liveValue: Self {
		let live = OpenAIClientLive()
		return Self(
			transformText: { try await live.transformText($0, customPrompt: $1, modelName: $2, maxOutputTokens: $3) },
			isConfigured: { await live.isConfigured() }
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
	case invalidResponse
	case apiError(statusCode: Int, message: String?)
	case parsingFailed

	var errorDescription: String? {
		switch self {
		case .apiKeyNotConfigured:
			return "OpenAI API key not configured"
		case .invalidResponse:
			return "Invalid response from OpenAI"
		case let .apiError(code, message):
			if let message {
				return "OpenAI API error (\(code)): \(message)"
			}
			return "OpenAI API error (status \(code))"
		case .parsingFailed:
			return "Failed to parse OpenAI response"
		}
	}
}

// MARK: - Live Implementation

actor OpenAIClientLive {
	@Dependency(\.keychain) var keychain

	private let apiKeyName = "openai-api-key"

	func isConfigured() async -> Bool {
		await keychain.load(apiKeyName) != nil
	}

	func transformText(_ text: String, customPrompt: String, modelName: String, maxOutputTokens: Int) async throws -> String {
		guard let apiKey = await keychain.load(apiKeyName) else {
			throw OpenAIError.apiKeyNotConfigured
		}

		let instructions = """
		Transform the following text according to these instructions:
		\(customPrompt)

		Only output the transformed text, nothing else.
		"""

		logger.info("Transforming text with OpenAI (model: \(modelName, privacy: .public))")

		let url = URL(string: "https://api.openai.com/v1/responses")!
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")

		let body: [String: Any] = [
			"model": modelName,
			"instructions": instructions,
			"input": "Rewrite the following text:\n\n\(text)",
			"max_output_tokens": maxOutputTokens
		]

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
			logger.error("OpenAI API error: status \(httpResponse.statusCode), message: \(errorMessage ?? "unknown", privacy: .public)")
			throw OpenAIError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
		}

		// Parse the Responses API response
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

		logger.error("Failed to parse OpenAI response: \(String(data: data, encoding: .utf8) ?? "nil", privacy: .private)")
		throw OpenAIError.parsingFailed
	}

}
