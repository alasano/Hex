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

	private var isLocalURL: Bool {
		let url = store.hexSettings.aiBaseURL
		guard let parsed = URL(string: url), let host = parsed.host else { return false }
		return host == "localhost" || host == "127.0.0.1" || host == "0.0.0.0" || host == "::1"
	}

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
								.disabled(!store.isOpenAIConfigured)
								.opacity(store.isOpenAIConfigured ? 1 : 0.5)

							Text("Example: \"Add proper punctuation\" or \"Fix grammar and add punctuation marks\"")
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
						// Base URL Row
						HStack {
							Image(systemName: "network")
								.foregroundStyle(.secondary)
							Text("API Base URL")
							Spacer()
							TextField("https://api.openai.com", text: $store.hexSettings.aiBaseURL)
								.textFieldStyle(.roundedBorder)
								.frame(width: 260)
								.onChange(of: store.hexSettings.aiBaseURL) {
									store.send(.checkOpenAIAPIKey)
								}
						}

						if isLocalURL {
							HStack(spacing: 6) {
								Image(systemName: "house.fill")
									.foregroundStyle(.green)
								Text("Local server detected — no API key required.")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
						}

						Divider()

						// API Key Row
						HStack {
							Image(systemName: "key.fill")
								.foregroundStyle(.secondary)
							Text("API Key")
							Spacer()
							if store.isOpenAIConfigured || isLocalURL {
								Image(systemName: "checkmark.circle.fill")
									.foregroundColor(.green)
								Text(isLocalURL ? "Optional" : "Configured")
									.foregroundStyle(.secondary)
							} else {
								Text("Not Set")
									.foregroundStyle(.secondary)
							}
							Button(store.isOpenAIConfigured && !isLocalURL ? "Change" : "Configure") {
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
							TextField(isLocalURL ? "gemma3:4b" : "gpt-5-nano", text: $store.hexSettings.aiModelName)
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
						Text("Works with OpenAI, Ollama (localhost:11434), LM Studio, or any OpenAI-compatible API.")
							.settingsCaption()
					}
				}

				if !store.isOpenAIConfigured {
					HStack(spacing: 8) {
						Image(systemName: "exclamationmark.triangle.fill")
							.foregroundStyle(.orange)
						Text("Configure an API key above, or point the base URL to a local server like Ollama.")
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
				isLocal: isLocalURL,
				onSave: { key in
					store.send(.saveOpenAIAPIKey(key))
				},
				onDelete: {
					store.send(.deleteOpenAIAPIKey)
				}
			)
		}
		.task {
			await store.send(.task).finish()
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
	let isLocal: Bool
	var onSave: (String) -> Void
	var onDelete: () -> Void

	var body: some View {
		VStack(spacing: 20) {
			Text("API Key")
				.font(.headline)

			Text(isLocal
				? "API key is optional for local servers. Leave empty if your server doesn't require authentication."
				: "Your API key is stored securely in the macOS Keychain and is only sent to the configured API server.")
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
