//
//  TextToSignView.swift
//  Version_0_1
//
//  English → ASL with an animated skeletal signing avatar.
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
    @State private var signProgress: Double = 0
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
                        Image(systemName: "figure.stand")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("Type or speak English below\nto see it signed with motion")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    VStack(spacing: 14) {
                        SigningAvatar3DView(
                            signs: playbackSigns,
                            currentIndex: currentSignIndex,
                            isPlaying: isPlaying,
                            signProgress: signProgress
                        )
                        .frame(maxWidth: 220)
                        .frame(height: 280)
                        .padding(.top, 8)

                        Text(lastTranslated)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        if playbackSigns.indices.contains(currentSignIndex) {
                            Text(playbackSigns[currentSignIndex].aslGloss)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                        }

                        if !playbackSigns.isEmpty {
                            Text(playbackSigns.map(\.aslGloss).joined(separator: " → "))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }

                        HStack(spacing: 12) {
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

                            Button {
                                stopPlayback()
                                lastTranslated = ""
                                playbackSigns = []
                                currentSignIndex = 0
                                signProgress = 0
                            } label: {
                                Label("Clear", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.bottom, 8)
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
        signProgress = 0

        let speed = max(playbackSpeed, 0.4)
        // Letters fingerspell a bit faster; whole words a bit longer.
        playbackTask = Task { @MainActor in
            while !Task.isCancelled && isPlaying {
                let currentIsLetter = playbackSigns.indices.contains(currentSignIndex)
                    && playbackSigns[currentSignIndex].english.count == 1
                let duration = (currentIsLetter ? 0.55 : 0.95) / speed
                let steps = currentIsLetter ? 14 : 22
                for step in 0...steps {
                    guard !Task.isCancelled, isPlaying else { return }
                    signProgress = Double(step) / Double(steps)
                    try? await Task.sleep(nanoseconds: UInt64((duration / Double(steps)) * 1_000_000_000))
                }
                if hapticsEnabled {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                guard !Task.isCancelled, isPlaying else { return }
                if currentSignIndex >= playbackSigns.count - 1 {
                    isPlaying = false
                    signProgress = 1
                    break
                }
                currentSignIndex += 1
                signProgress = 0
            }
        }
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }
}

#Preview {
    TextToSignView()
        .environmentObject(SignDictionaryStore())
}
