//
//  SettingsView.swift
//  Version_0_1
//
//  Settings for camera, Gemma vision server, avatar playback,
//  Sign Dictionary, and Feedback collection.
//

import SwiftUI
import AVFoundation

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("avatarPlaybackSpeed") private var playbackSpeed: Double = 1.0
    @AppStorage("hapticFeedbackEnabled") private var hapticsEnabled: Bool = true
    @AppStorage("useGemmaVision") private var useGemmaVision: Bool = false
    @AppStorage("gemmaServerURL") private var gemmaServerURL: String = "http://127.0.0.1:8000"
    @State private var cameraStatus: AVAuthorizationStatus = .notDetermined
    @State private var healthMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Camera") {
                    HStack {
                        Text("Access")
                        Spacer()
                        Text(cameraStatusLabel)
                            .foregroundStyle(.secondary)
                    }
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section {
                    Toggle("Use Gemma vision", isOn: $useGemmaVision)
                    TextField("Server URL", text: $gemmaServerURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("Test connection") {
                        Task { await testGemmaHealth() }
                    }
                    if let healthMessage {
                        Text(healthMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Gemma vision")
                } footer: {
                    Text("Runs google/gemma-4 on a Mac/GPU host (see ml/gemma_server). On a physical iPhone, use your Mac’s LAN IP, e.g. http://192.168.1.10:8000. Falls back to on-device hand pose if unreachable.")
                }

                Section("Sign Playback") {
                    VStack(alignment: .leading) {
                        Text("Avatar Speed")
                        Slider(value: $playbackSpeed, in: 0.5...1.5, step: 0.1) {
                            Text("Speed")
                        }
                        Text(String(format: "%.1fx", playbackSpeed))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Haptic feedback on translation", isOn: $hapticsEnabled)
                }

                Section("Community data") {
                    NavigationLink {
                        SignDictionaryView()
                    } label: {
                        Label("Sign Dictionary", systemImage: "book.fill")
                    }
                    NavigationLink {
                        FeedbackView()
                    } label: {
                        Label("Send Feedback", systemImage: "envelope.fill")
                    }
                }

                Section {
                    Text("For best ASL → English results: stand so your face and both hands are visible, sign at a natural pace, and wait for the caption to lock before the next word. After you stop recording, use Reset to clear the translation.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Signing tips")
                }

                Section("About") {
                    HStack {
                        Text("App")
                        Spacer()
                        Text("Signa")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("0.1")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
            }
        }
    }

    private var cameraStatusLabel: String {
        switch cameraStatus {
        case .authorized: return "Enabled"
        case .denied, .restricted: return "Denied"
        case .notDetermined: return "Not Requested"
        @unknown default: return "Unknown"
        }
    }

    private func testGemmaHealth() async {
        healthMessage = "Checking…"
        let raw = gemmaServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: raw) else {
            healthMessage = "Invalid URL"
            return
        }
        let url = base.appendingPathComponent("health")
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                healthMessage = "Server returned an error"
                return
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let model = json["model"] as? String {
                let loaded = (json["loaded"] as? Bool).map { $0 ? "loaded" : "not loaded yet" } ?? ""
                healthMessage = "OK · \(model) (\(loaded))"
            } else {
                healthMessage = "OK"
            }
        } catch {
            healthMessage = "Unreachable: \(error.localizedDescription)"
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SignDictionaryStore())
        .environmentObject(FeedbackStore())
}
