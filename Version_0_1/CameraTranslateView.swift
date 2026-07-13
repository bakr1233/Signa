//
//  CameraTranslateView.swift
//  Version_0_1
//
//  "ASL -> English" side of the translator. Full-bleed camera preview
//  with a live caption bar, matching the layout style of Apple's
//  Translate app (big glanceable text over a live feed) rather than
//  the plain black rectangle in the original mockup.
//

import SwiftUI
import AVFoundation

struct CameraTranslateView: View {
    @StateObject private var camera = CameraManager()
    @State private var isRecording = false

    var body: some View {
        ZStack {
            // Live camera feed, or a placeholder while permission is pending.
            if camera.isAuthorized {
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Camera access is needed to read sign language")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Button("Enable Camera") { camera.checkAuthorization() }
                        .buttonStyle(.borderedProminent)
                }
            }

            VStack {
                Spacer()

                // Live caption bar showing recognized text, styled like a
                // subtitle strip so it stays readable over any background.
                if !camera.recognizedText.isEmpty || isRecording {
                    Text(camera.recognizedText.isEmpty ? "Listening for signs…" : camera.recognizedText)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }

                // Record button, kept from the original design but paired
                // with a clear recording state.
                Button {
                    isRecording.toggle()
                    isRecording ? camera.start() : camera.stop()
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(.white, lineWidth: 4)
                            .frame(width: 76, height: 76)
                        RoundedRectangle(cornerRadius: isRecording ? 8 : 32)
                            .fill(.red)
                            .frame(width: isRecording ? 32 : 60, height: isRecording ? 32 : 60)
                            .animation(.spring(response: 0.3), value: isRecording)
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear { camera.checkAuthorization() }
        .onDisappear { camera.stop() }
        .animation(.easeInOut, value: camera.recognizedText)
    }
}

#Preview {
    CameraTranslateView()
}
