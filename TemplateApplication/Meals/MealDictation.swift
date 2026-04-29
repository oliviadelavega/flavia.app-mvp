//
// Flavia study app
//
// Speech-to-text controller for the meal description field. Wraps
// `SFSpeechRecognizer` + `AVAudioEngine` and streams partial results
// the view can splice into the bound text.
//

import AVFoundation
import Foundation
import Speech


@MainActor
@Observable
final class MealDictation {
    enum Status: Equatable {
        case idle
        case starting
        case recording
        case denied(String)
        case unavailable(String)
        case failed(String)
    }

    enum DictationError: LocalizedError {
        case noAudioInput

        var errorDescription: String? {
            switch self {
            case .noAudioInput:
                return "No microphone input detected. If you're on the simulator, enable I/O → Audio Input on the Mac."
            }
        }
    }


    private(set) var status: Status = .idle
    private(set) var transcript: String = ""

    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?


    var isRecording: Bool {
        if case .recording = status { return true }
        return false
    }


    func toggle() async {
        if isRecording {
            stop()
        } else {
            await start()
        }
    }

    func start() async {
        switch status {
        case .starting, .recording:
            return
        case .idle, .denied, .unavailable, .failed:
            break
        }
        status = .starting
        transcript = ""

        guard let recognizer else {
            status = .unavailable("Speech recognition isn't available for this locale.")
            return
        }
        guard recognizer.isAvailable else {
            status = .unavailable("Speech recognition is temporarily unavailable.")
            return
        }

        let speechAuth = await Self.requestSpeechAuthorization()
        guard speechAuth == .authorized else {
            status = .denied("Enable Speech Recognition for Flavia in Settings to dictate meals.")
            return
        }

        let micGranted = await Self.requestMicrophonePermission()
        guard micGranted else {
            status = .denied("Enable the Microphone for Flavia in Settings to dictate meals.")
            return
        }

        // Permissions can race: another call may have already started us.
        guard case .starting = status else { return }

        do {
            try configureAudioSession()
            try beginRecognition(with: recognizer)
            status = .recording
        } catch {
            cleanup()
            status = .failed(error.localizedDescription)
        }
    }

    func stop() {
        cleanup()
        switch status {
        case .recording, .starting:
            status = .idle
        case .idle, .denied, .unavailable, .failed:
            break
        }
    }


    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func beginRecognition(with recognizer: SFSpeechRecognizer) throws {
        let inputNode = audioEngine.inputNode
        // Ensure no leftover tap from a previous attempt — installing a
        // second tap on the same bus throws an NSException and traps.
        inputNode.removeTap(onBus: 0)

        let format = inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw DictationError.noAudioInput
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // iOS 17+ auto-picks the on-device path whenever the recognizer
        // claims on-device support — including the simulator, which ships
        // without the LSR asset and crashes with kLSRErrorDomain 300. Force
        // server-side recognition to keep the simulator workable.
        request.requiresOnDeviceRecognition = false
        self.request = request

        // Audio tap fires on AVFAudio's realtime render queue. The closure
        // must not inherit MainActor isolation from the enclosing class,
        // hence `@Sendable`. `append` is thread-safe.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable [request] buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        // SFSpeechRecognizer invokes this handler on an arbitrary queue, so
        // it likewise must be nonisolated. Hop to MainActor before touching
        // observable state.
        task = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorMessage = error.map(Self.userFacingMessage(for:))
            if let error {
                print("[MealDictation] recognition error: \(error)")
            }
            Task { @MainActor in
                guard let self else { return }
                if let transcript {
                    self.transcript = transcript
                }
                guard isFinal || errorMessage != nil else { return }
                self.cleanup()
                if let errorMessage {
                    self.status = .failed(errorMessage)
                } else {
                    self.status = .idle
                }
            }
        }
    }

    nonisolated private static func userFacingMessage(for error: Error) -> String {
        let nsError = error as NSError
        // kLSRErrorDomain 300 = on-device speech model failed to load. On the
        // simulator this happens because the asset isn't shipped; on device
        // it usually means Dictation is disabled in Settings.
        if nsError.domain == "kLSRErrorDomain" && nsError.code == 300 {
            #if targetEnvironment(simulator)
            return "Dictation isn't available in the iOS Simulator. Try a real device, "
                + "or enable Settings → General → Keyboard → Dictation in the simulator and restart it."
            #else
            return "Dictation couldn't start. Enable it in Settings → General → Keyboard → Dictation, then try again."
            #endif
        }
        return nsError.localizedDescription
    }

    private func cleanup() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }


    private nonisolated static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private nonisolated static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
