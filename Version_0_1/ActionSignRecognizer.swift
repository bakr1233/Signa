//
//  ActionSignRecognizer.swift
//  Version_0_1
//
//  Word-level ASL recognition using the LSTM from
//  github.com/nicknochnack/ActionDetectionforSignLanguage (action.h5),
//  converted to CoreML. Classes: hello, thanks, iloveyou.
//
//  The original model consumes MediaPipe Holistic keypoints per frame:
//    [pose 33x(x,y,z,visibility) | face 468x(x,y,z) | left hand 21x(x,y,z) |
//     right hand 21x(x,y,z)] = 1662 values, y-down image coordinates,
//  with zeros for any part that isn't detected. This class rebuilds that
//  exact layout from Apple Vision body-pose + hand-pose observations.
//

import Vision
import CoreML
import Foundation
import CoreGraphics

final class ActionSignRecognizer {

    /// Class order from the notebook: actions = ['hello', 'thanks', 'iloveyou'].
    private let labels = ["Hello", "Thanks", "I love you"]

    private let sequenceLength = 30
    private let featureSize = 1662
    /// Notebook uses ~0.5; require a clear winner with margin so bars don't
    /// lock a wrong class when two signs are close.
    private let confidenceThreshold: Double = 0.58
    private let winnerMargin: Double = 0.12

    private var model: MLModel?
    private var frameBuffer: [[Float]] = []
    /// Consecutive frames with no person at all — reset the window.
    private var emptyFrames = 0

    /// Latest full probability vector, for the on-screen bars.
    private(set) var lastProbabilities: [(String, Double)] = []

    init() {
        if let url = Bundle.main.url(forResource: "ActionSignClassifier", withExtension: "mlmodelc"),
           let m = try? MLModel(contentsOf: url) {
            model = m
        } else {
            print("ActionSignRecognizer: ActionSignClassifier not bundled — action model disabled.")
        }
    }

    var isAvailable: Bool { model != nil }

    func reset() {
        frameBuffer.removeAll()
        emptyFrames = 0
        lastProbabilities = []
    }

    /// Feed one processed frame. Missing parts become zeros exactly like the
    /// original MediaPipe pipeline, so the window keeps filling even when a
    /// hand briefly drops out.
    func ingest(body: VNHumanBodyPoseObservation?,
                hands: [VNHumanHandPoseObservation]) -> (String, Double)? {
        guard model != nil else { return nil }

        if body == nil && hands.isEmpty {
            emptyFrames += 1
            if emptyFrames >= 8 { reset() }
            return nil
        }
        emptyFrames = 0

        frameBuffer.append(Self.holisticVector(body: body, hands: hands))
        if frameBuffer.count > sequenceLength {
            frameBuffer.removeFirst(frameBuffer.count - sequenceLength)
        }
        guard frameBuffer.count == sequenceLength else { return nil }
        return predict()
    }

    // MARK: - Feature construction (MediaPipe Holistic layout)

    /// MediaPipe hand landmark order as Vision joint names.
    private static let handJointOrder: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip
    ]

    private static func holisticVector(body: VNHumanBodyPoseObservation?,
                                       hands: [VNHumanHandPoseObservation]) -> [Float] {
        var v = [Float](repeating: 0, count: 1662)

        var headX: Float = 0
        var headY: Float = 0
        var hasHead = false

        // --- Pose: 33 landmarks × (x, y, z, visibility) = 132 values.
        if let body, let joints = try? body.recognizedPoints(.all) {
            func put(_ mpIndex: Int, _ name: VNHumanBodyPoseObservation.JointName) {
                guard let p = joints[name], p.confidence > 0.1 else { return }
                let base = mpIndex * 4
                v[base] = Float(p.location.x)
                v[base + 1] = Float(1 - p.location.y) // Vision y-up → MediaPipe y-down
                v[base + 2] = 0
                v[base + 3] = min(max(Float(p.confidence), 0), 1)
            }

            put(0, .nose)
            // Inner/outer eye corners approximated by the eye centers.
            put(1, .leftEye); put(2, .leftEye); put(3, .leftEye)
            put(4, .rightEye); put(5, .rightEye); put(6, .rightEye)
            put(7, .leftEar); put(8, .rightEar)
            put(9, .nose); put(10, .nose) // mouth ≈ just below nose
            put(11, .leftShoulder); put(12, .rightShoulder)
            put(13, .leftElbow); put(14, .rightElbow)
            put(15, .leftWrist); put(16, .rightWrist)
            // 17–22 (pinky/index/thumb tips) approximated by the wrists.
            put(17, .leftWrist); put(18, .rightWrist)
            put(19, .leftWrist); put(20, .rightWrist)
            put(21, .leftWrist); put(22, .rightWrist)
            put(23, .leftHip); put(24, .rightHip)
            put(25, .leftKnee); put(26, .rightKnee)
            put(27, .leftAnkle); put(28, .rightAnkle)
            put(29, .leftAnkle); put(30, .rightAnkle)
            put(31, .leftAnkle); put(32, .rightAnkle)

            if let nose = joints[.nose], nose.confidence > 0.1 {
                headX = Float(nose.location.x)
                headY = Float(1 - nose.location.y)
                hasHead = true
            }
        }

        // --- Face: 468 landmarks × (x, y, z) = 1404 values.
        // Vision has no 468-point mesh; a static cloud at the head position is
        // far closer to the training distribution (face nearly still) than zeros.
        if hasHead {
            for i in 0..<468 {
                let base = 132 + i * 3
                v[base] = headX
                v[base + 1] = headY
                v[base + 2] = 0
            }
        }

        // --- Hands: left 21×3 then right 21×3 (anatomical left/right).
        for hand in hands {
            guard let points = try? hand.recognizedPoints(.all) else { continue }
            let offset = hand.chirality == .left ? 1536 : 1599
            for (i, name) in handJointOrder.enumerated() {
                guard let p = points[name], p.confidence > 0.1 else { continue }
                let base = offset + i * 3
                v[base] = Float(p.location.x)
                v[base + 1] = Float(1 - p.location.y)
                v[base + 2] = 0
            }
        }

        return v
    }

    // MARK: - Prediction

    private func predict() -> (String, Double)? {
        guard
            let model,
            let array = try? MLMultiArray(shape: [1, NSNumber(value: sequenceLength), NSNumber(value: featureSize)],
                                          dataType: .float32)
        else { return nil }

        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: sequenceLength * featureSize)
        for (f, frame) in frameBuffer.enumerated() {
            let base = f * featureSize
            for i in 0..<featureSize {
                ptr[base + i] = frame[i]
            }
        }

        guard
            let provider = try? MLDictionaryFeatureProvider(
                dictionary: ["landmarks": MLFeatureValue(multiArray: array)]
            ),
            let result = try? model.prediction(from: provider),
            let probs = result.featureValue(for: "probabilities")?.multiArrayValue
        else { return nil }

        var bestIndex = 0
        var bestValue = -Double.infinity
        var secondValue = -Double.infinity
        var all: [(String, Double)] = []
        for i in 0..<probs.count {
            let value = probs[i].doubleValue
            if labels.indices.contains(i) {
                all.append((labels[i], value))
            }
            if value > bestValue {
                secondValue = bestValue
                bestValue = value
                bestIndex = i
            } else if value > secondValue {
                secondValue = value
            }
        }
        lastProbabilities = all

        guard bestValue >= confidenceThreshold,
              bestValue - secondValue >= winnerMargin,
              labels.indices.contains(bestIndex) else { return nil }
        return (labels[bestIndex], bestValue)
    }
}
