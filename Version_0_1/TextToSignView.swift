//
//  TextToSignView.swift
//  Version_0_1
//
//  "English -> ASL" side of the translator. A hearing person types or
//  speaks, and the app plays back the signed translation through an
//  avatar/video area. The avatar renderer itself is a placeholder hook
//  (`SignAvatarPlayer`) so a real 3D avatar or clip-stitching engine can
//  be swapped in without touching this screen.
//

import SwiftUI

struct TextToSignView: View {
    @State private var inputText: String = ""
    @State private var isPlaying: Bool = false
    @State private var lastTranslated: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Avatar / sign playback area — stands in for the camera
            // preview on the other side of the translator so both modes
            // feel like mirror images of each other.
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
                        // Placeholder avatar figure; swap for a real
                        // avatar/video renderer driven by `lastTranslated`.
                        SignAvatarPlayer(isPlaying: $isPlaying)
                            .frame(width: 160, height: 220)

                        Text(lastTranslated)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        Button {
                            isPlaying.toggle()
                        } label: {
                            Label(isPlaying ? "Playing…" : "Replay", systemImage: isPlaying ? "pause.fill" : "play.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Text / mic input bar, styled like the input row in Translate.
            HStack(spacing: 12) {
                TextField("Type in English…", text: $inputText, axis: .vertical)
                    .focused($isInputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                    .lineLimit(1...4)

                Button {
                    // TODO: hook up speech-to-text (SFSpeechRecognizer)
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.accentColor, in: Circle())
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
    }

    private func translate() {
        // TODO: replace with real English -> ASL gloss translation.
        lastTranslated = inputText
        inputText = ""
        isInputFocused = false
        isPlaying = true
    }
}

/// Stand-in for a real signing avatar. Shows a simple animated hand icon
/// while "playing" so the UI reads correctly before a real renderer exists.
struct SignAvatarPlayer: View {
    @Binding var isPlaying: Bool

    var body: some View {
        VStack {
            Image(systemName: "figure.wave")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.pulse, isActive: isPlaying)
        }
        .padding(20)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 4)
    }
}

#Preview {
    TextToSignView()
}
