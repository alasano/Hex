//
//  AITransformsView.swift
//  Hex
//

import ComposableArchitecture
import HexCore
import Inject
import SwiftUI

struct AITransformsView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>
	@State private var apiKeyInput: String = ""
	@State private var showingAPIKeySheet: Bool = false

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				VStack(alignment: .leading, spacing: 6) {
					Text("AI Transforms")
						.font(.title2.bold())
					Text("Transform transcriptions using AI before pasting. Requires an OpenAI API key.")
						.font(.callout)
						.foregroundStyle(.secondary)
				}

					// Custom Prompt Section
				GroupBox {
					VStack(alignment: .leading, spacing: 12) {
						Toggle("Enable Custom Prompt", isOn: $store.hexSettings.aiTransformEnabled)
							.toggleStyle(.checkbox)
							.disabled(!store.isOpenAIConfigured)

						if store.hexSettings.aiTransformEnabled {
							VStack(alignment: .leading, spacing: 4) {
								Text("Transformation Prompt")
									.font(.caption.weight(.semibold))
									.foregroundStyle(.secondary)

								TextEditor(text: $store.hexSettings.aiTransformPrompt)
									.font(.body)
									.frame(minHeight: 80, maxHeight: 160)
									.scrollContentBackground(.hidden)
									.padding(8)
									.background(
										RoundedRectangle(cornerRadius: 6)
											.fill(Color(nsColor: .controlBackgroundColor))
									)
									.overlay(
										RoundedRectangle(cornerRadius: 6)
											.stroke(Color(nsColor: .separatorColor), lineWidth: 1)
									)

								Text("Example: \"Make it sound like Samuel L. Jackson\" or \"Add enthusiasm and energy\"")
									.settingsCaption()
							}
						}
					}
					.padding(.vertical, 4)
				} label: {
					VStack(alignment: .leading, spacing: 4) {
						Text("Custom Prompt")
							.font(.headline)
						Text("Apply any custom transformation to your transcriptions using a free-text prompt.")
							.settingsCaption()
					}
				}

					// API Configuration Section
				GroupBox {
					VStack(alignment: .leading, spacing: 12) {
						// API Key Row
						HStack {
							Image(systemName: "key.fill")
								.foregroundStyle(.secondary)
							Text("OpenAI API Key")
							Spacer()
							if store.isOpenAIConfigured {
								Image(systemName: "checkmark.circle.fill")
									.foregroundColor(.green)
								Text("Configured")
									.foregroundStyle(.secondary)
							} else {
								Text("Not Set")
									.foregroundStyle(.secondary)
							}
							Button(store.isOpenAIConfigured ? "Change" : "Configure") {
								showingAPIKeySheet = true
							}
						}

						Divider()

						// Model Name Row
						HStack {
							Image(systemName: "cpu")
								.foregroundStyle(.secondary)
							Text("Model")
							Spacer()
							TextField("gpt-5-nano", text: $store.hexSettings.aiModelName)
								.textFieldStyle(.roundedBorder)
								.frame(width: 180)
						}

						// Max Output Tokens Row
						HStack {
							Image(systemName: "number")
								.foregroundStyle(.secondary)
							Text("Max Output Tokens")
							Spacer()
							TextField("32768", value: $store.hexSettings.aiMaxOutputTokens, format: .number)
								.textFieldStyle(.roundedBorder)
								.frame(width: 100)
						}
					}
					.padding(.vertical, 4)
				} label: {
					VStack(alignment: .leading, spacing: 4) {
						Text("API Configuration")
							.font(.headline)
						Text("Your API key is stored securely in the macOS Keychain. Model defaults to gpt-5-nano.")
							.settingsCaption()
					}
				}

				if !store.isOpenAIConfigured {
					HStack(spacing: 8) {
						Image(systemName: "exclamationmark.triangle.fill")
							.foregroundStyle(.orange)
						Text("An OpenAI API key is required to use AI Transforms. Configure your key above to enable these features.")
							.font(.callout)
							.foregroundStyle(.secondary)
					}
					.padding(12)
					.background(
						RoundedRectangle(cornerRadius: 8)
							.fill(Color.orange.opacity(0.1))
					)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding()
		}
		.sheet(isPresented: $showingAPIKeySheet) {
			APIKeyConfigSheet(
				apiKeyInput: $apiKeyInput,
				isConfigured: store.isOpenAIConfigured,
				onSave: { key in
					store.send(.saveOpenAIAPIKey(key))
				},
				onDelete: {
					store.send(.deleteOpenAIAPIKey)
				}
			)
		}
		.task {
			await store.send(.checkOpenAIAPIKey).finish()
		}
		.enableInjection()
	}
}

// MARK: - API Key Configuration Sheet

private struct APIKeyConfigSheet: View {
	@Environment(\.dismiss) var dismiss
	@Binding var apiKeyInput: String
	let isConfigured: Bool
	var onSave: (String) -> Void
	var onDelete: () -> Void

	var body: some View {
		VStack(spacing: 20) {
			Text("OpenAI API Key")
				.font(.headline)

			Text("Your API key is stored securely in the macOS Keychain and is only sent to OpenAI's servers.")
				.font(.caption)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)

			SecureField("sk-...", text: $apiKeyInput)
				.textFieldStyle(.roundedBorder)
				.frame(width: 320)

			HStack(spacing: 12) {
				if isConfigured {
					Button("Delete Key", role: .destructive) {
						onDelete()
						apiKeyInput = ""
						dismiss()
					}
				}

				Button("Cancel") {
					apiKeyInput = ""
					dismiss()
				}
				.keyboardShortcut(.escape)

				Button("Save") {
					guard !apiKeyInput.isEmpty else { return }
					onSave(apiKeyInput)
					apiKeyInput = ""
					dismiss()
				}
				.keyboardShortcut(.return)
				.disabled(apiKeyInput.isEmpty)
			}
		}
		.padding(24)
		.frame(width: 400)
	}
}
