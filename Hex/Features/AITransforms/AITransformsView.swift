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
					Text("Transform transcriptions using AI before pasting. Assign a separate hotkey to trigger AI-enhanced transcription.")
						.font(.callout)
						.foregroundStyle(.secondary)
				}

				// AI Transform Hotkey Section
				GroupBox {
					VStack(spacing: 12) {
						let aiHotKey = store.hexSettings.aiTransformHotkey
						let key = store.isSettingAITransformHotkey ? nil : aiHotKey?.key
						let modifiers = store.isSettingAITransformHotkey
							? store.currentAITransformModifiers
							: (aiHotKey?.modifiers ?? .init(modifiers: []))

						HStack {
							Spacer()
							HotKeyView(modifiers: modifiers, key: key, isActive: store.isSettingAITransformHotkey)
								.animation(.spring(), value: key)
								.animation(.spring(), value: modifiers)
							Spacer()
						}
						.contentShape(Rectangle())
						.onTapGesture {
							store.send(.startSettingAITransformHotkey)
						}

						if !store.isSettingAITransformHotkey, let aiHotKey,
						   aiHotKey.key == nil, !aiHotKey.modifiers.isEmpty {
							ModifierSideControls(
								modifiers: aiHotKey.modifiers,
								onSelect: { kind, side in
									store.send(.setAITransformModifierSide(kind, side))
								}
							)
							.transition(.opacity)
						}

						if store.hexSettings.aiTransformHotkey != nil {
							Button("Clear Hotkey") {
								store.send(.clearAITransformHotkey)
							}
							.foregroundStyle(.secondary)
							.font(.caption)
						}
					}
					.padding(.vertical, 4)
				} label: {
					VStack(alignment: .leading, spacing: 4) {
						Text("AI Transform Hotkey")
							.font(.headline)
						Text("Use this hotkey instead of your main shortcut to apply AI transformation to the transcription.")
							.settingsCaption()
					}
				}

				// Custom Prompt Section
				GroupBox {
					VStack(alignment: .leading, spacing: 12) {
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
								.disabled(!store.isAIProviderConfigured)
								.opacity(store.isAIProviderConfigured ? 1 : 0.5)

							Text("Example: \"Make it sound like Samuel L. Jackson\" or \"Add enthusiasm and energy\"")
								.settingsCaption()
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
						// Provider Row
						HStack {
							Image(systemName: "server.rack")
								.foregroundStyle(.secondary)
							Text("Provider")
							Spacer()
							Picker("Provider", selection: $store.hexSettings.aiProviderType) {
								Text("OpenAI").tag(AIProviderType.openai)
								Text("OpenAI-compatible").tag(AIProviderType.openaiCompatible)
							}
							.labelsHidden()
							.frame(width: 180)
						}

						if store.hexSettings.aiProviderType == .openaiCompatible {
							Divider()

							// Base URL Row
							HStack {
								Image(systemName: "link")
									.foregroundStyle(.secondary)
								Text("Base URL")
								Spacer()
								TextField("https://api.cerebras.ai/v1", text: $store.hexSettings.aiCompatibleBaseURL)
									.textFieldStyle(.roundedBorder)
									.frame(width: 240)
							}
						}

						Divider()

						// API Key Row
						HStack {
							Image(systemName: "key.fill")
								.foregroundStyle(.secondary)
							Text(store.hexSettings.aiProviderType == .openai ? "OpenAI API Key" : "API Key")
							Spacer()
							if store.isAIProviderConfigured {
								Image(systemName: "checkmark.circle.fill")
									.foregroundColor(.green)
								Text("Configured")
									.foregroundStyle(.secondary)
							} else {
								Text("Not Set")
									.foregroundStyle(.secondary)
							}
							Button(store.isAIProviderConfigured ? "Change" : "Configure") {
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
							if store.hexSettings.aiProviderType == .openai {
								TextField("gpt-5.6-luna", text: $store.hexSettings.aiModelName)
									.textFieldStyle(.roundedBorder)
									.frame(width: 180)
							} else {
								TextField("gpt-oss-120b", text: $store.hexSettings.aiCompatibleModelName)
									.textFieldStyle(.roundedBorder)
									.frame(width: 180)
							}
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
						Text("Each provider keeps its own API key and model. Keys are stored securely in the macOS Keychain.")
							.settingsCaption()
					}
				}

				if !store.isAIProviderConfigured {
					HStack(spacing: 8) {
						Image(systemName: "exclamationmark.triangle.fill")
							.foregroundStyle(.orange)
						Text("An API key is required to use AI Transforms. Configure your key above to enable these features.")
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
				provider: store.hexSettings.aiProviderType,
				isConfigured: store.isAIProviderConfigured,
				onSave: { key in
					store.send(.saveAIAPIKey(key))
				},
				onDelete: {
					store.send(.deleteAIAPIKey)
				}
			)
		}
		.task {
			await store.send(.task).finish()
		}
		.task {
			await store.send(.checkAIAPIKey).finish()
		}
		.onChange(of: store.hexSettings.aiProviderType) {
			store.send(.checkAIAPIKey)
		}
		.enableInjection()
	}
}

// MARK: - API Key Configuration Sheet

private struct APIKeyConfigSheet: View {
	@Environment(\.dismiss) var dismiss
	@Binding var apiKeyInput: String
	let provider: AIProviderType
	let isConfigured: Bool
	var onSave: (String) -> Void
	var onDelete: () -> Void

	var body: some View {
		VStack(spacing: 20) {
			Text(provider == .openai ? "OpenAI API Key" : "API Key")
				.font(.headline)

			Text(provider == .openai
				? "Your API key is stored securely in the macOS Keychain and is only sent to OpenAI's servers."
				: "Your API key is stored securely in the macOS Keychain and is only sent to the provider at your configured base URL.")
				.font(.caption)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)

			SecureField(provider == .openai ? "sk-..." : "csk-...", text: $apiKeyInput)
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
