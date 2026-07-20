//
//  SigningAvatar3DView.swift
//  Version_0_1
//
//  3D human-like signing avatar (SceneKit). A jointed humanoid — head,
//  torso, arms, articulated hands — is posed every frame from the same
//  SignAnimationLibrary keyframes used by the 2D avatar, so English→ASL
//  plays back as smooth 3D signing motion.
//

import SwiftUI
import SceneKit

struct SigningAvatar3DView: UIViewRepresentable {
    let signs: [SignEntry]
    let currentIndex: Int
    let isPlaying: Bool
    /// 0...1 progress within the current sign (driven by parent timer).
    let signProgress: Double

    func makeCoordinator() -> AvatarScene {
        AvatarScene()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.antialiasingMode = .multisampling4X
        view.isJitteringEnabled = true
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let english = signs.indices.contains(currentIndex) ? signs[currentIndex].english : ""
        let frames = SignAnimationLibrary.keyframes(for: english)
        let pose = SignAnimationLibrary.interpolate(keyframes: frames, progress: isPlaying ? signProgress : 1)
        context.coordinator.apply(pose: pose)
    }
}

// MARK: - Scene graph

final class AvatarScene {
    let scene = SCNScene()

    // Skin / clothing palette — warmer, more natural.
    private let skin = UIColor(red: 0.90, green: 0.72, blue: 0.58, alpha: 1)
    private let skinShadow = UIColor(red: 0.78, green: 0.58, blue: 0.46, alpha: 1)
    private let shirt = UIColor(red: 0.18, green: 0.42, blue: 0.78, alpha: 1)
    private let pants = UIColor(red: 0.18, green: 0.22, blue: 0.30, alpha: 1)
    private let hairColor = UIColor(red: 0.22, green: 0.14, blue: 0.10, alpha: 1)

    // Fixed body landmarks (world space), derived from the 2D keyframe frame:
    // worldX = (kx - 0.5) * spanX, worldY = spanY * (1 - ky)
    private let spanX: Float = 1.35
    private let spanY: Float = 1.85

    private var lShoulder: SCNVector3 { world(x: 0.36, y: 0.30) }
    private var rShoulder: SCNVector3 { world(x: 0.64, y: 0.30) }

    // Posable nodes.
    private var lUpperArm = SCNNode()
    private var lForearm = SCNNode()
    private var rUpperArm = SCNNode()
    private var rForearm = SCNNode()
    private var lPalm = SCNNode()
    private var rPalm = SCNNode()
    private var lFingers: [SCNNode] = []
    private var rFingers: [SCNNode] = []

    init() {
        buildEnvironment()
        buildBody()
        buildArms()
    }

    private func world(x: Double, y: Double) -> SCNVector3 {
        SCNVector3((Float(x) - 0.5) * spanX, spanY * (1 - Float(y)), 0)
    }

    private func buildEnvironment() {
        let camera = SCNCamera()
        camera.fieldOfView = 32
        camera.wantsHDR = true
        let camNode = SCNNode()
        camNode.camera = camera
        // Slightly pulled back so the signer reads smaller in-frame.
        camNode.position = SCNVector3(0, 1.1, 2.85)
        camNode.look(at: SCNVector3(0, 0.95, 0))
        scene.rootNode.addChildNode(camNode)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 950
        key.light?.castsShadow = true
        key.position = SCNVector3(1.2, 3.2, 2.2)
        key.look(at: SCNVector3(0, 1, 0))
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.intensity = 350
        fill.position = SCNVector3(-1.5, 2.0, 1.5)
        fill.look(at: SCNVector3(0, 1, 0))
        scene.rootNode.addChildNode(fill)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 420
        ambient.light?.color = UIColor(red: 0.95, green: 0.95, blue: 1.0, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let floor = SCNNode(geometry: SCNCylinder(radius: 0.85, height: 0.02))
        floor.geometry?.firstMaterial = material(UIColor(white: 0.22, alpha: 1))
        floor.position = SCNVector3(0, -0.01, 0)
        scene.rootNode.addChildNode(floor)
    }

    private func material(_ color: UIColor, roughness: CGFloat = 0.65) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.lightingModel = .physicallyBased
        m.roughness.contents = roughness
        m.metalness.contents = 0.0
        return m
    }

    private func buildBody() {
        let headCenter = world(x: 0.5, y: 0.15)

        // Slightly elongated head (more human than a perfect ball).
        let head = SCNNode(geometry: SCNSphere(radius: 0.145))
        head.geometry?.firstMaterial = material(skin, roughness: 0.55)
        head.scale = SCNVector3(0.95, 1.08, 0.92)
        head.position = headCenter
        scene.rootNode.addChildNode(head)

        // Jaw / chin soft volume.
        let jaw = SCNNode(geometry: SCNSphere(radius: 0.095))
        jaw.geometry?.firstMaterial = material(skinShadow, roughness: 0.6)
        jaw.scale = SCNVector3(0.95, 0.55, 0.85)
        jaw.position = SCNVector3(headCenter.x, headCenter.y - 0.09, headCenter.z + 0.02)
        scene.rootNode.addChildNode(jaw)

        // Hair cap + fringe.
        let hair = SCNNode(geometry: SCNSphere(radius: 0.155))
        hair.geometry?.firstMaterial = material(hairColor, roughness: 0.85)
        hair.scale = SCNVector3(1.02, 0.78, 1.05)
        hair.position = SCNVector3(headCenter.x, headCenter.y + 0.05, headCenter.z - 0.01)
        scene.rootNode.addChildNode(hair)

        // Ears.
        for side: Float in [-1, 1] {
            let ear = SCNNode(geometry: SCNSphere(radius: 0.032))
            ear.geometry?.firstMaterial = material(skinShadow, roughness: 0.6)
            ear.scale = SCNVector3(0.55, 1.0, 0.7)
            ear.position = SCNVector3(headCenter.x + side * 0.14, headCenter.y, headCenter.z)
            scene.rootNode.addChildNode(ear)
        }

        // Eyes with white sclera + dark iris.
        for side: Float in [-1, 1] {
            let white = SCNNode(geometry: SCNSphere(radius: 0.022))
            white.geometry?.firstMaterial = material(.white, roughness: 0.25)
            white.position = SCNVector3(headCenter.x + side * 0.048, headCenter.y + 0.015, headCenter.z + 0.12)
            scene.rootNode.addChildNode(white)

            let iris = SCNNode(geometry: SCNSphere(radius: 0.012))
            iris.geometry?.firstMaterial = material(UIColor(red: 0.2, green: 0.28, blue: 0.4, alpha: 1), roughness: 0.2)
            iris.position = SCNVector3(headCenter.x + side * 0.048, headCenter.y + 0.015, headCenter.z + 0.138)
            scene.rootNode.addChildNode(iris)

            let brow = SCNNode(geometry: SCNCapsule(capRadius: 0.006, height: 0.045))
            brow.geometry?.firstMaterial = material(hairColor, roughness: 0.9)
            brow.eulerAngles.z = .pi / 2
            brow.position = SCNVector3(headCenter.x + side * 0.048, headCenter.y + 0.045, headCenter.z + 0.125)
            scene.rootNode.addChildNode(brow)
        }

        // Nose.
        let nose = SCNNode(geometry: SCNSphere(radius: 0.022))
        nose.geometry?.firstMaterial = material(skinShadow, roughness: 0.55)
        nose.scale = SCNVector3(0.7, 0.9, 1.1)
        nose.position = SCNVector3(headCenter.x, headCenter.y - 0.02, headCenter.z + 0.14)
        scene.rootNode.addChildNode(nose)

        // Mouth.
        let mouth = SCNNode(geometry: SCNCapsule(capRadius: 0.007, height: 0.045))
        mouth.geometry?.firstMaterial = material(UIColor(red: 0.72, green: 0.32, blue: 0.35, alpha: 1), roughness: 0.4)
        mouth.eulerAngles.z = .pi / 2
        mouth.position = SCNVector3(headCenter.x, headCenter.y - 0.07, headCenter.z + 0.125)
        scene.rootNode.addChildNode(mouth)

        // Neck.
        let neck = SCNNode(geometry: SCNCylinder(radius: 0.052, height: 0.11))
        neck.geometry?.firstMaterial = material(skin, roughness: 0.55)
        neck.position = SCNVector3(0, headCenter.y - 0.19, 0)
        scene.rootNode.addChildNode(neck)

        // Broader torso (shirt).
        let torso = SCNNode(geometry: SCNCapsule(capRadius: 0.24, height: 0.72))
        torso.geometry?.firstMaterial = material(shirt, roughness: 0.75)
        torso.position = SCNVector3(0, (lShoulder.y + world(x: 0.5, y: 0.55).y) / 2, 0)
        torso.scale = SCNVector3(1.05, 1, 0.68)
        scene.rootNode.addChildNode(torso)

        // Shoulders.
        for p in [lShoulder, rShoulder] {
            let s = SCNNode(geometry: SCNSphere(radius: 0.085))
            s.geometry?.firstMaterial = material(shirt, roughness: 0.75)
            s.position = p
            scene.rootNode.addChildNode(s)
        }

        // Legs — thicker, more natural.
        let hipY = world(x: 0.5, y: 0.55).y
        for side: Float in [-1, 1] {
            let leg = SCNNode(geometry: SCNCapsule(capRadius: 0.085, height: CGFloat(hipY) + 0.02))
            leg.geometry?.firstMaterial = material(pants, roughness: 0.8)
            leg.position = SCNVector3(side * 0.12, hipY / 2 - 0.02, 0)
            scene.rootNode.addChildNode(leg)

            let shoe = SCNNode(geometry: SCNCapsule(capRadius: 0.055, height: 0.2))
            shoe.geometry?.firstMaterial = material(.black, roughness: 0.5)
            shoe.eulerAngles.x = .pi / 2
            shoe.position = SCNVector3(side * 0.12, 0.04, 0.06)
            scene.rootNode.addChildNode(shoe)
        }
    }

    private func buildArms() {
        func segment(_ radius: CGFloat, _ color: UIColor) -> SCNNode {
            let node = SCNNode(geometry: SCNCylinder(radius: radius, height: 1))
            node.geometry?.firstMaterial = material(color, roughness: 0.6)
            scene.rootNode.addChildNode(node)
            return node
        }

        // Thicker arms so they read as human limbs, not sticks.
        lUpperArm = segment(0.062, shirt)
        rUpperArm = segment(0.062, shirt)
        lForearm = segment(0.05, skin)
        rForearm = segment(0.05, skin)

        lPalm = SCNNode(geometry: SCNSphere(radius: 0.068))
        rPalm = SCNNode(geometry: SCNSphere(radius: 0.068))
        for palm in [lPalm, rPalm] {
            palm.geometry?.firstMaterial = material(skin, roughness: 0.55)
            scene.rootNode.addChildNode(palm)
        }

        lFingers = (0..<5).map { _ in segment(0.018, skin) }
        rFingers = (0..<5).map { _ in segment(0.018, skin) }
    }

    // MARK: - Posing

    func apply(pose: SignKeyframe) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.06

        let lElbow = world(x: pose.leftElbow.x, y: pose.leftElbow.y)
        let lWrist = world(x: pose.leftWrist.x, y: pose.leftWrist.y)
        let rElbow = world(x: pose.rightElbow.x, y: pose.rightElbow.y)
        let rWrist = world(x: pose.rightWrist.x, y: pose.rightWrist.y)

        // Bring forearms slightly forward so signing happens in front of the body.
        let lElbowF = SCNVector3(lElbow.x, lElbow.y, 0.16)
        let lWristF = SCNVector3(lWrist.x, lWrist.y, 0.26)
        let rElbowF = SCNVector3(rElbow.x, rElbow.y, 0.16)
        let rWristF = SCNVector3(rWrist.x, rWrist.y, 0.26)

        place(lUpperArm, from: lShoulder, to: lElbowF)
        place(lForearm, from: lElbowF, to: lWristF)
        place(rUpperArm, from: rShoulder, to: rElbowF)
        place(rForearm, from: rElbowF, to: rWristF)

        lPalm.position = lWristF
        rPalm.position = rWristF

        pose3DFingers(lFingers, wrist: lWristF, elbow: lElbowF, shape: pose.leftHand)
        pose3DFingers(rFingers, wrist: rWristF, elbow: rElbowF, shape: pose.rightHand)

        SCNTransaction.commit()
    }

    /// Positions a unit cylinder between two points.
    private func place(_ node: SCNNode, from a: SCNVector3, to b: SCNVector3) {
        let av = simd_float3(a.x, a.y, a.z)
        let bv = simd_float3(b.x, b.y, b.z)
        let delta = bv - av
        let length = max(simd_length(delta), 0.001)

        node.simdPosition = (av + bv) / 2
        node.scale = SCNVector3(1, length, 1)

        let up = simd_float3(0, 1, 0)
        let dir = delta / length
        if simd_length(simd_cross(up, dir)) < 0.0001 {
            node.simdOrientation = dir.y > 0
                ? simd_quatf(angle: 0, axis: up)
                : simd_quatf(angle: .pi, axis: simd_float3(1, 0, 0))
        } else {
            node.simdOrientation = simd_quatf(from: up, to: dir)
        }
    }

    /// Same (along, side) finger layout as the 2D avatar, applied in the arm plane.
    private func pose3DFingers(_ nodes: [SCNNode], wrist: SCNVector3, elbow: SCNVector3, shape: SignHandShape) {
        let offsets: [(CGFloat, CGFloat)]
        switch shape {
        case .open:      offsets = [(3.2, -1.6), (3.6, -0.5), (3.6, 0.5), (3.2, 1.6), (2.2, -2.2)]
        case .fist:      offsets = [(1.2, -1.0), (1.2, -0.3), (1.2, 0.3), (1.2, 1.0)]
        case .point:     offsets = [(3.8, 0), (1.2, -0.8), (1.2, 0.8), (1.1, 1.4)]
        case .thumbUp:   offsets = [(1.2, -0.8), (1.2, 0), (1.2, 0.8), (2.8, -2.2)]
        case .thumbDown: offsets = [(1.2, -0.8), (1.2, 0), (1.2, 0.8), (2.8, 2.2)]
        case .peace:     offsets = [(3.8, -0.7), (3.8, 0.7), (1.2, 1.2), (1.1, 1.8)]
        case .ok:        offsets = [(2.0, -1.2), (3.4, 0.4), (3.4, 1.2), (3.0, 1.8)]
        case .ily:       offsets = [(3.6, -1.5), (1.2, -0.3), (1.2, 0.5), (3.6, 1.5), (2.6, -2.2)]
        case .call:      offsets = [(2.8, -2.0), (1.2, -0.4), (1.2, 0.4), (2.8, 2.0)]
        }

        let scale: Float = 0.05
        let w = simd_float3(wrist.x, wrist.y, wrist.z)
        let e = simd_float3(elbow.x, elbow.y, elbow.z)
        var u = w - e
        let len = max(simd_length(u), 0.001)
        u /= len
        // Perpendicular within the mostly-vertical arm plane (facing the camera).
        let camera = simd_float3(0, 0, 1)
        var p = simd_cross(u, camera)
        if simd_length(p) < 0.001 { p = simd_float3(1, 0, 0) }
        p = simd_normalize(p)

        for (i, node) in nodes.enumerated() {
            guard i < offsets.count else {
                node.isHidden = true
                continue
            }
            node.isHidden = false
            let (along, side) = offsets[i]
            let tip = w + u * Float(along) * scale + p * Float(side) * scale
            place(node,
                  from: SCNVector3(w.x, w.y, w.z),
                  to: SCNVector3(tip.x, tip.y, tip.z))
        }
    }
}

#Preview {
    SigningAvatar3DView(
        signs: [
            SignEntry(english: "hello", aslGloss: "HELLO", description: "Wave", symbolName: "hand.wave", contributor: "Signa", isUserContributed: false)
        ],
        currentIndex: 0,
        isPlaying: true,
        signProgress: 0.5
    )
    .frame(width: 240, height: 340)
    .padding()
}
