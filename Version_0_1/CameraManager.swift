//
//  CameraManager.swift
//  Version_0_1
//
//  Preview runs as soon as the camera is authorized so ASL→English is
//  never a black screen. Recognition (hand tracking / Gemma / CoreML)
//  only runs while the red record button is active.
//

import AVFoundation
import CoreML
import CoreVideo
import SwiftUI
import Combine
import UIKit

// MARK: - SignClassifier (optional CoreML path)

final class SignClassifier: ObservableObject {
    @Published var recognizedLabel: String = ""
    @Published var confidence: Double = 0
    @Published var isReady: Bool = false

    private var featureExtractor: MLModel?
    private var sequenceClassifier: MLModel?
    private var labels: [String] = []

    private let framesPerVideo: Int
    private var frameBuffer: [MLMultiArray] = []
    private let workQueue = DispatchQueue(label: "signa.sign.classifier")
    private var hasModels = false

    init(framesPerVideo: Int = 60) {
        self.framesPerVideo = framesPerVideo
        loadModels()
    }

    private func loadModels() {
        guard
            let featureURL = Bundle.main.url(forResource: "SpatialFeatureExtractor", withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: "SpatialFeatureExtractor", withExtension: "mlpackage"),
            let rnnURL = Bundle.main.url(forResource: "GestureRNN", withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: "GestureRNN", withExtension: "mlpackage"),
            let labelsURL = Bundle.main.url(forResource: "GestureLabels", withExtension: "txt")
        else {
            print("SignClassifier: CoreML models not bundled — using Gemma / hand-pose fallback.")
            return
        }

        do {
            featureExtractor = try MLModel(contentsOf: featureURL)
            sequenceClassifier = try MLModel(contentsOf: rnnURL)
            labels = try String(contentsOf: labelsURL, encoding: .utf8)
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.isEmpty }
            hasModels = featureExtractor != nil && sequenceClassifier != nil && !labels.isEmpty
            DispatchQueue.main.async { self.isReady = self.hasModels }
        } catch {
            print("SignClassifier: failed to load models — \(error)")
        }
    }

    func reset() {
        workQueue.async {
            self.frameBuffer.removeAll()
            DispatchQueue.main.async {
                self.recognizedLabel = ""
                self.confidence = 0
            }
        }
    }

    func ingest(pixelBuffer: CVPixelBuffer) {
        guard hasModels else { return }
        workQueue.async {
            guard let featureExtractor = self.featureExtractor else { return }

            guard
                let inputName = featureExtractor.modelDescription.inputDescriptionsByName.keys.first,
                let provider = try? MLDictionaryFeatureProvider(
                    dictionary: [inputName: MLFeatureValue(pixelBuffer: pixelBuffer)]
                ),
                let result = try? featureExtractor.prediction(from: provider),
                let outputName = featureExtractor.modelDescription.outputDescriptionsByName.keys.first,
                let features = result.featureValue(for: outputName)?.multiArrayValue
            else { return }

            self.frameBuffer.append(features)
            if self.frameBuffer.count > self.framesPerVideo {
                self.frameBuffer.removeFirst(self.frameBuffer.count - self.framesPerVideo)
            }
            if self.frameBuffer.count == self.framesPerVideo {
                self.classifySequence()
            }
        }
    }

    private func classifySequence() {
        guard let sequenceClassifier, let sequenceArray = try? Self.stack(frameBuffer) else { return }

        guard
            let inputName = sequenceClassifier.modelDescription.inputDescriptionsByName.keys.first,
            let provider = try? MLDictionaryFeatureProvider(
                dictionary: [inputName: MLFeatureValue(multiArray: sequenceArray)]
            ),
            let result = try? sequenceClassifier.prediction(from: provider),
            let outputName = sequenceClassifier.modelDescription.outputDescriptionsByName.keys.first,
            let probs = result.featureValue(for: outputName)?.multiArrayValue
        else { return }

        var bestIndex = 0
        var bestValue = -Double.infinity
        for i in 0..<probs.count {
            let value = probs[i].doubleValue
            if value > bestValue {
                bestValue = value
                bestIndex = i
            }
        }

        let label = labels.indices.contains(bestIndex) ? labels[bestIndex] : "?"
        DispatchQueue.main.async {
            self.recognizedLabel = label
            self.confidence = bestValue
        }
    }

    private static func stack(_ arrays: [MLMultiArray]) throws -> MLMultiArray {
        guard let first = arrays.first else {
            throw NSError(domain: "SignClassifier", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty frame buffer"])
        }
        let featureDim = first.count
        let shape: [NSNumber] = [1, NSNumber(value: arrays.count), NSNumber(value: featureDim)]
        let stacked = try MLMultiArray(shape: shape, dataType: .float32)

        for (frameIndex, frameFeatures) in arrays.enumerated() {
            for featureIndex in 0..<featureDim {
                stacked[[0, frameIndex, featureIndex] as [NSNumber]] = frameFeatures[featureIndex]
            }
        }
        return stacked
    }
}

// MARK: - CameraManager

final class CameraManager: NSObject, ObservableObject {

    @Published var isAuthorized = false
    /// True while AVCaptureSession is running (live video preview).
    @Published var isPreviewRunning = false
    /// True while the red button is armed for recognition.
    @Published var isRecognizing = false
    @Published var recognizedText: String = ""
    @Published var isClassifierReady = false
    @Published var isRecognitionAvailable = true
    @Published var recognitionSource: String = "Hand pose"
    @Published var gemmaError: String?
    /// Hand skeletons, body pose, and face landmarks for the live overlay.
    @Published var trackingOverlay = TrackingOverlay()
    /// Live class probabilities from the action model (for the bars UI).
    @Published var actionProbabilities: [(String, Double)] = []
    /// Which camera feeds the preview (front for selfie signing, back to film someone else).
    @Published var cameraPosition: AVCaptureDevice.Position = .front

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let classifier = SignClassifier()
    private let handPose = HandPoseRecognizer()
    private let gemma = GemmaSignRecognizer()
    private var cancellables = Set<AnyCancellable>()
    private var shouldClassify = false
    private var frameSkipCounter = 0
    /// Process every frame: the action LSTM expects a 30-frame ≈ 1 s window
    /// (matching its 30 fps training data), so skipping frames stretches
    /// signs to double speed and hurts recognition.
    private let frameStride = 1
    private var useCoreML = false
    private var useGemma = false
    private var hasHandsForGemma = false
    private var didConfigure = false
    /// Session-queue copy of the active camera position.
    private var currentPosition: AVCaptureDevice.Position = .front

    override init() {
        super.init()
        checkAuthorization()
        observeRecognizers()
        refreshGemmaPreference()
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshGemmaPreference()
        }
    }

    private func refreshGemmaPreference() {
        gemma.reloadSettings()
        let enabled = UserDefaults.standard.bool(forKey: "useGemmaVision")
        sessionQueue.async { self.useGemma = enabled }
        updateSourceLabel()
    }

    private func updateSourceLabel() {
        if isClassifierReady {
            recognitionSource = "CoreML"
        } else if gemma.isEnabledCached {
            recognitionSource = "Gemma"
        } else {
            recognitionSource = "Hand pose"
        }
    }

    private func observeRecognizers() {
        classifier.$isReady
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ready in
                guard let self else { return }
                self.isClassifierReady = ready
                self.sessionQueue.async { self.useCoreML = ready }
                self.updateSourceLabel()
            }
            .store(in: &cancellables)

        gemma.$lastError
            .receive(on: DispatchQueue.main)
            .assign(to: &$gemmaError)

        gemma.$isEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateSourceLabel() }
            .store(in: &cancellables)

        handPose.$trackingOverlay
            .receive(on: DispatchQueue.main)
            .assign(to: &$trackingOverlay)

        handPose.$actionProbabilities
            .receive(on: DispatchQueue.main)
            .assign(to: &$actionProbabilities)

        handPose.$hasHandsInFrame
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasHands in
                guard let self else { return }
                self.sessionQueue.async {
                    self.hasHandsForGemma = hasHands
                }
            }
            .store(in: &cancellables)

        // Prefer full transcript for the caption while recognizing; fall back to live label.
        Publishers.CombineLatest4(
            classifier.$recognizedLabel,
            gemma.$recognizedLabel,
            handPose.$liveLabel,
            handPose.$transcript
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] coreMLLabel, gemmaLabel, live, transcript in
            guard let self else { return }
            if self.isClassifierReady, !coreMLLabel.isEmpty {
                self.recognizedText = coreMLLabel
                self.recognitionSource = "CoreML"
            } else if self.gemma.isEnabledCached, !gemmaLabel.isEmpty {
                self.recognizedText = gemmaLabel
                self.recognitionSource = "Gemma"
            } else if !transcript.isEmpty {
                let previous = self.recognizedText
                self.recognizedText = transcript
                self.recognitionSource = "Hand pose"
                let hapticsOn = (UserDefaults.standard.object(forKey: "hapticFeedbackEnabled") as? Bool) ?? true
                if transcript != previous, hapticsOn {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            } else if !live.isEmpty {
                self.recognizedText = live
                self.recognitionSource = "Hand pose"
            } else if self.isRecognizing {
                // Keep empty so UI can show "Listening…"
                self.recognizedText = ""
            }
            // When stopped, keep the last transcript until the user resets.
        }
        .store(in: &cancellables)
    }

    func resetRecognition() {
        classifier.reset()
        handPose.reset()
        gemma.reset()
        recognizedText = ""
        trackingOverlay = TrackingOverlay()
        actionProbabilities = []
        frameSkipCounter = 0
    }

    /// Clears previously translated English words (after stop, or mid-session).
    func clearTranscript() {
        handPose.clearTranscript()
        classifier.reset()
        gemma.reset()
        recognizedText = ""
        actionProbabilities = []
    }

    func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            configureSessionThenPreview()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted { self?.configureSessionThenPreview() }
                }
            }
        default:
            isAuthorized = false
        }
    }

    private func configureSessionThenPreview() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureSessionLocked()
            self.startPreviewLocked()
        }
    }

    private func configureSessionLocked() {
        guard !didConfigure else { return }
        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        if session.inputs.isEmpty,
           let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        if session.outputs.isEmpty, session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = (currentPosition == .front)
            }
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }

        session.commitConfiguration()
        didConfigure = true
    }

    /// Flips between the front (selfie) and back camera without dropping the session.
    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let newPosition: AVCaptureDevice.Position = self.currentPosition == .front ? .back : .front
            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                let newInput = try? AVCaptureDeviceInput(device: device)
            else { return }

            self.session.beginConfiguration()
            for input in self.session.inputs {
                self.session.removeInput(input)
            }
            guard self.session.canAddInput(newInput) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(newInput)

            if let connection = self.videoOutput.connection(with: .video) {
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = (newPosition == .front)
                }
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
            self.session.commitConfiguration()

            self.currentPosition = newPosition
            DispatchQueue.main.async { self.cameraPosition = newPosition }
        }
    }

    // MARK: Preview vs recognition

    func startPreview() {
        sessionQueue.async { [weak self] in
            self?.configureSessionLocked()
            self?.startPreviewLocked()
        }
    }

    private func startPreviewLocked() {
        guard !session.isRunning else {
            DispatchQueue.main.async { self.isPreviewRunning = true }
            return
        }
        session.startRunning()
        DispatchQueue.main.async { self.isPreviewRunning = true }
    }

    func stopPreview() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.shouldClassify = false
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.isPreviewRunning = false
                self.isRecognizing = false
            }
        }
    }

    func startRecognition() {
        refreshGemmaPreference()
        resetRecognition()
        beginRecognitionSession()
    }

    /// Continue signing without wiping the English caption built so far.
    func resumeRecognitionKeepingTranscript() {
        refreshGemmaPreference()
        // Reset model buffers / votes, keep published recognizedText.
        classifier.reset()
        gemma.reset()
        handPose.resetBuffersKeepingTranscript()
        trackingOverlay = TrackingOverlay()
        actionProbabilities = []
        frameSkipCounter = 0
        beginRecognitionSession()
    }

    private func beginRecognitionSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureSessionLocked()
            self.startPreviewLocked()
            self.shouldClassify = true
            self.frameSkipCounter = 0
            DispatchQueue.main.async { self.isRecognizing = true }
        }
    }

    func stopRecognition() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.shouldClassify = false
            DispatchQueue.main.async {
                self.isRecognizing = false
                self.trackingOverlay = TrackingOverlay()
                self.actionProbabilities = []
            }
        }
    }

    private func classify(pixelBuffer: CVPixelBuffer) {
        let orientation: CGImagePropertyOrientation = currentPosition == .front ? .upMirrored : .up
        if useCoreML {
            classifier.ingest(pixelBuffer: pixelBuffer)
        } else if useGemma {
            handPose.ingest(pixelBuffer: pixelBuffer, orientation: orientation)
            if hasHandsForGemma {
                gemma.ingest(pixelBuffer: pixelBuffer)
            } else {
                gemma.clearRecognizedLabel()
            }
        } else {
            handPose.ingest(pixelBuffer: pixelBuffer, orientation: orientation)
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard shouldClassify else { return }
        frameSkipCounter += 1
        guard frameSkipCounter % frameStride == 0 else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        classify(pixelBuffer: pixelBuffer)
    }
}

/// SwiftUI wrapper that hosts the AVCaptureVideoPreviewLayer.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
    }

    final class PreviewUIView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
