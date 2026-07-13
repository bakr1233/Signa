//
//  TranslateDirection.swift
//  Version_0_1
//
//  Shared model for the sign-language translator.
//

import Foundation

/// The two translation directions the app supports, mirroring how
/// Apple's Translate app swaps between a source and target language.
enum TranslateDirection: String, CaseIterable, Identifiable {
    case signToText   // Camera watches signing -> outputs spoken/written English
    case textToSign   // User types/speaks English -> app shows signed output

    var id: String { rawValue }

    /// Label shown on the left side of the direction pill.
    var sourceLabel: String {
        switch self {
        case .signToText: return "ASL"
        case .textToSign: return "English"
        }
    }

    /// Label shown on the right side of the direction pill.
    var targetLabel: String {
        switch self {
        case .signToText: return "English"
        case .textToSign: return "ASL"
        }
    }

    /// Flips the direction, used when the user taps the swap button.
    var swapped: TranslateDirection {
        switch self {
        case .signToText: return .textToSign
        case .textToSign: return .signToText
        }
    }
}

/// A single translated line, kept so the session reads like a running
/// transcript (as in a real conversation translator).
struct TranslationEntry: Identifiable, Equatable {
    let id = UUID()
    let direction: TranslateDirection
    let sourceText: String
    let translatedText: String
    let timestamp: Date = Date()
}
