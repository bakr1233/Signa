//
//  SigningAvatarView.swift
//  Version_0_1
//
//  2D skeletal signer that interpolates hand/arm keyframes so English→ASL
//  plays back as motion, not static SF Symbols.
//

import SwiftUI

enum SignHandShape: String, Codable, Hashable {
    case open, fist, point, thumbUp, thumbDown, peace, ok, ily, call
}

struct Point2D: Codable, Equatable, Hashable {
    var x: Double
    var y: Double

    var cg: CGPoint { CGPoint(x: x, y: y) }

    static func lerp(_ a: Point2D, _ b: Point2D, _ t: Double) -> Point2D {
        Point2D(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

struct SignKeyframe: Codable, Equatable, Hashable {
    /// 0...1 within one sign.
    var t: Double
    var leftElbow: Point2D
    var leftWrist: Point2D
    var rightElbow: Point2D
    var rightWrist: Point2D
    var leftHand: SignHandShape
    var rightHand: SignHandShape
}

enum SignAnimationLibrary {
    /// Rest pose (arms down at sides).
    static let rest: SignKeyframe = SignKeyframe(
        t: 0,
        leftElbow: Point2D(x: 0.32, y: 0.48),
        leftWrist: Point2D(x: 0.28, y: 0.68),
        rightElbow: Point2D(x: 0.68, y: 0.48),
        rightWrist: Point2D(x: 0.72, y: 0.68),
        leftHand: .open,
        rightHand: .open
    )

    static func keyframes(for english: String) -> [SignKeyframe] {
        switch english.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "hello", "hi":
            return wave(shape: .open)
        case "goodbye", "bye":
            return wave(shape: .open, higher: false)
        case "yes":
            return [
                rest,
                SignKeyframe(t: 0.35, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.62, y: 0.42), rightWrist: Point2D(x: 0.58, y: 0.28),
                             leftHand: .fist, rightHand: .thumbUp),
                SignKeyframe(t: 0.7, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.62, y: 0.44), rightWrist: Point2D(x: 0.58, y: 0.34),
                             leftHand: .fist, rightHand: .thumbUp),
                SignKeyframe(t: 1.0, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.62, y: 0.42), rightWrist: Point2D(x: 0.58, y: 0.28),
                             leftHand: .fist, rightHand: .thumbUp)
            ]
        case "no":
            return [
                rest,
                SignKeyframe(t: 0.4, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.64, y: 0.45), rightWrist: Point2D(x: 0.60, y: 0.55),
                             leftHand: .open, rightHand: .thumbDown),
                SignKeyframe(t: 1.0, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.64, y: 0.45), rightWrist: Point2D(x: 0.56, y: 0.58),
                             leftHand: .open, rightHand: .thumbDown)
            ]
        case "you":
            return [
                rest,
                SignKeyframe(t: 0.45, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.60, y: 0.40), rightWrist: Point2D(x: 0.52, y: 0.32),
                             leftHand: .open, rightHand: .point),
                SignKeyframe(t: 1.0, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.60, y: 0.40), rightWrist: Point2D(x: 0.48, y: 0.30),
                             leftHand: .open, rightHand: .point)
            ]
        case "where":
            return [
                rest,
                SignKeyframe(t: 0.3, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.60, y: 0.40), rightWrist: Point2D(x: 0.56, y: 0.30),
                             leftHand: .open, rightHand: .point),
                SignKeyframe(t: 0.55, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.60, y: 0.40), rightWrist: Point2D(x: 0.46, y: 0.30),
                             leftHand: .open, rightHand: .point),
                SignKeyframe(t: 0.8, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.60, y: 0.40), rightWrist: Point2D(x: 0.56, y: 0.30),
                             leftHand: .open, rightHand: .point),
                SignKeyframe(t: 1.0, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.60, y: 0.40), rightWrist: Point2D(x: 0.48, y: 0.30),
                             leftHand: .open, rightHand: .point)
            ]
        case "water":
            return [
                rest,
                SignKeyframe(t: 0.4, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.58, y: 0.36), rightWrist: Point2D(x: 0.50, y: 0.22),
                             leftHand: .open, rightHand: .open),
                SignKeyframe(t: 0.7, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.58, y: 0.36), rightWrist: Point2D(x: 0.50, y: 0.20),
                             leftHand: .open, rightHand: .open),
                SignKeyframe(t: 1.0, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.58, y: 0.36), rightWrist: Point2D(x: 0.50, y: 0.22),
                             leftHand: .open, rightHand: .open)
            ]
        case "eat":
            return [
                rest,
                SignKeyframe(t: 0.35, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.58, y: 0.36), rightWrist: Point2D(x: 0.50, y: 0.20),
                             leftHand: .open, rightHand: .ok),
                SignKeyframe(t: 0.7, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.58, y: 0.38), rightWrist: Point2D(x: 0.50, y: 0.26),
                             leftHand: .open, rightHand: .ok),
                SignKeyframe(t: 1.0, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.58, y: 0.36), rightWrist: Point2D(x: 0.50, y: 0.20),
                             leftHand: .open, rightHand: .ok)
            ]
        case "thanks", "thank", "thank you":
            return [
                rest,
                SignKeyframe(t: 0.35, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.58, y: 0.36), rightWrist: Point2D(x: 0.50, y: 0.22),
                             leftHand: .open, rightHand: .open),
                SignKeyframe(t: 1.0, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.60, y: 0.42), rightWrist: Point2D(x: 0.55, y: 0.48),
                             leftHand: .open, rightHand: .open)
            ]
        case "please":
            return [
                rest,
                SignKeyframe(t: 0.3, leftElbow: Point2D(x: 0.38, y: 0.42), leftWrist: Point2D(x: 0.45, y: 0.40),
                             rightElbow: rest.rightElbow, rightWrist: rest.rightWrist,
                             leftHand: .open, rightHand: .open),
                SignKeyframe(t: 0.65, leftElbow: Point2D(x: 0.40, y: 0.42), leftWrist: Point2D(x: 0.52, y: 0.42),
                             rightElbow: rest.rightElbow, rightWrist: rest.rightWrist,
                             leftHand: .open, rightHand: .open),
                SignKeyframe(t: 1.0, leftElbow: Point2D(x: 0.38, y: 0.42), leftWrist: Point2D(x: 0.45, y: 0.40),
                             rightElbow: rest.rightElbow, rightWrist: rest.rightWrist,
                             leftHand: .open, rightHand: .open)
            ]
        case "sorry":
            return [
                rest,
                SignKeyframe(t: 0.4, leftElbow: Point2D(x: 0.40, y: 0.42), leftWrist: Point2D(x: 0.48, y: 0.38),
                             rightElbow: rest.rightElbow, rightWrist: rest.rightWrist,
                             leftHand: .fist, rightHand: .open),
                SignKeyframe(t: 0.75, leftElbow: Point2D(x: 0.42, y: 0.42), leftWrist: Point2D(x: 0.52, y: 0.40),
                             rightElbow: rest.rightElbow, rightWrist: rest.rightWrist,
                             leftHand: .fist, rightHand: .open),
                SignKeyframe(t: 1.0, leftElbow: Point2D(x: 0.40, y: 0.42), leftWrist: Point2D(x: 0.48, y: 0.38),
                             rightElbow: rest.rightElbow, rightWrist: rest.rightWrist,
                             leftHand: .fist, rightHand: .open)
            ]
        case "i love you", "love":
            return [
                rest,
                SignKeyframe(t: 0.5, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.60, y: 0.38), rightWrist: Point2D(x: 0.52, y: 0.26),
                             leftHand: .open, rightHand: .ily),
                SignKeyframe(t: 1.0, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.60, y: 0.38), rightWrist: Point2D(x: 0.52, y: 0.26),
                             leftHand: .open, rightHand: .ily)
            ]
        case "help":
            return [
                rest,
                SignKeyframe(t: 0.45, leftElbow: Point2D(x: 0.38, y: 0.46), leftWrist: Point2D(x: 0.46, y: 0.44),
                             rightElbow: Point2D(x: 0.58, y: 0.40), rightWrist: Point2D(x: 0.50, y: 0.36),
                             leftHand: .open, rightHand: .fist),
                SignKeyframe(t: 1.0, leftElbow: Point2D(x: 0.38, y: 0.40), leftWrist: Point2D(x: 0.46, y: 0.34),
                             rightElbow: Point2D(x: 0.58, y: 0.34), rightWrist: Point2D(x: 0.50, y: 0.28),
                             leftHand: .open, rightHand: .fist)
            ]
        case "ok":
            return [
                rest,
                SignKeyframe(t: 0.5, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.62, y: 0.40), rightWrist: Point2D(x: 0.54, y: 0.30),
                             leftHand: .open, rightHand: .ok),
                SignKeyframe(t: 1.0, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.62, y: 0.40), rightWrist: Point2D(x: 0.54, y: 0.30),
                             leftHand: .open, rightHand: .ok)
            ]
        case "peace":
            return [
                rest,
                SignKeyframe(t: 0.5, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.62, y: 0.40), rightWrist: Point2D(x: 0.54, y: 0.28),
                             leftHand: .open, rightHand: .peace),
                SignKeyframe(t: 1.0, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.62, y: 0.40), rightWrist: Point2D(x: 0.54, y: 0.28),
                             leftHand: .open, rightHand: .peace)
            ]

        // MY — flat palm presses the chest (was incorrectly a generic open hand).
        case "my":
            return [
                rest,
                SignKeyframe(t: 0.35, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.58, y: 0.40), rightWrist: Point2D(x: 0.50, y: 0.42),
                             leftHand: .open, rightHand: .open),
                SignKeyframe(t: 0.7, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.56, y: 0.40), rightWrist: Point2D(x: 0.48, y: 0.44),
                             leftHand: .open, rightHand: .open),
                SignKeyframe(t: 1.0, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.58, y: 0.40), rightWrist: Point2D(x: 0.50, y: 0.42),
                             leftHand: .open, rightHand: .open)
            ]

        // NAME — both H-hands (index+middle = peace shape) tap twice at center.
        case "name":
            return [
                rest,
                SignKeyframe(t: 0.25,
                             leftElbow: Point2D(x: 0.40, y: 0.40), leftWrist: Point2D(x: 0.46, y: 0.36),
                             rightElbow: Point2D(x: 0.60, y: 0.40), rightWrist: Point2D(x: 0.54, y: 0.36),
                             leftHand: .peace, rightHand: .peace),
                SignKeyframe(t: 0.45,
                             leftElbow: Point2D(x: 0.40, y: 0.40), leftWrist: Point2D(x: 0.48, y: 0.38),
                             rightElbow: Point2D(x: 0.60, y: 0.40), rightWrist: Point2D(x: 0.52, y: 0.38),
                             leftHand: .peace, rightHand: .peace),
                SignKeyframe(t: 0.65,
                             leftElbow: Point2D(x: 0.40, y: 0.40), leftWrist: Point2D(x: 0.46, y: 0.36),
                             rightElbow: Point2D(x: 0.60, y: 0.40), rightWrist: Point2D(x: 0.54, y: 0.36),
                             leftHand: .peace, rightHand: .peace),
                SignKeyframe(t: 0.85,
                             leftElbow: Point2D(x: 0.40, y: 0.40), leftWrist: Point2D(x: 0.48, y: 0.38),
                             rightElbow: Point2D(x: 0.60, y: 0.40), rightWrist: Point2D(x: 0.52, y: 0.38),
                             leftHand: .peace, rightHand: .peace),
                SignKeyframe(t: 1.0,
                             leftElbow: Point2D(x: 0.40, y: 0.40), leftWrist: Point2D(x: 0.46, y: 0.36),
                             rightElbow: Point2D(x: 0.60, y: 0.40), rightWrist: Point2D(x: 0.54, y: 0.36),
                             leftHand: .peace, rightHand: .peace)
            ]

        case "i", "me":
            return [
                rest,
                SignKeyframe(t: 0.45, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.58, y: 0.40), rightWrist: Point2D(x: 0.50, y: 0.42),
                             leftHand: .open, rightHand: .point),
                SignKeyframe(t: 1.0, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.58, y: 0.40), rightWrist: Point2D(x: 0.48, y: 0.44),
                             leftHand: .open, rightHand: .point)
            ]

        case "your", "his", "her":
            return [
                rest,
                SignKeyframe(t: 0.5, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.60, y: 0.40), rightWrist: Point2D(x: 0.55, y: 0.32),
                             leftHand: .open, rightHand: .open),
                SignKeyframe(t: 1.0, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.62, y: 0.40), rightWrist: Point2D(x: 0.58, y: 0.30),
                             leftHand: .open, rightHand: .open)
            ]

        case "how":
            return [
                rest,
                SignKeyframe(t: 0.4,
                             leftElbow: Point2D(x: 0.40, y: 0.42), leftWrist: Point2D(x: 0.46, y: 0.40),
                             rightElbow: Point2D(x: 0.60, y: 0.42), rightWrist: Point2D(x: 0.54, y: 0.40),
                             leftHand: .fist, rightHand: .fist),
                SignKeyframe(t: 1.0,
                             leftElbow: Point2D(x: 0.38, y: 0.40), leftWrist: Point2D(x: 0.44, y: 0.36),
                             rightElbow: Point2D(x: 0.62, y: 0.40), rightWrist: Point2D(x: 0.56, y: 0.36),
                             leftHand: .fist, rightHand: .fist)
            ]

        case "what":
            return [
                rest,
                SignKeyframe(t: 0.35,
                             leftElbow: Point2D(x: 0.36, y: 0.44), leftWrist: Point2D(x: 0.32, y: 0.50),
                             rightElbow: Point2D(x: 0.64, y: 0.44), rightWrist: Point2D(x: 0.68, y: 0.50),
                             leftHand: .open, rightHand: .open),
                SignKeyframe(t: 0.7,
                             leftElbow: Point2D(x: 0.38, y: 0.44), leftWrist: Point2D(x: 0.34, y: 0.48),
                             rightElbow: Point2D(x: 0.62, y: 0.44), rightWrist: Point2D(x: 0.66, y: 0.48),
                             leftHand: .open, rightHand: .open),
                SignKeyframe(t: 1.0,
                             leftElbow: Point2D(x: 0.36, y: 0.44), leftWrist: Point2D(x: 0.32, y: 0.50),
                             rightElbow: Point2D(x: 0.64, y: 0.44), rightWrist: Point2D(x: 0.68, y: 0.50),
                             leftHand: .open, rightHand: .open)
            ]

        case "good":
            return [
                rest,
                SignKeyframe(t: 0.35, leftElbow: Point2D(x: 0.40, y: 0.42), leftWrist: Point2D(x: 0.48, y: 0.48),
                             rightElbow: Point2D(x: 0.58, y: 0.36), rightWrist: Point2D(x: 0.50, y: 0.22),
                             leftHand: .open, rightHand: .open),
                SignKeyframe(t: 1.0, leftElbow: Point2D(x: 0.40, y: 0.42), leftWrist: Point2D(x: 0.48, y: 0.48),
                             rightElbow: Point2D(x: 0.56, y: 0.42), rightWrist: Point2D(x: 0.50, y: 0.46),
                             leftHand: .open, rightHand: .open)
            ]

        case "friend", "meet":
            return [
                rest,
                SignKeyframe(t: 0.4,
                             leftElbow: Point2D(x: 0.40, y: 0.40), leftWrist: Point2D(x: 0.46, y: 0.36),
                             rightElbow: Point2D(x: 0.60, y: 0.40), rightWrist: Point2D(x: 0.54, y: 0.36),
                             leftHand: .point, rightHand: .point),
                SignKeyframe(t: 1.0,
                             leftElbow: Point2D(x: 0.42, y: 0.40), leftWrist: Point2D(x: 0.48, y: 0.38),
                             rightElbow: Point2D(x: 0.58, y: 0.40), rightWrist: Point2D(x: 0.52, y: 0.38),
                             leftHand: .point, rightHand: .point)
            ]

        case "drink":
            return [
                rest,
                SignKeyframe(t: 0.45, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.58, y: 0.36), rightWrist: Point2D(x: 0.50, y: 0.22),
                             leftHand: .open, rightHand: .call),
                SignKeyframe(t: 1.0, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                             rightElbow: Point2D(x: 0.58, y: 0.34), rightWrist: Point2D(x: 0.50, y: 0.18),
                             leftHand: .open, rightHand: .call)
            ]

        case "stop", "finish":
            return [
                rest,
                SignKeyframe(t: 0.4,
                             leftElbow: Point2D(x: 0.40, y: 0.44), leftWrist: Point2D(x: 0.48, y: 0.48),
                             rightElbow: Point2D(x: 0.58, y: 0.34), rightWrist: Point2D(x: 0.50, y: 0.28),
                             leftHand: .open, rightHand: .open),
                SignKeyframe(t: 1.0,
                             leftElbow: Point2D(x: 0.40, y: 0.44), leftWrist: Point2D(x: 0.48, y: 0.48),
                             rightElbow: Point2D(x: 0.56, y: 0.42), rightWrist: Point2D(x: 0.50, y: 0.46),
                             leftHand: .open, rightHand: .open)
            ]

        case "happy", "fine", "nice":
            return genericEmphasize(rightShape: .open)
        case "sad", "tired", "hungry", "sleep":
            return genericEmphasize(rightShape: .fist)
        case "know", "understand", "see", "look", "why", "who", "when",
             "mother", "father", "boy", "girl", "man", "woman",
             "school", "work", "home", "book", "today", "tomorrow", "yesterday",
             "now", "later", "again", "bathroom", "want", "need", "like", "more",
             "go", "come", "our", "are", "bad", "family", "morning", "night",
             "yes please", "no thanks", "what's your name":
            return genericEmphasize(rightShape: .open)

        default:
            // Distinct fingerspell pose per letter so B-A-K-R don't all look identical.
            if english.count == 1, let ch = english.lowercased().first {
                return fingerspell(ch)
            }
            return genericEmphasize(rightShape: .open)
        }
    }

    /// Per-letter fingerspelling pose (simplified ASL alphabet shapes).
    private static func fingerspell(_ ch: Character) -> [SignKeyframe] {
        let shape: SignHandShape
        switch ch {
        case "a", "e", "m", "n", "s", "t": shape = .fist
        case "b", "4", "5": shape = .open
        case "c", "o": shape = .call
        case "d", "g", "l", "x", "1": shape = .point
        case "f", "9": shape = .ok
        case "h", "k", "p", "r", "u", "v", "2": shape = .peace
        case "i", "j", "y": shape = .ily
        case "w", "3": shape = .open
        case "q", "z": shape = .point
        default: shape = .point
        }
        // Slight horizontal offset per letter so the sequence reads as motion.
        let nudge = Double((ch.asciiValue ?? 97) % 5) * 0.012 - 0.024
        return [
            rest,
            SignKeyframe(t: 0.35, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                         rightElbow: Point2D(x: 0.60, y: 0.38), rightWrist: Point2D(x: 0.52 + nudge, y: 0.28),
                         leftHand: .open, rightHand: shape),
            SignKeyframe(t: 0.7, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                         rightElbow: Point2D(x: 0.60, y: 0.38), rightWrist: Point2D(x: 0.52 + nudge, y: 0.26),
                         leftHand: .open, rightHand: shape),
            SignKeyframe(t: 1.0, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                         rightElbow: Point2D(x: 0.60, y: 0.40), rightWrist: Point2D(x: 0.52 + nudge, y: 0.30),
                         leftHand: .open, rightHand: shape)
        ]
    }

    private static func wave(shape: SignHandShape, higher: Bool = true) -> [SignKeyframe] {
        let yBase: Double = higher ? 0.24 : 0.34
        return [
            rest,
            SignKeyframe(t: 0.25, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                         rightElbow: Point2D(x: 0.64, y: 0.36), rightWrist: Point2D(x: 0.70, y: yBase),
                         leftHand: .open, rightHand: shape),
            SignKeyframe(t: 0.5, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                         rightElbow: Point2D(x: 0.64, y: 0.36), rightWrist: Point2D(x: 0.58, y: yBase + 0.02),
                         leftHand: .open, rightHand: shape),
            SignKeyframe(t: 0.75, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                         rightElbow: Point2D(x: 0.64, y: 0.36), rightWrist: Point2D(x: 0.72, y: yBase),
                         leftHand: .open, rightHand: shape),
            SignKeyframe(t: 1.0, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                         rightElbow: Point2D(x: 0.64, y: 0.36), rightWrist: Point2D(x: 0.62, y: yBase + 0.02),
                         leftHand: .open, rightHand: shape)
        ]
    }

    private static func genericEmphasize(rightShape: SignHandShape) -> [SignKeyframe] {
        [
            rest,
            SignKeyframe(t: 0.45, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                         rightElbow: Point2D(x: 0.60, y: 0.40), rightWrist: Point2D(x: 0.50, y: 0.32),
                         leftHand: .open, rightHand: rightShape),
            SignKeyframe(t: 1.0, leftElbow: rest.leftElbow, leftWrist: rest.leftWrist,
                         rightElbow: Point2D(x: 0.60, y: 0.42), rightWrist: Point2D(x: 0.52, y: 0.36),
                         leftHand: .open, rightHand: rightShape)
        ]
    }

    static func interpolate(keyframes: [SignKeyframe], progress: Double) -> SignKeyframe {
        let frames = keyframes.sorted { $0.t < $1.t }
        guard let first = frames.first else { return rest }
        guard frames.count > 1 else { return first }
        let p = min(1, max(0, progress))
        if p <= first.t { return first }
        if p >= frames.last!.t { return frames.last! }
        for i in 0..<(frames.count - 1) {
            let a = frames[i]
            let b = frames[i + 1]
            if p >= a.t && p <= b.t {
                let local = b.t > a.t ? (p - a.t) / (b.t - a.t) : 1
                let ease = local * local * (3 - 2 * local) // smoothstep
                return SignKeyframe(
                    t: p,
                    leftElbow: Point2D.lerp(a.leftElbow, b.leftElbow, ease),
                    leftWrist: Point2D.lerp(a.leftWrist, b.leftWrist, ease),
                    rightElbow: Point2D.lerp(a.rightElbow, b.rightElbow, ease),
                    rightWrist: Point2D.lerp(a.rightWrist, b.rightWrist, ease),
                    leftHand: ease < 0.5 ? a.leftHand : b.leftHand,
                    rightHand: ease < 0.5 ? a.rightHand : b.rightHand
                )
            }
        }
        return frames.last!
    }
}

struct SigningAvatarView: View {
    let signs: [SignEntry]
    let currentIndex: Int
    let isPlaying: Bool
    /// 0...1 progress within the current sign (driven by parent timer).
    let signProgress: Double

    var body: some View {
        let english = signs.indices.contains(currentIndex) ? signs[currentIndex].english : ""
        let frames = SignAnimationLibrary.keyframes(for: english)
        let pose = SignAnimationLibrary.interpolate(keyframes: frames, progress: isPlaying ? signProgress : 1)

        Canvas { context, size in
            drawAvatar(context: context, size: size, pose: pose)
        }
        .aspectRatio(0.72, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        )
        .animation(.linear(duration: 0.04), value: signProgress)
    }

    private func drawAvatar(context: GraphicsContext, size: CGSize, pose: SignKeyframe) {
        let w = size.width
        let h = size.height

        func P(_ p: Point2D) -> CGPoint {
            CGPoint(x: p.x * w, y: p.y * h)
        }

        // Soft ground
        var ground = Path()
        ground.addEllipse(in: CGRect(x: w * 0.2, y: h * 0.88, width: w * 0.6, height: h * 0.06))
        context.fill(ground, with: .color(.secondary.opacity(0.12)))

        let neck = CGPoint(x: w * 0.5, y: h * 0.28)
        let hip = CGPoint(x: w * 0.5, y: h * 0.55)
        let headCenter = CGPoint(x: w * 0.5, y: h * 0.16)
        let lShoulder = CGPoint(x: w * 0.38, y: h * 0.30)
        let rShoulder = CGPoint(x: w * 0.62, y: h * 0.30)

        // Torso
        stroke(context, from: neck, to: hip, width: 10, color: .accentColor.opacity(0.85))
        stroke(context, from: lShoulder, to: rShoulder, width: 8, color: .accentColor.opacity(0.75))

        // Head
        let headRect = CGRect(x: headCenter.x - w * 0.08, y: headCenter.y - w * 0.08,
                              width: w * 0.16, height: w * 0.16)
        context.fill(Path(ellipseIn: headRect), with: .color(.accentColor.opacity(0.9)))

        // Arms
        let lElbow = P(pose.leftElbow)
        let lWrist = P(pose.leftWrist)
        let rElbow = P(pose.rightElbow)
        let rWrist = P(pose.rightWrist)

        stroke(context, from: lShoulder, to: lElbow, width: 7, color: .accentColor)
        stroke(context, from: lElbow, to: lWrist, width: 6, color: .accentColor)
        stroke(context, from: rShoulder, to: rElbow, width: 7, color: .accentColor)
        stroke(context, from: rElbow, to: rWrist, width: 6, color: .accentColor)

        drawHand(context: context, at: lWrist, toward: lElbow, shape: pose.leftHand, size: w)
        drawHand(context: context, at: rWrist, toward: rElbow, shape: pose.rightHand, size: w)

        // Legs (static)
        stroke(context, from: hip, to: CGPoint(x: w * 0.42, y: h * 0.86), width: 7, color: .accentColor.opacity(0.7))
        stroke(context, from: hip, to: CGPoint(x: w * 0.58, y: h * 0.86), width: 7, color: .accentColor.opacity(0.7))
    }

    private func stroke(_ context: GraphicsContext, from: CGPoint, to: CGPoint, width: CGFloat, color: Color) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private func drawHand(context: GraphicsContext, at wrist: CGPoint, toward elbow: CGPoint, shape: SignHandShape, size: CGFloat) {
        let scale = size * 0.035
        let dx = wrist.x - elbow.x
        let dy = wrist.y - elbow.y
        let len = max(hypot(dx, dy), 1)
        let ux = dx / len
        let uy = dy / len
        let px = -uy
        let py = ux

        func tip(_ along: CGFloat, _ side: CGFloat) -> CGPoint {
            CGPoint(x: wrist.x + ux * along * scale + px * side * scale,
                    y: wrist.y + uy * along * scale + py * side * scale)
        }

        let palm = CGRect(x: wrist.x - scale * 1.1, y: wrist.y - scale * 1.1, width: scale * 2.2, height: scale * 2.2)
        context.fill(Path(ellipseIn: palm), with: .color(.accentColor))

        let fingers: [(CGFloat, CGFloat)]
        switch shape {
        case .open:
            fingers = [(3.2, -1.6), (3.6, -0.5), (3.6, 0.5), (3.2, 1.6), (2.2, -2.2)]
        case .fist:
            fingers = [(1.2, -1.0), (1.2, -0.3), (1.2, 0.3), (1.2, 1.0)]
        case .point:
            fingers = [(3.8, 0), (1.2, -0.8), (1.2, 0.8), (1.1, 1.4)]
        case .thumbUp:
            fingers = [(1.2, -0.8), (1.2, 0), (1.2, 0.8), (2.8, -2.2)]
        case .thumbDown:
            fingers = [(1.2, -0.8), (1.2, 0), (1.2, 0.8), (2.8, 2.2)]
        case .peace:
            fingers = [(3.8, -0.7), (3.8, 0.7), (1.2, 1.2), (1.1, 1.8)]
        case .ok:
            fingers = [(2.0, -1.2), (3.4, 0.4), (3.4, 1.2), (3.0, 1.8)]
        case .ily:
            fingers = [(3.6, -1.5), (1.2, -0.3), (1.2, 0.5), (3.6, 1.5), (2.6, -2.2)]
        case .call:
            fingers = [(2.8, -2.0), (1.2, -0.4), (1.2, 0.4), (2.8, 2.0)]
        }

        for f in fingers {
            stroke(context, from: wrist, to: tip(f.0, f.1), width: scale * 0.55, color: .accentColor)
            let end = tip(f.0, f.1)
            let r = CGRect(x: end.x - scale * 0.35, y: end.y - scale * 0.35, width: scale * 0.7, height: scale * 0.7)
            context.fill(Path(ellipseIn: r), with: .color(.accentColor))
        }
    }
}

#Preview {
    SigningAvatarView(
        signs: [
            SignEntry(english: "hello", aslGloss: "HELLO", description: "Wave", symbolName: "hand.wave", contributor: "Signa", isUserContributed: false)
        ],
        currentIndex: 0,
        isPlaying: true,
        signProgress: 0.5
    )
    .frame(width: 220, height: 300)
    .padding()
}
