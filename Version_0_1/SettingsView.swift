//
//  SettingsView.swift
//  Version_0_1
//
//  Replaces the original SettingView.swift with a fuller settings
//  screen appropriate for a translator app: camera permission status,
//  playback preferences for the sign avatar, and app info.
//

import SwiftUI
import AVFoundation

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("avatarPlaybackSpeed") private var playbackSpeed: Double = 1.0
    @AppStorage("hapticFeedbackEnabled") private var hapticsEnabled: Bool = true
    @State private var cameraStatus: AVAuthorizationStatus = .notDetermined

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

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("0.1")
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink("Sign Dictionary") {
                        Text("Sign dictionary coming soon.")
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink("Send Feedback") {
                        Text("Feedback form coming soon.")
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
}

#Preview {
    SettingsView()
}
