//
//  TextToSignView.swift
//  Version_0_1
//
//  "English -> ASL" side of the translator. A hearing person types or
//  speaks, and the app plays back the signed translation through an
//  avatar driven by the Sign Dictionary (pose + gloss + description).
//

import SwiftUI
import UIKit

struct TextToSignView: View {
    @EnvironmentObject private var dictionary: SignDictionaryStore
    @AppStorage("avatarPlaybackSpeed") private var playbackSpeed: Double = 1.0
    @AppStorage("hapticFeedbackEnabled") private var hapticsEnabled: Bool = true

    @StateObject private var speech = SpeechRecognizer()
    @State private var inputText: String = ""
    @State private var isPlaying: Bool = false
    @State private var lastTranslated: String = ""
    @State private var playbackSigns: [SignEntry] = []
    @State private var currentSignIndex: Int = 0
    @State private var playbackTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 0)
                    .fill(Color(.secondarySystemBackground))
                    .ignoresSafeArea(edges: .top)

                if lastTranslated.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("Type or speak English below\nto see it signed here")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    VStack(spacing: 16) {
                        SignAvatarPlayer(
                            signs: playbackSigns,
                            currentIndex: currentSignIndex,
                            isPlaying: isPlaying
                        )
                        .frame(maxWidth: 280)
                        .frame(height: 260)

                        Text(lastTranslated)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        if !playbackSigns.isEmpty {
                            Text(playbackSigns.map(\.aslGloss).joined(separator: " → "))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }

                        Button {
                            if isPlaying {
                                stopPlayback()
                            } else {
                                startPlayback()
                            }
                        } label: {
                            Label(
                                isPlaying ? "Playing…" : "Replay",
                                systemImage: isPlaying ? "pause.fill" : "play.fill"
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            if let error = speech.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            HStack(spacing: 12) {
                TextField("Type in English…", text: $inputText, axis: .vertical)
                    .focused($isInputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                    .lineLimit(1...4)
                    .onChange(of: speech.transcript) { _, newValue in
                        guard speech.isRecording, !newValue.isEmpty else { return }
                        inputText = newValue
                    }

                Button {
                    isInputFocused = false
                    speech.toggle()
                } label: {
                    Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(speech.isRecording ? Color.red : Color.accentColor, in: Circle())
                }
                .accessibilityLabel(speech.isRecording ? "Stop listening" : "Dictate with microphone")

                Button {
                    translate()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(inputText.isEmpty ? .secondary : Color.accentColor)
                }
                .disabled(inputText.isEmpty)
            }
            .padding(12)
            .background(.bar)
        }
        .onAppear { speech.requestAuthorization() }
        .onDisappear {
            speech.stop()
            stopPlayback()
        }
    }

    private func translate() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if speech.isRecording { speech.stop() }

        lastTranslated = text
        playbackSigns = dictionary.signs(forSentence: text)
        inputText = ""
        isInputFocused = false

        if hapticsEnabled {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        startPlayback()
    }

    private func startPlayback() {
        guard !playbackSigns.isEmpty else { return }
        playbackTask?.cancel()
        isPlaying = true
        currentSignIndex = 0

        let speed = max(playbackSpeed, 0.4)
        let holdNanos = UInt64((1.1 / speed) * 1_000_000_000)

        playbackTask = Task { @MainActor in
            while !Task.isCancelled && isPlaying {
                if hapticsEnabled {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                try? await Task.sleep(nanoseconds: holdNanos)
                guard !Task.isCancelled, isPlaying else { break }
                if currentSignIndex >= playbackSigns.count - 1 {
                    isPlaying = false
                    break
                }
                currentSignIndex += 1
            }
        }
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }
}

/// Avatar that steps through dictionary signs: pose symbol, ASL gloss,
/// and a short production note so English → ASL actually reflects signs.
struct SignAvatarPlayer: View {
    let signs: [SignEntry]
    let currentIndex: Int
    let isPlaying: Bool

    private var current: SignEntry? {
        guard signs.indices.contains(currentIndex) else { return nil }
        return signs[currentIndex]
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 3)

                if let current {
                    VStack(spacing: 12) {
                        Image(systemName: current.symbolName)
                            .font(.system(size: 72, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .symbolEffect(.bounce, value: currentIndex)
                            .symbolEffect(.pulse, isActive: isPlaying)
                            .contentTransition(.symbolEffect(.replace))

                        Text(current.aslGloss)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)

                        Text(current.description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 20)
                    .id(current.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }

            if signs.count > 1 {
                HStack(spacing: 6) {
                    ForEach(Array(signs.indices), id: \.self) { index in
                        Capsule()
                            .fill(index == currentIndex ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: index == currentIndex ? 18 : 7, height: 7)
                    }
                }
                .animation(.spring(response: 0.35), value: currentIndex)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentIndex)
    }
}

#Preview {
    TextToSignView()
        .environmentObject(SignDictionaryStore())
}
