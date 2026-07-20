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

    /// Bump when bundled seeds grow so existing installs pick up new words.
    private let seedVersion = 2
    private let seedVersionKey = "signDictionarySeedVersion"

    init() {
        load()
        if entries.isEmpty {
            seedDefaults()
            save()
        } else {
            mergeMissingSeeds()
        }
        UserDefaults.standard.set(seedVersion, forKey: seedVersionKey)
    }

    func entry(for english: String) -> SignEntry? {
        let key = english.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.first { $0.normalizedEnglish == key }
    }

    /// English words that are usually dropped in ASL (not fingerspelled).
    private static let skippedEnglish: Set<String> = [
        "is", "am", "a", "an", "the", "to", "of", "be"
    ]

    /// Resolve a free-form English sentence into an ordered sequence of signs.
    /// Prefers longest phrase matches, then single words; unknown tokens
    /// become fingerspelled letter entries. Copulas/articles are skipped
    /// (e.g. "My name is Bakr" → MY NAME B-A-K-R).
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
            i += 1
            if Self.skippedEnglish.contains(word) { continue }

            if let entry = entry(for: word) {
                result.append(entry)
            } else {
                // Fingerspell unknown words / names letter by letter.
                for ch in word where ch.isLetter || ch.isNumber {
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
        entries = Self.bundledSeeds()
    }

    /// Adds any bundled words missing from the user's on-disk dictionary.
    private func mergeMissingSeeds() {
        let existing = Set(entries.map(\.normalizedEnglish))
        var added = false
        for seed in Self.bundledSeeds() where !existing.contains(seed.normalizedEnglish) {
            entries.append(seed)
            added = true
        }
        if added {
            entries.sort { $0.english < $1.english }
            save()
        }
    }

    private static func bundledSeeds() -> [SignEntry] {
        let seeds: [(String, String, String, String)] = [
            ("hello", "HELLO", "Open flat hand at the forehead (salute), then move outward.", "hand.wave"),
            ("hi", "HI", "Wave with an open hand.", "hand.wave"),
            ("goodbye", "GOODBYE", "Open hand waves away from the body.", "hand.wave"),
            ("bye", "BYE", "Open hand waves away from the body.", "hand.wave"),
            ("thanks", "THANK-YOU", "Fingertips start at the chin, then move forward and down.", "hand.raised.fill"),
            ("thank you", "THANK-YOU", "Fingertips start at the chin, then move forward and down.", "hand.raised.fill"),
            ("please", "PLEASE", "Flat open hand circles on the chest.", "hand.raised"),
            ("yes", "YES", "Fist nods up and down like a head nodding.", "hand.thumbsup.fill"),
            ("no", "NO", "Index and middle close onto the thumb (or thumb-down).", "hand.thumbsdown.fill"),
            ("how", "HOW", "Bent knuckles together, hands roll forward/out.", "hands.clap.fill"),
            ("are", "ARE", "R-handshape moves forward from near the mouth.", "mouth.fill"),
            ("you", "YOU", "Index finger points toward the other person.", "hand.point.right.fill"),
            ("i", "I", "Index finger points to your own chest.", "person.fill"),
            ("me", "ME", "Index finger points to your own chest.", "person.fill"),
            ("my", "MY", "Flat open palm presses once on the chest.", "person.fill"),
            ("name", "NAME", "Both hands H-shape (index+middle); tap the two middle fingers twice.", "textformat"),
            ("what", "WHAT", "Palms up, hands shake slightly side to side.", "questionmark.circle.fill"),
            ("where", "WHERE", "Index finger points up and wags side to side.", "mappin.circle.fill"),
            ("why", "WHY", "Middle finger taps the forehead, then hand opens palm-up.", "brain.head.profile"),
            ("who", "WHO", "Thumb on chin, index finger wiggles.", "person.crop.circle.questionmark"),
            ("when", "WHEN", "Index finger of one hand circles the upright index of the other.", "calendar"),
            ("good", "GOOD", "Flat hand moves from chin down onto the other palm.", "hand.thumbsup.fill"),
            ("bad", "BAD", "Flat hand flips down from the chin.", "hand.thumbsdown.fill"),
            ("love", "LOVE", "Crossed arms over the chest (or ILY handshape).", "heart.fill"),
            ("i love you", "I-LOVE-YOU", "ILY handshape (thumb, index, pinky extended) held out.", "heart.fill"),
            ("help", "HELP", "Fist on open palm; both rise together.", "lifepreserver.fill"),
            ("sorry", "SORRY", "Fist circles on the chest.", "heart.slash.fill"),
            ("friend", "FRIEND", "Index fingers hook together, then reverse.", "person.2.fill"),
            ("family", "FAMILY", "F-handshapes form a circle in front of the body.", "figure.2.and.child.holdinghands"),
            ("eat", "EAT", "Fingertips bunched, tap the mouth repeatedly.", "fork.knife"),
            ("drink", "DRINK", "C-handshape tips toward the mouth like a cup.", "cup.and.saucer.fill"),
            ("water", "WATER", "W-handshape (3 fingers) taps the chin.", "drop.fill"),
            ("ok", "OK", "Thumb and index form a circle; other fingers up.", "hand.raised.fill"),
            ("peace", "PEACE", "Index and middle up in a V; other fingers folded.", "hand.raised"),
            ("how are you", "HOW-ARE-YOU", "HOW then YOU — common greeting.", "hands.clap.fill"),
            ("nice", "NICE", "Flat hand slides across the other open palm.", "sparkles"),
            ("meet", "MEET", "Both index fingers upright, come together to meet.", "person.2.fill"),
            ("see", "SEE", "V-handshape from near the eyes moves forward.", "eye.fill"),
            ("look", "LOOK", "V-handshape from eyes points forward.", "eye"),
            ("want", "WANT", "Both hands claw-shape, pull toward the body.", "hand.raised"),
            ("need", "NEED", "Bent index finger nods downward firmly.", "exclamationmark.circle"),
            ("like", "LIKE", "Thumb and middle finger pinch near the chest, pull out.", "heart"),
            ("more", "MORE", "Fingertips of both hands tap together.", "plus.circle"),
            ("finish", "FINISH", "Both open hands flip outward (all done).", "checkmark.circle"),
            ("stop", "STOP", "Flat hand chops down onto the other palm.", "stop.circle"),
            ("go", "GO", "Both index fingers point forward and move out.", "arrow.forward.circle"),
            ("come", "COME", "Index fingers beckon toward the body.", "arrow.backward.circle"),
            ("understand", "UNDERSTAND", "Index finger flicks up from the forehead.", "lightbulb"),
            ("know", "KNOW", "Flat hand taps the forehead.", "brain"),
            ("don't know", "DON'T-KNOW", "Flat hand leaves the forehead flipping out.", "questionmark"),
            ("mother", "MOTHER", "Thumb of open hand taps the chin.", "figure.stand"),
            ("father", "FATHER", "Thumb of open hand taps the forehead.", "figure.stand"),
            ("boy", "BOY", "Hand flattens from forehead like tipping a cap.", "figure.stand"),
            ("girl", "GIRL", "Thumb brushes down the cheek.", "figure.stand"),
            ("man", "MAN", "Open hand from forehead down to chest.", "figure.stand"),
            ("woman", "WOMAN", "Open hand from chin down to chest.", "figure.stand"),
            ("school", "SCHOOL", "Clap flat hands together twice.", "building.columns"),
            ("work", "WORK", "S-fists tap wrists together.", "briefcase"),
            ("home", "HOME", "Flat-O handshape taps cheek then ear.", "house.fill"),
            ("book", "BOOK", "Palms together, then open like a book.", "book.fill"),
            ("today", "TODAY", "Y-handshapes drop down in front of the body.", "sun.max"),
            ("tomorrow", "TOMORROW", "A-hand thumb at cheek arcs forward.", "sunrise"),
            ("yesterday", "YESTERDAY", "A-hand thumb at cheek arcs back.", "sunset"),
            ("now", "NOW", "Both Y-hands drop sharply downward.", "clock"),
            ("later", "LATER", "L-hand pivots forward from the palm.", "clock.arrow.circlepath"),
            ("again", "AGAIN", "Bent hand taps into the other palm.", "arrow.clockwise"),
            ("bathroom", "BATHROOM", "T-hand shakes side to side.", "toilet"),
            ("fine", "FINE", "Open hand taps the chest with the thumb.", "hand.thumbsup"),
            ("happy", "HAPPY", "Open hands brush up the chest repeatedly.", "face.smiling"),
            ("sad", "SAD", "Open hands drop down the face.", "face.dashed"),
            ("tired", "TIRED", "Bent hands on chest drop forward.", "bed.double"),
            ("hungry", "HUNGRY", "C-hand slides down the center of the chest.", "fork.knife"),
            ("sleep", "SLEEP", "Open hand at face closes into a flat-O and drops.", "moon.zzz"),
            ("morning", "MORNING", "Flat hand rises from under the other arm.", "sunrise.fill"),
            ("night", "NIGHT", "Bent hand arches over the other horizontal arm.", "moon.stars"),
            ("yes please", "YES PLEASE", "YES then PLEASE.", "hand.raised"),
            ("no thanks", "NO THANKS", "NO then THANK-YOU.", "hand.raised.fill"),
            ("what's your name", "WHAT YOUR NAME", "WHAT + YOUR + NAME.", "textformat"),
            ("your", "YOUR", "Flat palm pushes toward the other person.", "person.fill"),
            ("his", "HIS", "Flat palm pushes toward a male referent.", "person.fill"),
            ("her", "HER", "Flat palm pushes toward a female referent.", "person.fill"),
            ("our", "OUR", "Flat hand sweeps from one shoulder to the other.", "person.3.fill"),
        ]

        return seeds.map {
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
