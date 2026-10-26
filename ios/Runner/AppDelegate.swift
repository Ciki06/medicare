import Flutter
import UIKit
import UserNotifications
import AVFoundation
import CryptoKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let deepLinkChannelName = "medicare/deeplinks"
  private var deepLinkChannel: FlutterMethodChannel?
  private var pendingInitialDeepLink: String?
  private var reminderWriters: [UUID: ReminderSoundWriter] = [:]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let audio = FlutterMethodChannel(name: "medicare/reminder_audio",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    audio.setMethodCallHandler { [weak self] call, result in
      if call.method == "cancelIncomingCall", let args = call.arguments as? [String: Any], let id = args["callId"] as? String {
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
          let ids = notifications.filter { ($0.request.content.userInfo["callId"] as? String) == id }.map { $0.request.identifier }
          UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
          DispatchQueue.main.async { result(nil) }
        }
        return
      }
      guard call.method == "sound", let args = call.arguments as? [String: Any],
            let speech = args["speech"] as? String, !speech.isEmpty else {
        result(FlutterMethodNotImplemented); return
      }
      let id = UUID()
      let writer = ReminderSoundWriter()
      self?.reminderWriters[id] = writer
      writer.write(speech) { name in
        DispatchQueue.main.async { result(name); self?.reminderWriters.removeValue(forKey: id) }
      }
    }

    let channel = FlutterMethodChannel(
      name: deepLinkChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "consumeInitialDeepLink" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let link = self?.pendingInitialDeepLink
      self?.pendingInitialDeepLink = nil
      result(link)
    }
    deepLinkChannel = channel
  }

  @discardableResult
  func receiveDeepLink(_ url: URL, initial: Bool) -> Bool {
    guard url.scheme?.lowercased() == "medicare",
          url.host?.lowercased() == "sos",
          url.path == "/trigger" else {
      return false
    }

    let link = url.absoluteString
    if initial || deepLinkChannel == nil {
      pendingInitialDeepLink = link
    } else {
      deepLinkChannel?.invokeMethod("onDeepLink", arguments: link)
    }
    return true
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    let handled = receiveDeepLink(url, initial: false)
    return super.application(app, open: url, options: options) || handled
  }
}

// Generate the complete spoken notification before scheduling it. iOS can play
// Library/Sounds files while the process is suspended; no timer/TTS at fire time.
private final class ReminderSoundWriter {
  private let synth = AVSpeechSynthesizer()
  private var output: AVAudioFile?
  private var completed = false
  func write(_ speech: String, completion: @escaping (String?) -> Void) {
    // Include the voice configuration version so existing cached audio is
    // regenerated after speech-rate/voice improvements.
    let digest = SHA256.hash(data: Data(("voice-v2:" + speech).utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    let name = "reminder_\(digest).caf"
    let folder = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Sounds")
    let url = folder.appendingPathComponent(name)
    let temporary = folder.appendingPathComponent("\(UUID().uuidString).caf")
    if FileManager.default.fileExists(atPath: url.path) { completion(name); return }
    do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    catch { completion(nil); return }
    func finish(_ success: Bool) {
      guard !completed else { return }
      completed = true
      output = nil // Close the CAF before exposing it to notifications.
      var saved = success
      if success {
        do {
          if !FileManager.default.fileExists(atPath: url.path) { try FileManager.default.moveItem(at: temporary, to: url) }
        } catch { saved = false }
      }
      try? FileManager.default.removeItem(at: temporary)
      completion(saved ? name : nil)
    }
    let utterance = AVSpeechUtterance(string: speech)
    utterance.voice = AVSpeechSynthesisVoice.speechVoices()
      .filter { $0.language == "en-US" }
      .sorted { $0.quality.rawValue > $1.quality.rawValue }.first
      ?? AVSpeechSynthesisVoice(language: "en-US")
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
    utterance.pitchMultiplier = 1.0
    synth.write(utterance) { [self] buffer in
      DispatchQueue.main.async { [self] in
        guard !completed, let pcm = buffer as? AVAudioPCMBuffer else { return }
        if pcm.frameLength == 0 { finish(output != nil); return }
        do {
          if output == nil { output = try AVAudioFile(forWriting: temporary, settings: pcm.format.settings) }
          // Custom notification sounds must be shorter than 30 seconds.
          if let file = output, Double(file.length + Int64(pcm.frameLength)) / pcm.format.sampleRate >= 29 {
            synth.stopSpeaking(at: .immediate); finish(false); return
          }
          try output?.write(from: pcm)
        } catch { finish(false) }
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
      guard let self = self, !self.completed else { return }
      self.synth.stopSpeaking(at: .immediate); finish(false)
    }
  }
}
