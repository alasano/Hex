import Foundation

/// A curated model offered in the AI Transforms model picker, with the
/// reasoning effort values its API accepts.
public struct AIModelPreset: Equatable, Sendable {
	public let id: String
	public let displayName: String
	public let reasoningEfforts: [String]
	/// Effort the API applies when the request omits it.
	public let defaultReasoningEffort: String
}

extension AIProviderType {
	/// Curated models for this provider. Any other model ID can still be entered as a custom model.
	public var modelPresets: [AIModelPreset] {
		switch self {
		case .openai:
			// https://developers.openai.com/api/docs/models/gpt-6-luna
			return [
				AIModelPreset(
					id: "gpt-6-luna",
					displayName: "GPT-6 Luna",
					reasoningEfforts: ["none", "low", "medium", "high", "xhigh", "max"],
					defaultReasoningEffort: "medium"
				)
			]
		case .openaiCompatible:
			// Cerebras public endpoints: https://inference-docs.cerebras.ai/capabilities/reasoning
			return [
				AIModelPreset(
					id: "qwen-3.8-27b",
					displayName: "Qwen 3.8 27B (Cerebras)",
					reasoningEfforts: ["none", "low", "medium", "high"],
					defaultReasoningEffort: "high"
				),
				AIModelPreset(
					id: "gpt-oss-120b",
					displayName: "GPT OSS 120B (Cerebras)",
					reasoningEfforts: ["low", "medium", "high"],
					defaultReasoningEffort: "medium"
				)
			]
		}
	}

	public func modelPreset(id: String) -> AIModelPreset? {
		modelPresets.first { $0.id == id }
	}
}
