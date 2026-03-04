//
//  RecordingClient.swift
//  Hex
//
//  Created by Kit Langton on 1/24/25.
//

import AppKit // For NSEvent media key simulation
import AVFoundation
import ComposableArchitecture
import CoreAudio
import Dependencies
import DependenciesMacros
import Foundation
import HexCore

private let recordingLogger = HexLog.recording
private let mediaLogger = HexLog.media

/// Represents an audio input device
struct AudioInputDevice: Identifiable, Equatable {
  var id: String
  var name: String
}

@DependencyClient
struct RecordingClient {
  var startRecording: @Sendable () async -> Void = {}
  var stopRecording: @Sendable () async -> URL = { URL(fileURLWithPath: "") }
  var requestMicrophoneAccess: @Sendable () async -> Bool = { false }
  var observeAudioLevel: @Sendable () async -> AsyncStream<Meter> = { AsyncStream { _ in } }
  var getAvailableInputDevices: @Sendable () async -> [AudioInputDevice] = { [] }
  var getDefaultInputDeviceName: @Sendable () async -> String? = { nil }
  var warmUpRecorder: @Sendable () async -> Void = {}
  var cleanup: @Sendable () async -> Void = {}
}

extension RecordingClient: DependencyKey {
  static var liveValue: Self {
    let live = RecordingClientLive()
    return Self(
      startRecording: { await live.startRecording() },
      stopRecording: { await live.stopRecording() },
      requestMicrophoneAccess: { await live.requestMicrophoneAccess() },
      observeAudioLevel: { await live.observeAudioLevel() },
      getAvailableInputDevices: { await live.getAvailableInputDevices() },
      getDefaultInputDeviceName: { await live.getDefaultInputDeviceName() },
      warmUpRecorder: { await live.warmUpRecorder() },
      cleanup: { await live.cleanup() }
    )
  }
}

/// Simple structure representing audio metering values.
struct Meter: Equatable {
  let averagePower: Double
  let peakPower: Double
}

func isAudioPlayingOnDefaultOutput() async -> Bool {
  // Use Core Audio to check if the default output device has active audio.
  var deviceID = AudioDeviceID(0)
  var size = UInt32(MemoryLayout<AudioDeviceID>.size)
  var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )

  var status = AudioObjectGetPropertyData(
    AudioObjectID(kAudioObjectSystemObject),
    &address,
    0,
    nil,
    &size,
    &deviceID
  )

  guard status == noErr else {
    mediaLogger.error("Failed to get default output device: \(status)")
    return false
  }

  var isRunning: UInt32 = 0
  size = UInt32(MemoryLayout<UInt32>.size)
  address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere

  status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &isRunning)
  guard status == noErr else {
    mediaLogger.error("Failed to check audio running state: \(status)")
    return false
  }

  return isRunning != 0
}

/// Check if an application is installed by looking for its bundle
private func isAppInstalled(bundleID: String) -> Bool {
  let workspace = NSWorkspace.shared
  return workspace.urlForApplication(withBundleIdentifier: bundleID) != nil
}

/// Cached list of installed media players (computed once at first access)
private let installedMediaPlayers: [String: String] = {
  var result: [String: String] = [:]

  if isAppInstalled(bundleID: "com.apple.Music") {
    result["Music"] = "com.apple.Music"
  }

  if isAppInstalled(bundleID: "com.apple.iTunes") {
    result["iTunes"] = "com.apple.iTunes"
  }

  if isAppInstalled(bundleID: "com.spotify.client") {
    result["Spotify"] = "com.spotify.client"
  }

  if isAppInstalled(bundleID: "org.videolan.vlc") {
    result["VLC"] = "org.videolan.vlc"
  }

  return result
}()

// Backoff to avoid spamming AppleScript errors on systems without controllable players
private var mediaControlErrorCount = 0
private var mediaControlDisabled = false

struct MediaPauseResult {
  let pausedPlayers: [String]
  let knownPlayerRunning: Bool
}

func pauseAllMediaApplications() async -> MediaPauseResult {
  if mediaControlDisabled { return MediaPauseResult(pausedPlayers: [], knownPlayerRunning: false) }
  // Use cached list of installed media players
  if installedMediaPlayers.isEmpty {
    return MediaPauseResult(pausedPlayers: [], knownPlayerRunning: false)
  }

  mediaLogger.debug("Installed media players: \(installedMediaPlayers.keys.joined(separator: ", "))")

  // Create AppleScript that returns both paused players and running players.
  // This lets callers distinguish "no players running" (use media key fallback)
  // from "player running but already paused" (do nothing).
  var scriptParts: [String] = [
    "set pausedPlayers to {}",
    "set runningPlayers to {}"
  ]

  for (appName, _) in installedMediaPlayers {
    if appName == "VLC" {
      scriptParts.append("""
      try
        if application \"VLC\" is running then
          set end of runningPlayers to \"VLC\"
          tell application \"VLC\"
            if playing then
              pause
              set end of pausedPlayers to \"VLC\"
            end if
          end tell
        end if
      end try
      """)
    } else {
      scriptParts.append("""
      try
        if application \"\(appName)\" is running then
          set end of runningPlayers to \"\(appName)\"
          tell application \"\(appName)\"
            if player state is playing then
              pause
              set end of pausedPlayers to \"\(appName)\"
            end if
          end tell
        end if
      end try
      """)
    }
  }

  // Return a delimited string: "paused1,paused2|running1,running2"
  scriptParts.append("""
  set AppleScript's text item delimiters to ","
  set pausedStr to pausedPlayers as text
  set runningStr to runningPlayers as text
  set AppleScript's text item delimiters to ""
  return pausedStr & "|" & runningStr
  """)
  let script = scriptParts.joined(separator: "\n\n")
  
  let appleScript = NSAppleScript(source: script)
  var error: NSDictionary?
  guard let resultDescriptor = appleScript?.executeAndReturnError(&error) else {
    if let error = error {
      mediaLogger.error("Failed to pause media apps: \(error)")
      mediaControlErrorCount += 1
      if mediaControlErrorCount >= 3 { mediaControlDisabled = true }
    }
    return MediaPauseResult(pausedPlayers: [], knownPlayerRunning: false)
  }

  // Parse the "paused1,paused2|running1,running2" result string
  let resultString = resultDescriptor.stringValue ?? "|"
  let parts = resultString.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
  let pausedPlayers = parts[0].isEmpty ? [] : parts[0].split(separator: ",").map(String.init)
  let runningPlayers = parts.count > 1 && !parts[1].isEmpty
    ? parts[1].split(separator: ",").map(String.init)
    : []

  mediaLogger.notice("Paused media players: \(pausedPlayers.joined(separator: ", ")), running: \(runningPlayers.joined(separator: ", "))")

  return MediaPauseResult(pausedPlayers: pausedPlayers, knownPlayerRunning: !runningPlayers.isEmpty)
}

func resumeMediaApplications(_ players: [String]) async {
  guard !players.isEmpty else { return }

  // Only attempt to resume players that are installed
  let validPlayers = players.filter { installedMediaPlayers.keys.contains($0) }
  if validPlayers.isEmpty {
    return
  }
  
  // Create specific resume script for each player
  var scriptParts: [String] = []
  
  for player in validPlayers {
    if player == "VLC" {
      scriptParts.append("""
      try
        if application id \"org.videolan.vlc\" is running then
          tell application id \"org.videolan.vlc\" to play
        end if
      end try
      """)
    } else {
      scriptParts.append("""
      try
        if application \"\(player)\" is running then
          tell application \"\(player)\" to play
        end if
      end try
      """)
    }
  }
  
  let script = scriptParts.joined(separator: "\n\n")
  
  let appleScript = NSAppleScript(source: script)
  var error: NSDictionary?
  appleScript?.executeAndReturnError(&error)
  if let error = error {
    mediaLogger.error("Failed to resume media apps: \(error)")
  }
}

/// Simulates a media key press (the Play/Pause key) by posting a system-defined NSEvent.
/// This toggles the state of the active media app.
private func sendMediaKey() {
  let NX_KEYTYPE_PLAY: UInt32 = 16
  func postKeyEvent(down: Bool) {
    let flags: NSEvent.ModifierFlags = down ? .init(rawValue: 0xA00) : .init(rawValue: 0xB00)
    let data1 = Int((NX_KEYTYPE_PLAY << 16) | (down ? 0xA << 8 : 0xB << 8))
    if let event = NSEvent.otherEvent(with: .systemDefined,
                                      location: .zero,
                                      modifierFlags: flags,
                                      timestamp: 0,
                                      windowNumber: 0,
                                      context: nil,
                                      subtype: 8,
                                      data1: data1,
                                      data2: -1)
    {
      event.cgEvent?.post(tap: .cghidEventTap)
    }
  }
  postKeyEvent(down: true)
  postKeyEvent(down: false)
}

// MARK: - RecordingClientLive Implementation

actor RecordingClientLive {
  private var recorder: AVAudioRecorder?
  private let recordingURL = FileManager.default.temporaryDirectory.appendingPathComponent("recording.wav")
  private var isRecorderPrimedForNextSession = false
  private var lastPrimedDeviceID: AudioDeviceID?
  private var recordingSessionID: UUID?

  /// Outcome returned by start-time media control work (pause/mute).
  private struct MediaControlOutcome {
    var pausedPlayers: [String] = []
    var didPauseMedia: Bool = false
    var previousVolume: Float?
  }

  private var mediaControlTask: Task<MediaControlOutcome, Never>?
  private let recorderSettings: [String: Any] = [
    AVFormatIDKey: Int(kAudioFormatLinearPCM),
    AVSampleRateKey: 16000.0,
    AVNumberOfChannelsKey: 1,
    AVLinearPCMBitDepthKey: 32,
    AVLinearPCMIsFloatKey: true,
    AVLinearPCMIsBigEndianKey: false,
    AVLinearPCMIsNonInterleaved: false,
  ]
  private let (meterStream, meterContinuation) = AsyncStream<Meter>.makeStream()
  private var meterTask: Task<Void, Never>?

  @Shared(.hexSettings) var hexSettings: HexSettings

  /// Tracks whether media was paused using the media key when recording started.
  private var didPauseMedia: Bool = false

  /// Tracks which specific media players were paused
  private var pausedPlayers: [String] = []

  /// Tracks previous system volume when muted for recording
  private var previousVolume: Float?

  /// Bundles the info needed to resume media after recording.
  private struct PendingMediaResume {
    let task: Task<Void, Never>
    let players: [String]
    let didPauseMedia: Bool
    let previousVolume: Float?
  }

  /// The in-flight resume from the most recent stopRecording().
  /// Stored so startRecording() can cancel + inherit its payload.
  private var pendingResume: PendingMediaResume?

  /// Monotonic counter incremented on each startRecording().
  /// Resume Tasks capture the current value and bail if it changed,
  /// preventing stale side-effects from firing during a later session.
  private var mediaGeneration: UInt64 = 0

  // Cache to store already-processed device information
  private var deviceCache: [AudioDeviceID: (hasInput: Bool, name: String?)] = [:]
  private var lastDeviceCheck = Date(timeIntervalSince1970: 0)
  
  /// Gets all available input devices on the system
  func getAvailableInputDevices() async -> [AudioInputDevice] {
    // Reset cache if it's been more than 5 minutes since last full refresh
    let now = Date()
    if now.timeIntervalSince(lastDeviceCheck) > 300 {
      deviceCache.removeAll()
      lastDeviceCheck = now
    }
    
    // Get all available audio devices
    let devices = getAllAudioDevices()
    var inputDevices: [AudioInputDevice] = []
    
    // Filter to only input devices and convert to our model
    for device in devices {
      let hasInput: Bool
      let name: String?
      
      // Check cache first to avoid expensive Core Audio calls
      if let cached = deviceCache[device] {
        hasInput = cached.hasInput
        name = cached.name
      } else {
        hasInput = deviceHasInput(deviceID: device)
        name = hasInput ? getDeviceName(deviceID: device) : nil
        deviceCache[device] = (hasInput, name)
      }
      
      if hasInput, let deviceName = name {
        inputDevices.append(AudioInputDevice(id: String(device), name: deviceName))
      }
    }
    
    return inputDevices
  }

  /// Gets the current system default input device name
  func getDefaultInputDeviceName() async -> String? {
    guard let deviceID = getDefaultInputDevice() else { return nil }
    if let cached = deviceCache[deviceID], cached.hasInput, let name = cached.name {
      return name
    }
    let name = getDeviceName(deviceID: deviceID)
    if let name {
      deviceCache[deviceID] = (hasInput: true, name: name)
    }
    return name
  }
  
  // MARK: - Core Audio Helpers

  /// Creates an AudioObjectPropertyAddress with common defaults.
  private func audioPropertyAddress(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
  ) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: scope,
      mElement: element
    )
  }

  /// Get all available audio devices
  private func getAllAudioDevices() -> [AudioDeviceID] {
    var propertySize: UInt32 = 0
    var address = audioPropertyAddress(kAudioHardwarePropertyDevices)
    
    // Get the property data size
    var status = AudioObjectGetPropertyDataSize(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &propertySize
    )
    
    if status != 0 {
      recordingLogger.error("AudioObjectGetPropertyDataSize failed: \(status)")
      return []
    }
    
    // Calculate device count
    let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
    var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
    
    // Get the device IDs
    status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &propertySize,
      &deviceIDs
    )
    
      if status != 0 {
        recordingLogger.error("AudioObjectGetPropertyData failed while listing devices: \(status)")
        return []
      }
    
    return deviceIDs
  }
  
  /// Get device name for the given device ID
  private func getDeviceName(deviceID: AudioDeviceID) -> String? {
    var address = audioPropertyAddress(kAudioDevicePropertyDeviceNameCFString)
    
    var deviceName: CFString? = nil
    var size = UInt32(MemoryLayout<CFString?>.size)
    let deviceNamePtr: UnsafeMutableRawPointer = .allocate(byteCount: Int(size), alignment: MemoryLayout<CFString?>.alignment)
    defer { deviceNamePtr.deallocate() }
    
    let status = AudioObjectGetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      &size,
      deviceNamePtr
    )
    
    if status == 0 {
        deviceName = deviceNamePtr.load(as: CFString?.self)
    }
    
      if status != 0 {
        recordingLogger.error("Failed to fetch device name: \(status)")
        return nil
      }
    
    return deviceName as String?
  }
  
  /// Check if device has input capabilities
  private func deviceHasInput(deviceID: AudioDeviceID) -> Bool {
    var address = audioPropertyAddress(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeInput)
    
    var propertySize: UInt32 = 0
    let status = AudioObjectGetPropertyDataSize(
      deviceID,
      &address,
      0,
      nil,
      &propertySize
    )
    
    if status != 0 {
      return false
    }
    
    let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(propertySize))
    defer { bufferList.deallocate() }
    
    let getStatus = AudioObjectGetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      &propertySize,
      bufferList
    )
    
    if getStatus != 0 {
      return false
    }
    
    // Check if we have any input channels
    let buffersPointer = UnsafeMutableAudioBufferListPointer(bufferList)
    return buffersPointer.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
  }
  
  /// Set device as the default input device
  private func setInputDevice(deviceID: AudioDeviceID) {
    var device = deviceID
    let size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = audioPropertyAddress(kAudioHardwarePropertyDefaultInputDevice)
    
    let status = AudioObjectSetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      size,
      &device
    )
    
    if status != 0 {
      recordingLogger.error("Failed to set default input device: \(status)")
    } else {
      recordingLogger.notice("Selected input device set to \(deviceID)")
    }
  }

  func requestMicrophoneAccess() async -> Bool {
    await AVCaptureDevice.requestAccess(for: .audio)
  }

  // MARK: - Input Device Query

  /// Gets the current default input device ID
  private func getDefaultInputDevice() -> AudioDeviceID? {
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = audioPropertyAddress(kAudioHardwarePropertyDefaultInputDevice)

    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &deviceID
    )

    if status != 0 {
      recordingLogger.error("Failed to get default input device: \(status)")
      return nil
    }

    return deviceID
  }

  // MARK: - Input Device Mute Detection & Fix

  /// Checks if the input device is muted at the Core Audio device level
  private func isInputDeviceMuted(_ deviceID: AudioDeviceID) -> Bool {
    var address = audioPropertyAddress(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeInput)
    var muted: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)

    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
    if status != noErr {
      // Property not supported on this device
      return false
    }
    return muted == 1
  }

  /// Unmutes the input device at the Core Audio device level
  private func unmuteInputDevice(_ deviceID: AudioDeviceID) {
    var address = audioPropertyAddress(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeInput)
    var muted: UInt32 = 0
    let size = UInt32(MemoryLayout<UInt32>.size)

    let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &muted)
    if status == noErr {
      recordingLogger.warning("Input device \(deviceID) was muted at device level - automatically unmuted")
    } else {
      recordingLogger.error("Failed to unmute input device \(deviceID): \(status)")
    }
  }

  /// Checks and fixes muted input device before recording
  private func ensureInputDeviceUnmuted() {
    // Check the selected device if specified, otherwise the default
    var deviceIDsToCheck: [AudioDeviceID] = []

    if let selectedIDString = hexSettings.selectedMicrophoneID,
       let selectedID = AudioDeviceID(selectedIDString) {
      deviceIDsToCheck.append(selectedID)
    }

    if let defaultID = getDefaultInputDevice() {
      if !deviceIDsToCheck.contains(defaultID) {
        deviceIDsToCheck.append(defaultID)
      }
    }

    for deviceID in deviceIDsToCheck {
      if isInputDeviceMuted(deviceID) {
        recordingLogger.error("⚠️ Input device \(deviceID) is MUTED at Core Audio level! This causes silent recordings.")
        unmuteInputDevice(deviceID)
      }
    }
  }

  // MARK: - Volume Control

  /// Mutes system volume and returns the previous volume level
  private func muteSystemVolume() async -> Float {
    let currentVolume = getSystemVolume()
    setSystemVolume(0)
    recordingLogger.notice("Muted system volume (was \(String(format: "%.2f", currentVolume)))")
    return currentVolume
  }

  /// Restores system volume to the specified level
  private func restoreSystemVolume(_ volume: Float) async {
    setSystemVolume(volume)
    recordingLogger.notice("Restored system volume to \(String(format: "%.2f", volume))")
  }

  /// Gets the default output device ID
  private func getDefaultOutputDevice() -> AudioDeviceID? {
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = audioPropertyAddress(kAudioHardwarePropertyDefaultOutputDevice)

    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &deviceID
    )

    if status != 0 {
      recordingLogger.error("Failed to get default output device: \(status)")
      return nil
    }

    return deviceID
  }

  /// Gets the current system output volume (0.0 to 1.0)
  private func getSystemVolume() -> Float {
    guard let deviceID = getDefaultOutputDevice() else {
      return 0.0
    }

    var volume: Float32 = 0.0
    var size = UInt32(MemoryLayout<Float32>.size)
    var address = audioPropertyAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)

    let status = AudioObjectGetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      &size,
      &volume
    )

    if status != 0 {
      recordingLogger.error("Failed to get system volume: \(status)")
      return 0.0
    }

    return volume
  }

  /// Sets the system output volume (0.0 to 1.0)
  private func setSystemVolume(_ volume: Float) {
    guard let deviceID = getDefaultOutputDevice() else {
      return
    }

    var newVolume = volume
    let size = UInt32(MemoryLayout<Float32>.size)
    var address = audioPropertyAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)

    let status = AudioObjectSetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      size,
      &newVolume
    )

    if status != 0 {
      recordingLogger.error("Failed to set system volume: \(status)")
    }
  }

  func startRecording() async {
    // Check and fix device-level mute before recording
    ensureInputDeviceUnmuted()

    let sessionID = UUID()
    recordingSessionID = sessionID

    // Advance generation — invalidates any in-flight resume Task's guards.
    mediaGeneration &+= 1

    // If a previous session's resume is still pending, cancel it and
    // carry forward its payload. The media is still paused/muted from
    // that session; the new session must remember what to resume.
    let inherited = pendingResume
    pendingResume?.task.cancel()
    pendingResume = nil

    mediaControlTask?.cancel()
    mediaControlTask = nil

    // Carry forward ALL inherited state unconditionally before checking
    // the current mode. This handles cross-mode switches (e.g. prior session
    // used .pauseMedia, current uses .mute) — the final stop will restore
    // everything.
    if let inherited {
      if !inherited.players.isEmpty { pausedPlayers = inherited.players }
      if inherited.didPauseMedia { didPauseMedia = true }
      if inherited.previousVolume != nil && previousVolume == nil {
        previousVolume = inherited.previousVolume
      }
    }

    // Handle audio behavior based on user preference
    switch hexSettings.recordingAudioBehavior {
    case .pauseMedia:
      // Pause media in background - don't block recording from starting
      mediaControlTask = Task { [sessionID] in
        guard await self.isCurrentSession(sessionID) else { return MediaControlOutcome() }

        // 1. Try AppleScript — targets specific known media players.
        let result = await pauseAllMediaApplications()
        var outcome = MediaControlOutcome(pausedPlayers: result.pausedPlayers)

        // Merge with inherited players (set union). If AppleScript found nothing
        // new to pause (player already paused from prior session), inherited
        // state is preserved. If it found new players, both sets are kept.
        await self.mergePausedPlayers(result.pausedPlayers, sessionID: sessionID)

        // Session may have changed while AppleScript was running. Return what
        // already happened so stopRecording can still carry this forward.
        guard await self.isCurrentSession(sessionID) else { return outcome }

        if !result.pausedPlayers.isEmpty {
          mediaLogger.notice("Paused media players via AppleScript")
          return outcome
        }

        // A known player is running but already paused — nothing to do.
        // Crucially, do NOT fall through to the media key toggle, which
        // would START playback.
        if result.knownPlayerRunning {
          mediaLogger.notice("Known media player running but not playing; skipping media key")
          return outcome
        }

        // 2. No known player running — try the media key for browser-based
        //    or other audio sources. Only send if audio is actually playing
        //    on the output device.
        // Skip if we already have inherited or current pause state.
        if await self.hasActiveOrInheritedPauseState() { return outcome }

        if await isAudioPlayingOnDefaultOutput() {
          mediaLogger.notice("No known player running; detected audio on output; sending media key")
          await MainActor.run {
            sendMediaKey()
          }
          await self.setDidPauseMedia(true, sessionID: sessionID)
          outcome.didPauseMedia = true
        }

        return outcome
      }

    case .mute:
      if previousVolume != nil {
        // Volume already inherited from cancelled resume — system is already muted.
        // Keep the original pre-mute volume for correct restoration.
        mediaLogger.notice("Volume already muted from prior session; carrying forward")
      } else {
        // Mute system volume in background
        mediaControlTask = Task { [sessionID] in
          guard await self.isCurrentSession(sessionID) else { return MediaControlOutcome() }
          let volume = await self.muteSystemVolume()
          await self.setPreviousVolume(volume, sessionID: sessionID)
          return MediaControlOutcome(previousVolume: volume)
        }
      }

    case .doNothing:
      // No audio handling
      break
    }

    // Determine target input device (custom selection or system default)
    let targetDeviceID: AudioDeviceID? = {
      if let selectedDeviceIDString = hexSettings.selectedMicrophoneID,
         let selectedDeviceID = AudioDeviceID(selectedDeviceIDString) {
        // Verify the selected device is still available
        let devices = getAllAudioDevices()
        if devices.contains(selectedDeviceID) && deviceHasInput(deviceID: selectedDeviceID) {
          return selectedDeviceID
        } else {
          recordingLogger.notice("Selected device \(selectedDeviceID) missing; using system default")
          return nil
        }
      }
      return nil  // Use system default
    }()

    // Get current default input device
    let currentDefaultDevice = getDefaultInputDevice()
    if let primedDevice = lastPrimedDeviceID, primedDevice != currentDefaultDevice {
      recordingLogger.notice("Default input changed from \(primedDevice) to \(currentDefaultDevice ?? 0); invalidating primed state")
      invalidatePrimedState()
    }

    // Only change device if target differs from current default
    if let target = targetDeviceID {
      if target != currentDefaultDevice {
        recordingLogger.notice("Switching input device from \(currentDefaultDevice ?? 0) to \(target)")
        setInputDevice(deviceID: target)
        // Invalidate primed state since device changed - recorder was prepared for old device
        invalidatePrimedState()
      } else {
        recordingLogger.debug("Device \(target) already set as default, skipping setInputDevice()")
      }
    } else {
      recordingLogger.debug("Using system default microphone")
    }

    do {
      let recorder = try ensureRecorderReadyForRecording()
      guard recorder.record() else {
        recordingLogger.error("AVAudioRecorder refused to start recording")
        endRecordingSession()
        return
      }
      startMeterTask()
      recordingLogger.notice("Recording started")
    } catch {
      recordingLogger.error("Failed to start recording: \(error.localizedDescription)")
      endRecordingSession()
    }
  }

  func stopRecording() async -> URL {
    let wasRecording = recorder?.isRecording == true
    recorder?.stop()
    stopMeterTask()

    // Export immediately so this stop call returns a stable URL even if
    // a new recording session starts while we await media work.
    var exportedURL = recordingURL
    var didCopyRecording = false
    do {
      exportedURL = try duplicateCurrentRecording()
      didCopyRecording = true
    } catch {
      isRecorderPrimedForNextSession = false
      recordingLogger.error("Failed to copy recording: \(error.localizedDescription)")
    }

    // Capture the session we're stopping and detach the media task reference
    // so a concurrent startRecording won't have its NEW task cancelled by
    // this stop flow when it ends.
    let stoppingSessionID = recordingSessionID
    let mediaTask = mediaControlTask
    mediaControlTask = nil

    // Await the in-flight media control task (pause/mute) so we can merge
    // its actual outcome even if state writes were blocked by session guards.
    let mediaOutcome: MediaControlOutcome
    if let mediaTask {
      mediaOutcome = await mediaTask.value
    } else {
      mediaOutcome = MediaControlOutcome()
    }

    // If a new session started during the await (actor reentrancy), don't
    // clobber it. Carry forward what we learned so the newer session can
    // resume correctly when it ends.
    guard recordingSessionID == stoppingSessionID else {
      recordingLogger.notice("stopRecording preempted by new session; carrying media outcome forward")
      mergeMediaOutcomeIntoState(mediaOutcome)
      return exportedURL
    }

    endRecordingSession()
    if wasRecording {
      recordingLogger.notice("Recording stopped")
    } else {
      recordingLogger.notice("stopRecording() called while recorder was idle")
    }

    if didCopyRecording {
      do {
        try primeRecorderForNextSession()
      } catch {
        isRecorderPrimedForNextSession = false
        recordingLogger.error("Failed to prime recorder: \(error.localizedDescription)")
      }
    }

    // Resume audio in background - don't block stop from completing
    var playersToResume = pausedPlayers
    if !mediaOutcome.pausedPlayers.isEmpty {
      playersToResume = Array(Set(playersToResume).union(mediaOutcome.pausedPlayers))
    }
    let shouldResumeMedia = didPauseMedia || mediaOutcome.didPauseMedia
    let volumeToRestore = previousVolume ?? mediaOutcome.previousVolume
    clearMediaState()

    if !playersToResume.isEmpty || shouldResumeMedia || volumeToRestore != nil {
      // Cancel any existing pending resume before creating a new one.
      // This prevents orphaned tasks if stopRecording() is called
      // multiple times without an intervening start (e.g. handleCancel).
      pendingResume?.task.cancel()

      let generation = mediaGeneration
      let task = Task {
        // Generation guard: bail if a new session started since we were spawned.
        guard await self.isCurrentGeneration(generation) else { return }

        // Volume and player resume are independent — handles cross-mode
        // carry-forward where both may be set from different sessions.
        if let volume = volumeToRestore {
          await self.restoreSystemVolume(volume)
        }

        guard await self.isCurrentGeneration(generation) else { return }

        if !playersToResume.isEmpty {
          mediaLogger.notice("Resuming players: \(playersToResume.joined(separator: ", "))")
          await resumeMediaApplications(playersToResume)
        } else if shouldResumeMedia {
          // Media key is mutually exclusive with AppleScript player resume.
          // Only send when no known players were involved (avoids double-toggle).
          await MainActor.run {
            sendMediaKey()
          }
          mediaLogger.notice("Resuming media via media key")
        }

        await self.clearPendingResumeIfCurrent(generation)
      }
      pendingResume = PendingMediaResume(
        task: task,
        players: playersToResume,
        didPauseMedia: shouldResumeMedia,
        previousVolume: volumeToRestore
      )
    }
    // else: no payload to resume. Leave existing pendingResume alone —
    // it may still need to complete (e.g. handleCancel called stop while idle).

    return exportedURL
  }

  // Actor state update helpers
  private func isCurrentSession(_ sessionID: UUID) -> Bool {
    recordingSessionID == sessionID
  }

  private func endRecordingSession() {
    recordingSessionID = nil
    mediaControlTask?.cancel()
    mediaControlTask = nil
  }

  private func invalidatePrimedState() {
    isRecorderPrimedForNextSession = false
    lastPrimedDeviceID = nil
  }

  private func updatePausedPlayers(_ players: [String], sessionID: UUID) {
    guard recordingSessionID == sessionID else { return }
    pausedPlayers = players
  }

  private func setDidPauseMedia(_ value: Bool, sessionID: UUID) {
    guard recordingSessionID == sessionID else { return }
    didPauseMedia = value
  }

  private func setPreviousVolume(_ volume: Float, sessionID: UUID) {
    guard recordingSessionID == sessionID else { return }
    previousVolume = volume
  }

  private func clearMediaState() {
    pausedPlayers = []
    didPauseMedia = false
    previousVolume = nil
  }

  private func mergeMediaOutcomeIntoState(_ outcome: MediaControlOutcome) {
    if !outcome.pausedPlayers.isEmpty {
      pausedPlayers = Array(Set(pausedPlayers).union(outcome.pausedPlayers))
    }
    if outcome.didPauseMedia {
      didPauseMedia = true
    }
    if previousVolume == nil, let volume = outcome.previousVolume {
      previousVolume = volume
    }
  }

  private func isCurrentGeneration(_ generation: UInt64) -> Bool {
    mediaGeneration == generation
  }

  private func clearPendingResumeIfCurrent(_ generation: UInt64) {
    guard mediaGeneration == generation else { return }
    pendingResume = nil
  }

  /// Merges newly paused players with any inherited paused players (set union).
  /// A prior session may have paused Spotify while this session's check also
  /// paused Music — both need to be resumed when this session ends.
  private func mergePausedPlayers(_ newPlayers: [String], sessionID: UUID) {
    guard recordingSessionID == sessionID else { return }
    if newPlayers.isEmpty { return }
    let merged = Array(Set(pausedPlayers).union(newPlayers))
    pausedPlayers = merged
  }

  /// True if the current session has any active or inherited pause state.
  /// Used to suppress the media-key fallback when prior state already covers resume.
  private func hasActiveOrInheritedPauseState() -> Bool {
    !pausedPlayers.isEmpty || didPauseMedia
  }

  private enum RecorderPreparationError: Error {
    case failedToPrepareRecorder
    case missingRecordingOnDisk
  }

  private func ensureRecorderReadyForRecording() throws -> AVAudioRecorder {
    let recorder = try recorderOrCreate()

    if !isRecorderPrimedForNextSession {
      recordingLogger.notice("Recorder NOT primed, calling prepareToRecord() now")
      guard recorder.prepareToRecord() else {
        throw RecorderPreparationError.failedToPrepareRecorder
      }
    } else {
      recordingLogger.notice("Recorder already primed, skipping prepareToRecord()")
    }

    isRecorderPrimedForNextSession = false
    return recorder
  }

  private func recorderOrCreate() throws -> AVAudioRecorder {
    if let recorder {
      return recorder
    }

    let recorder = try AVAudioRecorder(url: recordingURL, settings: recorderSettings)
    recorder.isMeteringEnabled = true
    self.recorder = recorder
    return recorder
  }

  private func duplicateCurrentRecording() throws -> URL {
    let fm = FileManager.default

    guard fm.fileExists(atPath: recordingURL.path) else {
      throw RecorderPreparationError.missingRecordingOnDisk
    }

    let exportURL = recordingURL
      .deletingLastPathComponent()
      .appendingPathComponent("hex-recording-\(UUID().uuidString).wav")

    if fm.fileExists(atPath: exportURL.path) {
      try fm.removeItem(at: exportURL)
    }

    try fm.copyItem(at: recordingURL, to: exportURL)
    return exportURL
  }

  private func primeRecorderForNextSession() throws {
    let recorder = try recorderOrCreate()
    guard recorder.prepareToRecord() else {
      isRecorderPrimedForNextSession = false
      lastPrimedDeviceID = nil
      throw RecorderPreparationError.failedToPrepareRecorder
    }

    isRecorderPrimedForNextSession = true
    lastPrimedDeviceID = getDefaultInputDevice()
    recordingLogger.debug("Recorder primed for device \(self.lastPrimedDeviceID ?? 0)")
  }

  func startMeterTask() {
    meterTask = Task {
      while !Task.isCancelled, let r = self.recorder, r.isRecording {
        r.updateMeters()
        let averagePower = r.averagePower(forChannel: 0)
        let averageNormalized = pow(10, averagePower / 20.0)
        let peakPower = r.peakPower(forChannel: 0)
        let peakNormalized = pow(10, peakPower / 20.0)
        meterContinuation.yield(Meter(averagePower: Double(averageNormalized), peakPower: Double(peakNormalized)))
        try? await Task.sleep(for: .milliseconds(100))
      }
    }
  }

  func stopMeterTask() {
    meterTask?.cancel()
    meterTask = nil
  }

  func observeAudioLevel() -> AsyncStream<Meter> {
    meterStream
  }

  func warmUpRecorder() async {
    do {
      try primeRecorderForNextSession()
    } catch {
      recordingLogger.error("Failed to warm up recorder: \(error.localizedDescription)")
    }
  }

  /// Release recorder resources. Call on app termination.
  func cleanup() {
    endRecordingSession()
    pendingResume?.task.cancel()
    pendingResume = nil
    if let recorder = recorder {
      if recorder.isRecording {
        recorder.stop()
      }
      self.recorder = nil
    }
    isRecorderPrimedForNextSession = false
    lastPrimedDeviceID = nil
    recordingLogger.notice("RecordingClient cleaned up")
  }
}

extension DependencyValues {
  var recording: RecordingClient {
    get { self[RecordingClient.self] }
    set { self[RecordingClient.self] = newValue }
  }
}
