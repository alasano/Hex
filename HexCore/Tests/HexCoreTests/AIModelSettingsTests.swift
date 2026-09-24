import XCTest
@testable import HexCore

final class AIModelSettingsTests: XCTestCase {
	func testActivePropertiesFollowSelectedProvider() {
		var settings = HexSettings(aiProviderType: .openaiCompatible)
		settings.activeAIModelName = "qwen-3.8-27b"
		settings.activeAIReasoningEffort = "none"

		XCTAssertEqual(settings.aiCompatibleModelName, "qwen-3.8-27b")
		XCTAssertEqual(settings.aiCompatibleReasoningEffort, "none")
		XCTAssertEqual(settings.aiModelName, "gpt-6-luna")
		XCTAssertEqual(settings.aiReasoningEffort, "low")

		settings.aiProviderType = .openai
		XCTAssertEqual(settings.activeAIModelName, "gpt-6-luna")
		XCTAssertEqual(settings.activeAIReasoningEffort, "low")
	}

	func testSwitchingToPresetWithoutCurrentEffortResetsToDefault() {
		var settings = HexSettings(aiProviderType: .openaiCompatible, aiCompatibleModelName: "qwen-3.8-27b", aiCompatibleReasoningEffort: "none")
		settings.activeAIModelName = "gpt-oss-120b"
		XCTAssertEqual(settings.aiCompatibleReasoningEffort, "")
	}

	func testSwitchingToPresetKeepsSupportedEffort() {
		var settings = HexSettings(aiProviderType: .openaiCompatible, aiCompatibleModelName: "qwen-3.8-27b", aiCompatibleReasoningEffort: "low")
		settings.activeAIModelName = "gpt-oss-120b"
		XCTAssertEqual(settings.aiCompatibleReasoningEffort, "low")
	}

	func testCustomModelKeepsAnyEffort() {
		var settings = HexSettings(aiProviderType: .openai, aiReasoningEffort: "max")
		settings.activeAIModelName = "gpt-7-preview"
		XCTAssertEqual(settings.aiModelName, "gpt-7-preview")
		XCTAssertEqual(settings.aiReasoningEffort, "max")
	}

	func testReasoningEffortsRoundTrip() throws {
		let settings = HexSettings(aiReasoningEffort: "none", aiCompatibleReasoningEffort: "medium")
		let decoded = try JSONDecoder().decode(HexSettings.self, from: JSONEncoder().encode(settings))
		XCTAssertEqual(decoded.aiReasoningEffort, "none")
		XCTAssertEqual(decoded.aiCompatibleReasoningEffort, "medium")
	}
}
