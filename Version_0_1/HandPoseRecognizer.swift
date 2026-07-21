//
//  HandPoseRecognizer.swift
//  Version_0_1
//
//  On-device ASL→English via Vision hand pose + short-term motion,
//  backed by a CoreML hand-pose classifier (fingerspelling A–Z, 0–9)
//  from the MIT-licensed liudasbar/ASL-Recognizer project.
//  Tracks up to two hands, votes temporally, and locks one stable word.
//

import Vision
import CoreVideo
import CoreML
import Combine
import Foundation
import CoreGraphics

/// One bone segment of a tracked skeleton (Vision normalized, y-up).
struct OverlaySegment: Equatable {
    var a: CGPoint
    var b: CGPoint
}

/// Full MediaPipe-holistic-style tracking overlay for the camera view.
struct TrackingOverlay: Equatable {
    var handPoints: [CGPoint] = []
    var handSegments: [OverlaySegment] = []
    var bodyPoints: [CGPoint] = []
    var bodySegments: [OverlaySegment] = []
    var facePoints: [CGPoint] = []

    var isEmpty: Bool {
        handPoints.isEmpty && bodyPoints.isEmpty && facePoints.isEmpty
    }
}

final class HandPoseRecognizer: ObservableObject {
    @Published var liveLabel: String = ""
    @Published var transcript: String = ""
    @Published var confidence: Double = 0
    @Published var hasHandsInFrame: Bool = false
    /// Hand skeletons + body pose + face landmarks for the live overlay.
    @Published var trackingOverlay = TrackingOverlay()
    /// Latest class probabilities from the action LSTM (label, probability).
    @Published var actionProbabilities: [(String, Double)] = []

    private let request = VNDetectHumanHandPoseRequest()
    /// Body pose gives us the head (nose/eyes) so signs can be located
    /// relative to the face — e.g. Hello is a salute FROM the forehead.
    private let bodyRequest = VNDetectHumanBodyPoseRequest()
    /// Face landmarks (~76 points) drawn as the green "mesh" overlay.
    private let faceRequest = VNDetectFaceLandmarksRequest()
    private let workQueue = DispatchQueue(label: "signa.hand.pose", qos: .userInitiated)

    private var voteBuffer: [(label: String, score: Double)] = []
    /// A sign must be held ~0.5s (7 of 10 frames agreeing) before it locks —
    /// slower, but stops hand transitions from spamming words.
    private let voteWindow = 10
    private let voteThreshold = 7
    private let scoreGate = 0.7

    private var lostCount = 0
    private let clearAfterLostFrames = 14
    private var lastLocked: String = ""
    private var lastLockTime: CFAbsoluteTime = 0
    private let lockCooldown: CFAbsoluteTime = 0.9
    private var frameTick = 0
    /// After hands leave the frame, allow locking the same word again.
    private var handsWereLost = false
    /// Frames since the last lock where NO sign matched (hand relaxed,
    /// moving between signs, or out of frame). A new word may only lock
    /// after a brief neutral gap, so one gesture can't chain into three.
    private var neutralSinceLock = 99

    private var wristHistory: [CGPoint] = []
    private let historyLimit = 16
    /// Recent wrist→head distances; rising values mean the hand is moving
    /// away from the head (the second half of the Hello salute).
    private var headDistHistory: [CGFloat] = []

    /// CoreML hand-pose classifier (21 Vision keypoints → letter/digit).
    private var poseModel: MLModel?
    private let poseModelThreshold = 0.88

    /// Word-level LSTM from nicknochnack/ActionDetectionforSignLanguage
    /// (action.h5 → CoreML). Watches 30 frames of holistic keypoints and
    /// recognizes sign MOTION: hello, thanks, iloveyou.
    private let actionModel = ActionSignRecognizer()

    init() {
        request.maximumHandCount = 2
        workQueue.async { [weak self] in
            guard let self else { return }
            if let url = Bundle.main.url(forResource: "ASLHandPoseClassifier", withExtension: "mlmodelc"),
               let model = try? MLModel(contentsOf: url) {
                self.poseModel = model
            } else {
                print("HandPoseRecognizer: ASLHandPoseClassifier not bundled — geometry rules only.")
            }
        }
    }

    func reset() {
        workQueue.async {
            self.voteBuffer.removeAll()
            self.lostCount = 0
            self.lastLocked = ""
            self.lastLockTime = 0
            self.wristHistory.removeAll()
            self.headDistHistory.removeAll()
            self.handsWereLost = false
            self.neutralSinceLock = 99
            self.actionModel.reset()
            DispatchQueue.main.async {
                self.liveLabel = ""
                self.transcript = ""
                self.confidence = 0
                self.hasHandsInFrame = false
                self.trackingOverlay = TrackingOverlay()
                self.actionProbabilities = []
            }
        }
    }

    /// Clears the English transcript without tearing down the camera session.
    func clearTranscript() {
        workQueue.async {
            self.voteBuffer.removeAll()
            self.lastLocked = ""
            self.lastLockTime = 0
            self.handsWereLost = false
            self.neutralSinceLock = 99
            self.wristHistory.removeAll()
            self.headDistHistory.removeAll()
            self.actionModel.reset()
            DispatchQueue.main.async {
                self.liveLabel = ""
                self.transcript = ""
                self.confidence = 0
                self.hasHandsInFrame = false
                self.actionProbabilities = []
            }
        }
    }

    /// Soft reset used when resuming record — keeps the published transcript.
    func resetBuffersKeepingTranscript() {
        workQueue.async {
            self.voteBuffer.removeAll()
            self.lostCount = 0
            self.lastLocked = ""
            self.lastLockTime = 0
            self.handsWereLost = false
            self.neutralSinceLock = 99
            self.wristHistory.removeAll()
            self.headDistHistory.removeAll()
            self.actionModel.reset()
            DispatchQueue.main.async {
                self.liveLabel = ""
                self.confidence = 0
                self.hasHandsInFrame = false
                self.trackingOverlay = TrackingOverlay()
                self.actionProbabilities = []
            }
        }
    }

    func ingest(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .upMirrored) {
        workQueue.async {
            // Face landmarks every other frame — hands/body every frame for speed.
            self.frameTick += 1
            let runFace = self.frameTick % 2 == 0
            let requests: [VNRequest] = runFace
                ? [self.request, self.bodyRequest, self.faceRequest]
                : [self.request, self.bodyRequest]
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
            do {
                try handler.perform(requests)
            } catch {
                self.handleLost()
                return
            }

            let head = Self.headPoint(from: self.bodyRequest.results?.first)

            let observations = self.request.results ?? []
            let confidentHandCount = observations.filter { observation in
                guard let points = try? observation.recognizedPoints(.all) else { return false }
                let keyJoints: [VNHumanHandPoseObservation.JointName] = [
                    .wrist, .thumbTip, .indexTip, .middleTip, .ringTip, .littleTip
                ]
                let confidences = keyJoints.compactMap { points[$0]?.confidence }
                guard confidences.count >= 4 else { return false }
                let avg = confidences.reduce(0, +) / Float(confidences.count)
                return avg >= 0.42
            }.count
            let hasConfidentHand = confidentHandCount > 0

            // Full MediaPipe-style tracking overlay: hand skeletons, body
            // pose lines, and face landmark points.
            var overlay = TrackingOverlay()
            for observation in observations {
                if let points = try? observation.recognizedPoints(.all) {
                    Self.appendHandSkeleton(points, to: &overlay)
                }
            }
            Self.appendBodySkeleton(self.bodyRequest.results?.first, to: &overlay)
            Self.appendFaceLandmarks(self.faceRequest.results?.first, to: &overlay)

            // Keep the 3-class action LSTM warm for Hello/Thanks/ILY only —
            // it must NOT override the full geometry vocabulary (You, Yes…).
            let actionResult = self.actionModel.ingest(
                body: self.bodyRequest.results?.first,
                hands: observations
            )
            DispatchQueue.main.async {
                self.trackingOverlay = overlay
                self.hasHandsInFrame = hasConfidentHand
                self.actionProbabilities = [] // UI bars removed
            }

            guard !observations.isEmpty else {
                self.handsWereLost = true
                DispatchQueue.main.async { self.hasHandsInFrame = false }
                self.handleLost()
                return
            }
            // A blurry blob near the lens can register as a low-confidence
            // "hand" — never classify those frames.
            guard hasConfidentHand else {
                self.handleLost(soft: true)
                return
            }
            self.handsWereLost = false

            // Classify the most confident hand only — mixing two hands
            // often flips between unrelated signs. The second hand's wrist
            // is still tracked so two-handed signs (Stop) can require the
            // chopping hand to actually meet the base hand.
            let primary = observations.max(by: { $0.confidence < $1.confidence })
            let otherWrist: CGPoint? = observations
                .filter { $0 !== primary }
                .compactMap { obs -> CGPoint? in
                    guard let pts = try? obs.recognizedPoints(.all) else { return nil }
                    return Self.point(pts, .wrist, minConfidence: 0.3)
                }
                .first
            var geometryBest: (String, Double)? = nil

            if let observation = primary,
               let points = try? observation.recognizedPoints(.all) {
                let keyJoints: [VNHumanHandPoseObservation.JointName] = [
                    .wrist, .indexTip, .middleTip, .ringTip, .littleTip, .thumbTip
                ]
                let confidences = keyJoints.compactMap { points[$0]?.confidence }
                if confidences.count >= 5 {
                    let avg = Double(confidences.reduce(0, +) / Float(confidences.count))
                    if avg >= 0.45 {
                        if let wrist = Self.point(points, .wrist, minConfidence: 0.35) {
                            let smoothed: CGPoint
                            if let last = self.wristHistory.last {
                                smoothed = CGPoint(
                                    x: last.x * 0.55 + wrist.x * 0.45,
                                    y: last.y * 0.55 + wrist.y * 0.45
                                )
                            } else {
                                smoothed = wrist
                            }
                            self.wristHistory.append(smoothed)
                            if self.wristHistory.count > self.historyLimit {
                                self.wristHistory.removeFirst(self.wristHistory.count - self.historyLimit)
                            }
                            if let head {
                                self.headDistHistory.append(Self.distance(smoothed, head))
                                if self.headDistHistory.count > self.historyLimit {
                                    self.headDistHistory.removeFirst(self.headDistHistory.count - self.historyLimit)
                                }
                            }
                        }

                        let motion = Self.motionFeatures(history: self.wristHistory, headDistances: self.headDistHistory)
                        if let result = Self.classify(points: points, motion: motion, head: head,
                                                      otherWrist: otherWrist) {
                            geometryBest = (result.0, max(result.1, avg * result.1))
                        } else {
                            // Fingerspelling fallback; skip near the head.
                            let wristNearHead: Bool = {
                                guard let head, let wrist = Self.point(points, .wrist, minConfidence: 0.35) else { return false }
                                return Self.distance(wrist, head) < 0.24
                            }()
                            if !wristNearHead, let mlResult = self.classifyWithModel(observation: observation) {
                                geometryBest = mlResult
                            }
                        }
                    }
                }
            }

            // Geometry owns the full word list. Action LSTM may only
            // reinforce Hello / Thanks / I love you when geometry is empty
            // or already agrees — never steal "You" → "I love you".
            let actionLabels: Set<String> = ["Hello", "Thanks", "I love you"]
            let best: (String, Double)?
            if let geometryBest {
                if let actionResult,
                   actionLabels.contains(actionResult.0),
                   actionResult.0 == geometryBest.0 {
                    best = (geometryBest.0, max(geometryBest.1, actionResult.1))
                } else {
                    best = geometryBest
                }
            } else if let actionResult,
                      actionLabels.contains(actionResult.0),
                      actionResult.1 >= 0.92,
                      head != nil {
                best = actionResult
            } else {
                best = nil
            }

            guard let best else {
                self.handleLost(soft: true)
                return
            }
            self.consider(label: best.0, score: best.1)
        }
    }

    /// Best available head landmark from the body pose: nose, else eye
    /// midpoint, else neck (all in Vision normalized, y-up coordinates).
    private static func headPoint(from observation: VNHumanBodyPoseObservation?) -> CGPoint? {
        guard let observation else { return nil }
        if let nose = try? observation.recognizedPoint(.nose), nose.confidence >= 0.3 {
            return nose.location
        }
        if let lEye = try? observation.recognizedPoint(.leftEye),
           let rEye = try? observation.recognizedPoint(.rightEye),
           lEye.confidence >= 0.3, rEye.confidence >= 0.3 {
            return CGPoint(x: (lEye.location.x + rEye.location.x) / 2,
                           y: (lEye.location.y + rEye.location.y) / 2)
        }
        if let neck = try? observation.recognizedPoint(.neck), neck.confidence >= 0.3 {
            return CGPoint(x: neck.location.x, y: neck.location.y + 0.12)
        }
        return nil
    }

    /// Runs the bundled CreateML hand-pose classifier on Vision's 21 keypoints.
    /// Returns an uppercased letter/digit when the model is very confident.
    private func classifyWithModel(observation: VNHumanHandPoseObservation) -> (String, Double)? {
        guard
            let poseModel,
            let keypoints = try? observation.keypointsMultiArray(),
            let provider = try? MLDictionaryFeatureProvider(
                dictionary: ["poses": MLFeatureValue(multiArray: keypoints)]
            ),
            let result = try? poseModel.prediction(from: provider),
            let label = result.featureValue(for: "label")?.stringValue,
            let probs = result.featureValue(for: "labelProbabilities")?.dictionaryValue as? [String: Double],
            let confidence = probs[label]
        else { return nil }

        guard confidence >= poseModelThreshold else { return nil }
        return (label.uppercased(), confidence)
    }

    private func handleLost(soft: Bool = false) {
        lostCount += 1
        neutralSinceLock = min(neutralSinceLock + 1, 99)
        // Soft loss (hand still visible, no label): keep recent votes so a
        // brief ambiguous frame doesn't restart the whole window. Motion
        // signs (Sorry, Please, Where) flicker to nil mid-gesture, so allow
        // several such frames before the vote resets.
        if !soft {
            voteBuffer.removeAll()
        } else if lostCount >= 7 {
            voteBuffer.removeAll()
        }
        if lostCount >= clearAfterLostFrames {
            handsWereLost = true
            DispatchQueue.main.async {
                self.liveLabel = ""
                self.confidence = 0
                self.hasHandsInFrame = false
                self.trackingOverlay = TrackingOverlay()
            }
        }
    }

    // MARK: - Overlay construction

    /// Bone chains of the hand, MediaPipe style (wrist → each finger).
    private static let handChains: [[VNHumanHandPoseObservation.JointName]] = [
        [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip],
        [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip],
        [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip],
        [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip],
        [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip],
        [.indexMCP, .middleMCP, .ringMCP, .littleMCP] // across the palm
    ]

    private static func appendHandSkeleton(
        _ points: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint],
        to overlay: inout TrackingOverlay
    ) {
        var located: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]
        for (name, p) in points where p.confidence >= 0.3 {
            located[name] = p.location
            overlay.handPoints.append(p.location)
        }
        for chain in handChains {
            for i in 0..<(chain.count - 1) {
                if let a = located[chain[i]], let b = located[chain[i + 1]] {
                    overlay.handSegments.append(OverlaySegment(a: a, b: b))
                }
            }
        }
    }

    private static let bodyChains: [[VNHumanBodyPoseObservation.JointName]] = [
        [.leftShoulder, .neck, .rightShoulder],
        [.leftShoulder, .leftElbow, .leftWrist],
        [.rightShoulder, .rightElbow, .rightWrist],
        [.neck, .nose]
    ]

    private static func appendBodySkeleton(
        _ observation: VNHumanBodyPoseObservation?,
        to overlay: inout TrackingOverlay
    ) {
        guard let observation, let joints = try? observation.recognizedPoints(.all) else { return }
        var located: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        let wanted: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .neck, .leftShoulder, .rightShoulder,
            .leftElbow, .rightElbow, .leftWrist, .rightWrist
        ]
        for name in wanted {
            if let p = joints[name], p.confidence >= 0.25 {
                located[name] = p.location
                overlay.bodyPoints.append(p.location)
            }
        }
        for chain in bodyChains {
            for i in 0..<(chain.count - 1) {
                if let a = located[chain[i]], let b = located[chain[i + 1]] {
                    overlay.bodySegments.append(OverlaySegment(a: a, b: b))
                }
            }
        }
    }

    private static func appendFaceLandmarks(
        _ face: VNFaceObservation?,
        to overlay: inout TrackingOverlay
    ) {
        guard let face, let all = face.landmarks?.allPoints else { return }
        // pointsInImage with a unit size yields Vision-normalized coordinates.
        overlay.facePoints = all.pointsInImage(imageSize: CGSize(width: 1, height: 1))
    }

    private func consider(label: String, score: Double) {
        guard score >= scoreGate else {
            handleLost(soft: true)
            return
        }
        lostCount = 0
        voteBuffer.append((label, score))
        if voteBuffer.count > voteWindow {
            voteBuffer.removeFirst(voteBuffer.count - voteWindow)
        }

        var counts: [String: (n: Int, sum: Double)] = [:]
        for item in voteBuffer {
            let cur = counts[item.label] ?? (0, 0)
            counts[item.label] = (cur.n + 1, cur.sum + item.score)
        }
        // Only surface a word once it clearly wins the vote — no flickering
        // between candidates while the vote is still open.
        guard let winner = counts.max(by: { $0.value.n < $1.value.n }),
              winner.value.n >= voteThreshold else {
            return
        }

        // Require a clear majority vs the runner-up so Please/Goodbye don't
        // trade places when both get a few votes.
        let runnerUp = counts
            .filter { $0.key != winner.key }
            .map(\.value.n)
            .max() ?? 0
        guard winner.value.n >= runnerUp + 1 else { return }

        let avgScore = winner.value.sum / Double(winner.value.n)
        guard avgScore >= 0.78 else { return }
        let now = CFAbsoluteTimeGetCurrent()

        // After a word locks, the hand must pass through a neutral moment
        // (a few frames with no recognized sign) before ANY new word can
        // lock. This stops one gesture + its wind-down from producing
        // "OK Thanks My" in a single motion. Exception: if the previous
        // word has completely vanished from the vote window — the signer
        // flowed straight into a clearly different sign (Yes → next word)
        // — the new word may lock without the neutral pause.
        if !lastLocked.isEmpty, neutralSinceLock < 3 {
            let oldWordGone = counts[lastLocked] == nil
            if winner.key == lastLocked {
                voteBuffer.removeAll()
                return
            }
            if !oldWordGone {
                // Old word still echoing in the window — let its votes age
                // out (don't clear, or the new word could never build up).
                return
            }
        }

        // Lock one word at a time. Same word can lock again after hands
        // left the frame (or a long cooldown), so "Hello Hello" is possible.
        let isNewWord = winner.key != lastLocked
        let canRepeatSame = handsWereLost && (now - lastLockTime >= lockCooldown)
        guard now - lastLockTime >= lockCooldown, isNewWord || canRepeatSame else {
            voteBuffer.removeAll()
            return
        }

        lastLocked = winner.key
        lastLockTime = now
        handsWereLost = false
        neutralSinceLock = 0
        DispatchQueue.main.async {
            self.liveLabel = winner.key
            self.confidence = avgScore
            if self.transcript.isEmpty {
                self.transcript = winner.key
            } else {
                self.transcript += " " + winner.key
            }
        }
        voteBuffer.removeAll()
    }

    // MARK: - Motion

    private struct MotionFeatures {
        var speed: CGFloat
        var lateralSwing: CGFloat
        var verticalDrift: CGFloat
        var isWaving: Bool
        var isPushingOut: Bool
        /// Wrist is travelling downward across the recent window — the
        /// signature of the Stop chop onto the base hand.
        var isMovingDown: Bool
        /// Hand was recently near the head and is now moving away from it —
        /// the outward half of the Hello salute.
        var isLeavingHead: Bool
        /// Smallest wrist→head distance in the recent window.
        var minHeadDistance: CGFloat
    }

    private static func motionFeatures(history: [CGPoint], headDistances: [CGFloat]) -> MotionFeatures {
        var isLeavingHead = false
        var minHeadDistance = CGFloat.greatestFiniteMagnitude
        if headDistances.count >= 5 {
            minHeadDistance = headDistances.min() ?? minHeadDistance
            let firstHalf = headDistances.prefix(headDistances.count / 2)
            let recent = headDistances.suffix(3)
            let earlyMin = firstHalf.min() ?? .greatestFiniteMagnitude
            let recentAvg = recent.reduce(0, +) / CGFloat(recent.count)
            // Started close to the head/chin, now clearly further away.
            // 0.30 covers a hand at the chin whose WRIST sits well below
            // the nose — 0.24 was too tight and made Thanks unreliable.
            isLeavingHead = earlyMin < 0.30 && recentAvg > earlyMin + 0.04
        }

        guard history.count >= 4 else {
            return MotionFeatures(speed: 0, lateralSwing: 0, verticalDrift: 0,
                                  isWaving: false, isPushingOut: false, isMovingDown: false,
                                  isLeavingHead: isLeavingHead, minHeadDistance: minHeadDistance)
        }
        var path: CGFloat = 0
        for i in 1..<history.count {
            path += distance(history[i], history[i - 1])
        }
        let speed = path / CGFloat(history.count - 1)
        let xs = history.map(\.x)
        let ys = history.map(\.y)
        let lateral = (xs.max() ?? 0) - (xs.min() ?? 0)
        let vertical = (ys.max() ?? 0) - (ys.min() ?? 0)
        // Wave: strong left-right oscillation with modest vertical move.
        let isWaving = lateral > 0.08 && lateral > vertical * 1.35 && speed > 0.012
        let isPushingOut = vertical > 0.06 && speed > 0.01 && !isWaving
        // Downward travel: recent positions clearly below the earlier ones
        // (Vision is y-up, so falling y = hand moving down).
        let earlyY = history.prefix(3).reduce(0) { $0 + $1.y } / 3
        let lateY = history.suffix(3).reduce(0) { $0 + $1.y } / 3
        let isMovingDown = earlyY - lateY > 0.04 && !isWaving
        return MotionFeatures(
            speed: speed,
            lateralSwing: lateral,
            verticalDrift: vertical,
            isWaving: isWaving,
            isPushingOut: isPushingOut,
            isMovingDown: isMovingDown,
            isLeavingHead: isLeavingHead,
            minHeadDistance: minHeadDistance
        )
    }

    // MARK: - Geometry

    private struct Digits {
        var wrist: CGPoint
        var thumbTip: CGPoint, thumbIP: CGPoint, thumbMP: CGPoint
        var indexTip: CGPoint, indexPIP: CGPoint, indexMCP: CGPoint
        var middleTip: CGPoint, middlePIP: CGPoint, middleMCP: CGPoint
        var ringTip: CGPoint, ringPIP: CGPoint, ringMCP: CGPoint
        var littleTip: CGPoint, littlePIP: CGPoint, littleMCP: CGPoint
        /// How many of the four fingertips Vision ACTUALLY saw (vs. the
        /// PIP fallback). A palm pressed flat on the chest hides its tips
        /// and would otherwise be indistinguishable from a fist.
        var realTipCount: Int
    }

    private static func point(_ points: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint],
                             _ name: VNHumanHandPoseObservation.JointName,
                             minConfidence: Float = 0.52) -> CGPoint? {
        guard let p = points[name], p.confidence >= minConfidence else { return nil }
        return p.location
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func isFingerExtended(tip: CGPoint, pip: CGPoint, mcp: CGPoint) -> Bool {
        let tipDist = distance(tip, mcp)
        let pipDist = distance(pip, mcp)
        guard pipDist > 0.008 else { return false }
        // tip beyond PIP relative to MCP + tip farther from MCP than PIP is.
        let tipBeyondPIP = distance(tip, mcp) > distance(pip, mcp) * 1.18
        return tipDist > pipDist * 1.22 && tipBeyondPIP
    }

    private static func isFingerCurled(tip: CGPoint, pip: CGPoint, mcp: CGPoint) -> Bool {
        let tipDist = distance(tip, mcp)
        let pipDist = distance(pip, mcp)
        return tipDist < pipDist * 1.18 || distance(tip, pip) < 0.055
    }

    private static func isThumbExtended(tip: CGPoint, ip: CGPoint, mp: CGPoint) -> Bool {
        distance(tip, mp) > distance(ip, mp) * 1.15
    }

    private static func digits(from points: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint]) -> Digits? {
        // Core joints (wrist, knuckles) must be tracked. Curled fingertips
        // are often OCCLUDED in a fist and drop below any threshold — those
        // fall back to their PIP joint, which correctly reads as "curled".
        // Without this, fist signs (Sorry, Yes, No) never classified at all.
        guard
            let wrist = point(points, .wrist, minConfidence: 0.35),
            let thumbTip = point(points, .thumbTip, minConfidence: 0.3),
            let thumbIP = point(points, .thumbIP, minConfidence: 0.25),
            let thumbMP = point(points, .thumbMP, minConfidence: 0.25),
            let indexPIP = point(points, .indexPIP, minConfidence: 0.25),
            let indexMCP = point(points, .indexMCP, minConfidence: 0.25),
            let middlePIP = point(points, .middlePIP, minConfidence: 0.25),
            let middleMCP = point(points, .middleMCP, minConfidence: 0.25),
            let ringPIP = point(points, .ringPIP, minConfidence: 0.2),
            let ringMCP = point(points, .ringMCP, minConfidence: 0.2),
            let littlePIP = point(points, .littlePIP, minConfidence: 0.2),
            let littleMCP = point(points, .littleMCP, minConfidence: 0.2)
        else { return nil }

        let realIndexTip = point(points, .indexTip, minConfidence: 0.3)
        let realMiddleTip = point(points, .middleTip, minConfidence: 0.3)
        let realRingTip = point(points, .ringTip, minConfidence: 0.25)
        let realLittleTip = point(points, .littleTip, minConfidence: 0.25)
        let realTipCount = [realIndexTip, realMiddleTip, realRingTip, realLittleTip]
            .compactMap { $0 }.count

        let indexTip = realIndexTip ?? indexPIP
        let middleTip = realMiddleTip ?? middlePIP
        let ringTip = realRingTip ?? ringPIP
        let littleTip = realLittleTip ?? littlePIP

        return Digits(
            wrist: wrist,
            thumbTip: thumbTip, thumbIP: thumbIP, thumbMP: thumbMP,
            indexTip: indexTip, indexPIP: indexPIP, indexMCP: indexMCP,
            middleTip: middleTip, middlePIP: middlePIP, middleMCP: middleMCP,
            ringTip: ringTip, ringPIP: ringPIP, ringMCP: ringMCP,
            littleTip: littleTip, littlePIP: littlePIP, littleMCP: littleMCP,
            realTipCount: realTipCount
        )
    }

    private static func classify(
        points: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint],
        motion: MotionFeatures,
        head: CGPoint?,
        otherWrist: CGPoint?
    ) -> (String, Double)? {
        guard let d = digits(from: points) else { return nil }

        // Lower floor than before — a closed fist is compact and was being
        // rejected outright, which silently disabled Sorry / Yes / No.
        let span = max(distance(d.indexTip, d.littleTip), distance(d.wrist, d.middleMCP))
        guard span > 0.07 else { return nil }

        let thumbExt = isThumbExtended(tip: d.thumbTip, ip: d.thumbIP, mp: d.thumbMP)
        let indexExt = isFingerExtended(tip: d.indexTip, pip: d.indexPIP, mcp: d.indexMCP)
        let middleExt = isFingerExtended(tip: d.middleTip, pip: d.middlePIP, mcp: d.middleMCP)
        let ringExt = isFingerExtended(tip: d.ringTip, pip: d.ringPIP, mcp: d.ringMCP)
        let littleExt = isFingerExtended(tip: d.littleTip, pip: d.littlePIP, mcp: d.littleMCP)

        let indexCurl = isFingerCurled(tip: d.indexTip, pip: d.indexPIP, mcp: d.indexMCP)
        let middleCurl = isFingerCurled(tip: d.middleTip, pip: d.middlePIP, mcp: d.middleMCP)
        let ringCurl = isFingerCurled(tip: d.ringTip, pip: d.ringPIP, mcp: d.ringMCP)
        let littleCurl = isFingerCurled(tip: d.littleTip, pip: d.littlePIP, mcp: d.littleMCP)
        let openPalm = indexExt && middleExt && ringExt && littleExt && distance(d.indexTip, d.littleTip) > 0.11
        let extendedCount = [indexExt, middleExt, ringExt, littleExt].filter { $0 }.count

        let headDistance = head.map { distance(d.wrist, $0) } ?? 1
        // Fingertips at/above the head line — a raised, salute-like hand.
        let handRaisedToHead = head.map { d.middleTip.y > $0.y - 0.10 } ?? false
        // Signs located on the body (chin, chest) require an actual person
        // in frame. Without a head there is no chin/chest — otherwise a
        // hand in front of a table can "sign" Thanks or My.
        let hasPerson = head != nil

        // ------------------------------------------------------------------
        // ZONES — mutually exclusive, head-relative regions. The same
        // handshape means a different word in each zone (a fist is Sorry on
        // the chest but Yes in neutral space; thumb+pinky is Drink at the
        // mouth but Help in neutral space). Every sign below is matched in
        // exactly ONE zone, so chin and chest can never both claim a hand.
        // ------------------------------------------------------------------
        enum Zone { case head, chin, chest, neutral }
        let zone: Zone
        if let head {
            let below = head.y - d.wrist.y            // + = wrist below head
            let lateral = abs(d.wrist.x - head.x)
            if headDistance < 0.26, below < 0.12 {
                zone = .head
            } else if below >= 0, below < 0.26, lateral < 0.30 {
                zone = .chin
            } else if below >= 0.26, below < 0.60, lateral < 0.34 {
                zone = .chest
            } else {
                zone = .neutral
            }
        } else {
            zone = .neutral
        }

        // Handshapes.
        let pointing =
            indexExt && !middleExt && !ringExt &&
            (littleCurl || !littleExt) &&
            (middleCurl || distance(d.middleTip, d.middleMCP) < 0.09)
        let isFist = indexCurl && middleCurl && ringCurl && littleCurl
        // A REAL fist: Vision must actually see curled fingertips. A palm
        // pressed flat on the chest hides its tips, reads as "curled" via
        // the PIP fallback, and used to turn Please into Sorry.
        let strongFist = isFist && d.realTipCount >= 3
        let vShape = indexExt && middleExt && !ringExt && !littleExt && ringCurl && littleCurl
        let callShape = thumbExt && littleExt && indexCurl && middleCurl && ringCurl
        let flatHand = extendedCount >= 3 && !indexCurl && !middleCurl
        let tipsBunched =
            distance(d.thumbTip, d.indexTip) < 0.055 &&
            distance(d.indexTip, d.middleTip) < 0.05 &&
            distance(d.middleTip, d.ringTip) < 0.05
        // Shared motion words.
        let chopping = motion.verticalDrift > 0.05 && motion.speed > 0.012 &&
                       motion.verticalDrift > motion.lateralSwing
        let circling = motion.speed > 0.008 &&
                       (motion.lateralSwing > 0.03 || motion.verticalDrift > 0.03)
        // Two-handed STOP: this hand travels DOWN and meets the other
        // (horizontal base) hand — descending wrist ending at/above the
        // other wrist, close enough to be in contact.
        let stopContact = otherWrist.map { other in
            (motion.isMovingDown || chopping) &&
            distance(d.wrist, other) < 0.26 &&
            d.wrist.y > other.y - 0.06
        } ?? false

        // Hello: salute — flat-ish hand that WAS at the forehead and is now
        // moving away. Checked before the zone switch because by the time
        // the motion reads "leaving", the hand is already below the head.
        if flatHand, motion.isLeavingHead, motion.minHeadDistance < 0.20 {
            return ("Hello", 0.96)
        }

        // See: V handshape that WAS at the eyes and is now moving forward.
        // Also global — mid-arc the wrist has already left the head zone,
        // and the moving V was being misread as a flat palm → "Thanks".
        if vShape, motion.isLeavingHead, motion.minHeadDistance < 0.34 {
            return ("See", 0.92)
        }

        // OK — unique pinch shape, valid in any zone.
        if distance(d.thumbTip, d.indexTip) < 0.055, middleExt, ringExt, littleExt {
            return ("OK", 0.92)
        }

        // I love you — thumb+index+pinky out, middle+ring folded, off the head.
        if zone != .head, thumbExt, indexExt, littleExt, middleCurl, ringCurl,
           !middleExt, !ringExt,
           distance(d.middleTip, d.middleMCP) < 0.075,
           distance(d.ringTip, d.ringMCP) < 0.075,
           distance(d.indexTip, d.littleTip) > 0.12 {
            return ("I love you", 0.91)
        }

        switch zone {
        case .head:
            if flatHand, handRaisedToHead, motion.isWaving {
                return ("Hello", 0.93)
            }
            if flatHand, handRaisedToHead, headDistance < 0.22 {
                return ("Hello", 0.9)
            }
            if vShape {
                return (motion.isPushingOut || motion.speed > 0.008)
                    ? ("See", 0.88) : ("Peace", 0.86)
            }
            if indexExt, middleExt, ringExt, !littleExt, littleCurl {
                return ("Water", 0.89)
            }
            if tipsBunched, motion.speed > 0.005 {
                return ("Eat", 0.88)
            }
            if callShape {
                return ("Drink", 0.86)
            }
            if flatHand, handRaisedToHead,
               motion.speed > 0.004, motion.speed < 0.02,
               !motion.isWaving, !motion.isLeavingHead {
                return ("Know", 0.84)
            }

        case .chin:
            // V at eye level (the wrist of a V held at the eyes sits in
            // this band): moving out = See, held still = Peace.
            if vShape {
                if motion.isPushingOut || motion.isLeavingHead || motion.speed > 0.01 {
                    return ("See", 0.88)
                }
                return ("Peace", 0.84)
            }
            // Thanks: open palm at the chin moving outward.
            if flatHand, motion.isLeavingHead || motion.isPushingOut {
                return ("Thanks", 0.9)
            }
            if indexExt, middleExt, ringExt, !littleExt, littleCurl {
                return ("Water", 0.89)
            }
            if tipsBunched, motion.speed > 0.005 {
                return ("Eat", 0.88)
            }
            if callShape {
                return ("Drink", 0.86)
            }

        case .chest:
            // Two-handed STOP: flat hand descending onto the base hand.
            // Checked first — the chop would otherwise read as Please.
            if flatHand, stopContact {
                return ("Stop", 0.93)
            }
            // Sorry needs REAL fingertip evidence of a fist; a palm flat
            // on the chest with hidden tips must not land here.
            if strongFist {
                return ("Sorry", 0.9)
            }
            if flatHand {
                // Thanks finishes its arc here — don't let Please steal it.
                if motion.isLeavingHead, motion.minHeadDistance < 0.30 {
                    return ("Thanks", 0.88)
                }
                if chopping {
                    return ("Stop", 0.84)
                }
                if circling {
                    return ("Please", 0.88)
                }
                // Still hand: fingers spread = Fine (5-hand), together = My.
                if distance(d.indexTip, d.littleTip) > 0.14, thumbExt {
                    return ("Fine", 0.85)
                }
                return ("My", 0.88)
            }
            // Ambiguous shape (tips hidden — palm probably pressed to the
            // chest) moving in circles: that's Please, not Sorry.
            if !strongFist, !pointing, circling, !chopping {
                return ("Please", 0.84)
            }
            if pointing {
                if motion.verticalDrift > 0.05, motion.speed > 0.012 {
                    return ("Come", 0.84)
                }
                // Tip clearly below the wrist = pointing at own chest.
                if d.indexTip.y < d.wrist.y - 0.03 {
                    return ("Me", 0.9)
                }
                if motion.lateralSwing > 0.05, motion.speed > 0.01 {
                    return ("Where", 0.9)
                }
                if motion.speed < 0.02 {
                    return ("You", 0.9)
                }
            }

        case .neutral:
            // Two-handed STOP can also land here when the hands sit lower
            // or off to the side of the strict chest band.
            if flatHand, stopContact, hasPerson {
                return ("Stop", 0.9)
            }
            if pointing {
                if motion.lateralSwing > 0.05, motion.speed > 0.01 {
                    return ("Where", 0.91)
                }
                if hasPerson, motion.isPushingOut, !motion.isWaving {
                    return ("Go", 0.83)
                }
                if motion.lateralSwing < 0.05, motion.speed < 0.02 {
                    return ("You", 0.93)
                }
            }
            if vShape {
                // Index+middle snapping down onto the thumb = No.
                if distance(d.indexTip, d.thumbTip) < 0.09 || distance(d.middleTip, d.thumbTip) < 0.09 {
                    return ("No", 0.88)
                }
                return ("Peace", 0.9)
            }
            if callShape {
                return ("Help", 0.88)
            }
            if thumbExt, isFist {
                if d.thumbTip.y > d.wrist.y + 0.05 {
                    return ("Yes", 0.92)
                }
                if d.thumbTip.y < d.wrist.y - 0.03 {
                    return ("No", 0.9)
                }
            }
            if strongFist, !thumbExt, hasPerson {
                return ("Yes", 0.8) // nodding fist, thumb hidden
            }
            if openPalm, hasPerson, motion.isWaving {
                return handRaisedToHead ? ("Hello", 0.93) : ("Goodbye", 0.9)
            }
            if openPalm, hasPerson, motion.isPushingOut {
                return ("Your", 0.84)
            }
        }

        return nil
    }
}
