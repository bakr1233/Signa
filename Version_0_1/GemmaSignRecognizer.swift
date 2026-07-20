//
//  GemmaSignRecognizer.swift
//  Version_0_1
//
//  Sends camera frames to the local Gemma FastAPI server
//  (ml/gemma_server) for ASL→English multimodal inference.
//

import Foundation
import CoreVideo
import CoreImage
import UIKit
import Combine

final class GemmaSignRecognizer: ObservableObject {
    @Published var recognizedLabel: String = ""
    @Published var isBusy: Bool = false
    @Published var lastError: String?
    @Published var isEnabled: Bool = false

    private let lock = NSLock()
    private var inFlight = false
    private var lastSent: CFAbsoluteTime = 0
    private let minInterval: CFAbsoluteTime = 1.5
    private let session: URLSession
    private let ciContext = CIContext(options: nil)

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
        reloadSettings()
    }

    func reloadSettings() {
        let enabled = UserDefaults.standard.bool(forKey: "useGemmaVision")
        DispatchQueue.main.async { self.isEnabled = enabled }
    }

    var isEnabledCached: Bool {
        UserDefaults.standard.bool(forKey: "useGemmaVision")
    }

    func reset() {
        lock.lock()
        lastSent = 0
        lock.unlock()
        DispatchQueue.main.async {
            self.recognizedLabel = ""
            self.lastError = nil
        }
    }

    func clearRecognizedLabel() {
        DispatchQueue.main.async {
            if !self.recognizedLabel.isEmpty {
                self.recognizedLabel = ""
            }
        }
    }

    /// Safe to call from the camera session queue. Encodes JPEG immediately,
    /// then POSTs asynchronously (at most one in-flight, ~1.5s throttle).
    func ingest(pixelBuffer: CVPixelBuffer) {
        guard isEnabledCached else { return }

        lock.lock()
        let now = CFAbsoluteTimeGetCurrent()
        if inFlight || now - lastSent < minInterval {
            lock.unlock()
            return
        }
        lastSent = now
        inFlight = true
        lock.unlock()

        DispatchQueue.main.async { self.isBusy = true }

        guard let jpeg = Self.jpegData(from: pixelBuffer, context: ciContext, maxDimension: 768) else {
            finish(error: "Could not encode camera frame")
            return
        }
        guard let base = Self.normalizedBaseURL() else {
            finish(error: "Set a valid Gemma server URL in Settings")
            return
        }

        let url = base.appendingPathComponent("analyze")
        Task {
            do {
                let label = try await postAnalyze(url: url, jpeg: jpeg)
                let cleaned = Self.clean(label)
                let normalized = ASLVocabulary.canonicalLabel(from: cleaned)
                DispatchQueue.main.async {
                    self.lastError = nil
                    self.recognizedLabel = normalized ?? ""
                }
                finish(error: nil)
            } catch {
                finish(error: error.localizedDescription)
            }
        }
    }

    private func finish(error: String?) {
        lock.lock()
        inFlight = false
        lock.unlock()
        DispatchQueue.main.async {
            self.isBusy = false
            if let error { self.lastError = error }
        }
    }

    private func postAnalyze(url: URL, jpeg: Data) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"frame.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpeg)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "GemmaSignRecognizer", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: detail])
        }

        let decoded = try JSONDecoder().decode(AnalyzeResponse.self, from: data)
        return decoded.label
    }

    private static func normalizedBaseURL() -> URL? {
        let raw = (UserDefaults.standard.string(forKey: "gemmaServerURL") ?? "http://127.0.0.1:8000")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: raw), components.scheme != nil, components.host != nil else {
            return nil
        }
        if components.path.hasSuffix("/") {
            components.path = String(components.path.dropLast())
        }
        return components.url
    }

    private static func clean(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private static func jpegData(from pixelBuffer: CVPixelBuffer, context: CIContext, maxDimension: CGFloat) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent
        guard extent.width > 1, extent.height > 1 else { return nil }

        let longest = max(extent.width, extent.height)
        let scale = min(1.0, maxDimension / longest)
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7)
    }
}

private struct AnalyzeResponse: Decodable {
    let label: String
    let model: String?
}

private enum ASLVocabulary {
    private static let canonicalDisplay: [String: String] = [
        "hello": "Hello", "hi": "Hi", "goodbye": "Goodbye", "bye": "Bye",
        "thanks": "Thanks", "thank you": "Thank you", "please": "Please",
        "yes": "Yes", "no": "No", "how": "How", "are": "Are", "you": "You",
        "i": "I", "me": "Me", "my": "My", "your": "Your", "his": "His",
        "her": "Her", "our": "Our", "name": "Name", "what": "What",
        "where": "Where", "why": "Why", "who": "Who", "when": "When",
        "good": "Good", "bad": "Bad", "nice": "Nice", "fine": "Fine",
        "love": "Love", "i love you": "I love you", "help": "Help",
        "sorry": "Sorry", "friend": "Friend", "meet": "Meet",
        "family": "Family", "eat": "Eat", "drink": "Drink", "water": "Water",
        "ok": "OK", "peace": "Peace", "see": "See", "look": "Look",
        "want": "Want", "need": "Need", "like": "Like", "more": "More",
        "finish": "Finish", "stop": "Stop", "go": "Go", "come": "Come",
        "know": "Know", "understand": "Understand", "don't know": "Don't know",
        "mother": "Mother", "father": "Father", "boy": "Boy", "girl": "Girl",
        "man": "Man", "woman": "Woman", "school": "School", "work": "Work",
        "home": "Home", "book": "Book", "today": "Today", "tomorrow": "Tomorrow",
        "yesterday": "Yesterday", "now": "Now", "later": "Later",
        "again": "Again", "morning": "Morning", "night": "Night",
        "bathroom": "Bathroom", "happy": "Happy", "sad": "Sad",
        "tired": "Tired", "hungry": "Hungry", "sleep": "Sleep",
        "how are you": "How are you", "what's your name": "What's your name",
        "yes please": "Yes please", "no thanks": "No thanks",
        "letters": "Letters"
    ]

    private static let aliases: [String: String] = [
        "thankyou": "thank you",
        "i-love-you": "i love you",
        "dont know": "don't know",
        "do not know": "don't know",
        "what is your name": "what's your name",
        "whats your name": "what's your name",
        "good bye": "goodbye"
    ]

    static func canonicalLabel(from raw: String) -> String? {
        let lowered = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowered.isEmpty else { return nil }
        let compact = lowered.replacingOccurrences(of: "_", with: " ")
        let normalized = compact
            .components(separatedBy: CharacterSet.letters.union(.whitespaces).union(CharacterSet(charactersIn: "'")).inverted)
            .joined()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized == "unknown" || normalized == "no sign" || normalized == "none" {
            return nil
        }
        if let direct = canonicalDisplay[normalized] {
            return direct
        }
        if let alias = aliases[normalized], let canonical = canonicalDisplay[alias] {
            return canonical
        }
        return nil
    }
}
