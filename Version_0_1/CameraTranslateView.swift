//
//  CameraTranslateView.swift
//  Version_0_1
//
//  ASL → English: live camera preview on launch; red button starts
//  recognition; English caption pinned at the bottom. After stop, Reset
//  clears the translated words.
//

import SwiftUI
import AVFoundation
import UIKit

struct CameraTranslateView: View {
    @StateObject private var camera = CameraManager()
    @State private var isRecording = false
    @State private var didCopy = false

    var body: some View {
        ZStack {
            if camera.isAuthorized {
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()

                // Tracking (hands / body / face) still runs for recognition;
                // the skeleton overlay is intentionally not drawn on screen.
                // To show it again, re-add a Canvas calling drawTracking(_:).
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

            VStack(spacing: 0) {
                Spacer()

                // Hand-not-detected tip while recording.
                if isRecording, camera.trackingOverlay.handPoints.isEmpty, camera.recognizedText.isEmpty {
                    Text("Show your hands clearly in the frame")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(.bottom, 10)
                }

                // Persistent caption while recording or when we have text.
                if isRecording || !camera.recognizedText.isEmpty {
                    VStack(spacing: 8) {
                        Text(captionTitle)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .animation(.easeInOut(duration: 0.2), value: camera.recognizedText)

                        Text(captionSubtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)

                        // After stop (or anytime text exists): Reset + Copy.
                        if !camera.recognizedText.isEmpty {
                            HStack(spacing: 12) {
                                Button {
                                    camera.clearTranscript()
                                    didCopy = false
                                } label: {
                                    Label("Reset", systemImage: "arrow.counterclockwise")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.white.opacity(0.22))
                                .foregroundStyle(.white)

                                Button {
                                    UIPasteboard.general.string = camera.recognizedText
                                    didCopy = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                        didCopy = false
                                    }
                                } label: {
                                    Label(didCopy ? "Copied" : "Copy",
                                          systemImage: didCopy ? "checkmark" : "doc.on.doc")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.white.opacity(0.22))
                                .foregroundStyle(.white)
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 22))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                ZStack {
                    Button {
                        isRecording.toggle()
                        if isRecording {
                            // Keep previous words unless user Reset — only
                            // clear internal buffers when starting fresh
                            // with an empty caption.
                            if camera.recognizedText.isEmpty {
                                camera.startRecognition()
                            } else {
                                camera.resumeRecognitionKeepingTranscript()
                            }
                        } else {
                            camera.stopRecognition()
                        }
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
                    .accessibilityLabel(isRecording ? "Stop recognition" : "Start recognition")

                    HStack {
                        // Left: Reset shortcut when stopped with text.
                        if !isRecording, !camera.recognizedText.isEmpty {
                            Button {
                                camera.clearTranscript()
                                didCopy = false
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 52, height: 52)
                                    .background(.black.opacity(0.45), in: Circle())
                            }
                            .accessibilityLabel("Reset translation")
                            .padding(.leading, 28)
                        }

                        Spacer()

                        Button {
                            camera.switchCamera()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .background(.black.opacity(0.45), in: Circle())
                        }
                        .accessibilityLabel("Switch camera")
                        .padding(.trailing, 28)
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            camera.checkAuthorization()
            camera.startPreview()
        }
        .onDisappear {
            camera.stopRecognition()
            camera.stopPreview()
            isRecording = false
        }
    }

    /// Draws the holistic tracking overlay, MediaPipe tutorial style:
    /// green face dots, magenta/purple hand skeletons, dark red body lines.
    private func drawTracking(context: GraphicsContext, size: CGSize, overlay: TrackingOverlay) {
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height)
        }
        func line(_ s: OverlaySegment, color: Color, width: CGFloat) {
            var path = Path()
            path.move(to: map(s.a))
            path.addLine(to: map(s.b))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        func dot(_ p: CGPoint, color: Color, radius: CGFloat) {
            let c = map(p)
            let rect = CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }

        for segment in overlay.bodySegments {
            line(segment, color: Color(red: 0.55, green: 0.1, blue: 0.15).opacity(0.9), width: 3)
        }
        for point in overlay.bodyPoints {
            dot(point, color: Color(red: 0.1, green: 0.1, blue: 0.45), radius: 4)
        }
        for point in overlay.facePoints {
            dot(point, color: .green.opacity(0.85), radius: 1.6)
        }
        for segment in overlay.handSegments {
            line(segment, color: Color(red: 0.85, green: 0.2, blue: 0.55).opacity(0.95), width: 2.5)
        }
        for point in overlay.handPoints {
            dot(point, color: Color(red: 0.45, green: 0.2, blue: 0.75), radius: 3)
        }
    }

    private var captionTitle: String {
        if camera.recognizedText.isEmpty {
            return "Listening for signs…"
        }
        return camera.recognizedText
    }

    private var captionSubtitle: String {
        if camera.recognizedText.isEmpty {
            if let err = camera.gemmaError, camera.recognitionSource == "Gemma" {
                return err
            }
            return "Hold signs clearly · face + hands in frame"
        }
        if isRecording {
            return "ASL → English · \(camera.recognitionSource)"
        }
        return "Stopped · Reset to clear, or tap record to continue"
    }
}

#Preview {
    CameraTranslateView()
}
