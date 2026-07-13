//
//  DataStores.swift
//  Version_0_1
//
//  Persistent local stores for user-submitted feedback and the
//  community-sourced ASL sign dictionary. Data is saved as JSON
//  in the Documents directory so it survives relaunches and can
//  be exported / shared for collection.
//

import Foundation
import Combine
import UIKit

// MARK: - Sign Dictionary

struct SignEntry: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    /// English word or short phrase (lookup key, stored lowercased).
    var english: String
    /// ASL gloss label shown during playback (e.g. "HOW", "YOU").
    var aslGloss: String
    /// Plain-language description of how to produce the sign.
    var description: String
    /// SF Symbol used as a visual stand-in for the signing avatar pose.
    var symbolName: String
    /// Who contributed this entry (anonymous by default).
    var contributor: String
    var createdAt: Date = Date()
    /// True for user-contributed entries; false for bundled seeds.
    var isUserContributed: Bool = true

    var normalizedEnglish: String {
        english.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

@MainActor
final class SignDictionaryStore: ObservableObject {
    @Published private(set) var entries: [SignEntry] = []

    private let fileName = "sign_dictionary.json"
    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    init() {
        load()
        if entries.isEmpty {
            seedDefaults()
            save()
        }
    }

    func entry(for english: String) -> SignEntry? {
        let key = english.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.first { $0.normalizedEnglish == key }
    }

    /// Resolve a free-form English sentence into an ordered sequence of signs.
    /// Prefers longest phrase matches, then single words; unknown tokens
    /// become fingerspelled letter entries.
    func signs(forSentence sentence: String) -> [SignEntry] {
        let cleaned = sentence
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        var result: [SignEntry] = []
        var i = 0
        let phraseKeys = entries
            .map(\.normalizedEnglish)
            .filter { $0.contains(" ") }
            .sorted { $0.split(separator: " ").count > $1.split(separator: " ").count }

        while i < cleaned.count {
            var matched = false
            for phrase in phraseKeys {
                let parts = phrase.split(separator: " ").map(String.init)
                if i + parts.count <= cleaned.count,
                   Array(cleaned[i..<(i + parts.count)]) == parts,
                   let entry = entry(for: phrase) {
                    result.append(entry)
                    i += parts.count
                    matched = true
                    break
                }
            }
            if matched { continue }

            let word = cleaned[i]
            if let entry = entry(for: word) {
                result.append(entry)
            } else {
                // Fingerspell unknown words letter by letter.
                for ch in word {
                    let letter = String(ch)
                    result.append(
                        SignEntry(
                            english: letter,
                            aslGloss: letter.uppercased(),
                            description: "Fingerspell \(letter.uppercased())",
                            symbolName: "hand.point.up.fill",
                            contributor: "System",
                            isUserContributed: false
                        )
                    )
                }
            }
            i += 1
        }
        return result
    }

    func add(_ entry: SignEntry) {
        var cleaned = entry
        cleaned.english = entry.normalizedEnglish
        if let idx = entries.firstIndex(where: { $0.normalizedEnglish == cleaned.english }) {
            cleaned.id = entries[idx].id
            entries[idx] = cleaned
        } else {
            entries.append(cleaned)
        }
        entries.sort { $0.english < $1.english }
        save()
    }

    func delete(_ entry: SignEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func exportURL() -> URL? {
        save()
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([SignEntry].self, from: data) else { return }
        entries = decoded.sorted { $0.english < $1.english }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func seedDefaults() {
        let seeds: [(String, String, String, String)] = [
            ("hello", "HELLO", "Open hand near the temple, wave outward once.", "hand.wave"),
            ("hi", "HI", "Wave with an open hand.", "hand.wave"),
            ("goodbye", "GOODBYE", "Open hand moves away from the body in a wave.", "hand.wave"),
            ("thanks", "THANK-YOU", "Fingers at chin move forward and down.", "hand.raised.fill"),
            ("thank you", "THANK-YOU", "Fingers at chin move forward and down.", "hand.raised.fill"),
            ("please", "PLEASE", "Flat hand circles on the chest.", "hand.raised"),
            ("yes", "YES", "Fist nods like a head nodding.", "hand.thumbsup.fill"),
            ("no", "NO", "Index and middle finger close onto the thumb.", "hand.thumbsdown.fill"),
            ("how", "HOW", "Knuckles together, hands roll forward.", "hands.clap.fill"),
            ("are", "ARE", "R-handshape moves forward from near the mouth.", "mouth.fill"),
            ("you", "YOU", "Index finger points toward the person.", "hand.point.right.fill"),
            ("i", "I", "Index finger points to your chest.", "person.fill"),
            ("me", "ME", "Index finger points to your chest.", "person.fill"),
            ("my", "MY", "Flat hand on the chest.", "person.fill"),
            ("name", "NAME", "H-handshapes tap each other twice.", "textformat"),
            ("what", "WHAT", "Palms up, hands move side to side.", "questionmark.circle.fill"),
            ("where", "WHERE", "Index finger wagged side to side.", "mappin.circle.fill"),
            ("why", "WHY", "Middle finger taps the forehead, then palm up.", "brain.head.profile"),
            ("who", "WHO", "Thumb on chin, index finger wiggles.", "person.crop.circle.questionmark"),
            ("good", "GOOD", "Flat hand from chin to palm-up hand.", "hand.thumbsup.fill"),
            ("bad", "BAD", "Hand flips down from the chin.", "hand.thumbsdown.fill"),
            ("love", "LOVE", "Crossed arms over the chest.", "heart.fill"),
            ("help", "HELP", "Fist on open palm, both rise together.", "lifepreserver.fill"),
            ("sorry", "SORRY", "Fist circles on the chest.", "heart.slash.fill"),
            ("friend", "FRIEND", "Index fingers hook together, then reverse.", "person.2.fill"),
            ("family", "FAMILY", "F-handshapes form a circle.", "figure.2.and.child.holdinghands"),
            ("eat", "EAT", "Fingertips tap the mouth.", "fork.knife"),
            ("drink", "DRINK", "C-handshape tips toward the mouth.", "cup.and.saucer.fill"),
            ("water", "WATER", "W-handshape taps the chin.", "drop.fill"),
            ("how are you", "HOW-ARE-YOU", "HOW then YOU — common greeting.", "hands.clap.fill"),
        ]

        entries = seeds.map {
            SignEntry(
                english: $0.0,
                aslGloss: $0.1,
                description: $0.2,
                symbolName: $0.3,
                contributor: "Signa",
                isUserContributed: false
            )
        }
    }
}

// MARK: - Feedback

struct FeedbackEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var category: String
    var message: String
    var rating: Int
    var contactEmail: String
    var deviceModel: String
    var systemVersion: String
    var appVersion: String
    var createdAt: Date = Date()
}

@MainActor
final class FeedbackStore: ObservableObject {
    @Published private(set) var entries: [FeedbackEntry] = []

    private let fileName = "user_feedback.json"
    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    init() { load() }

    func submit(category: String, message: String, rating: Int, contactEmail: String) {
        let entry = FeedbackEntry(
            category: category,
            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            rating: rating,
            contactEmail: contactEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            deviceModel: UIDevice.current.model,
            systemVersion: UIDevice.current.systemVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        )
        entries.insert(entry, at: 0)
        save()
    }

    func exportURL() -> URL? {
        save()
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([FeedbackEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
