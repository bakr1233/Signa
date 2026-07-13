//
//  ContentView.swift
//  Version_0_1
//
//  Main screen of the sign-language translator, redesigned to match the
//  layout language of Apple's Translate app: a direction pill with a
//  swap control up top, a large glanceable content area in the middle
//  (camera feed or sign avatar depending on direction), and a settings
//  gear tucked in the corner.
//

import SwiftUI

struct ContentView: View {
    @State private var direction: TranslateDirection = .signToText
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Main content swaps based on direction, mirroring how
                // Translate swaps which language box is "listening".
                Group {
                    switch direction {
                    case .signToText:
                        CameraTranslateView()
                    case .textToSign:
                        TextToSignView()
                    }
                }
                .ignoresSafeArea(edges: direction == .signToText ? .all : [])

                // Top bar: direction pill + settings, overlaid so the
                // camera view can still go full-bleed underneath it.
                HStack {
                    DirectionPill(direction: $direction)

                    Spacer()

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(direction == .signToText ? .white : .primary)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
}

/// The "ASL ⇄ English" pill with a tappable swap arrow, styled after
/// the source/target language selector in Translate.
struct DirectionPill: View {
    @Binding var direction: TranslateDirection

    var body: some View {
        HStack(spacing: 10) {
            Text(direction.sourceLabel)
                .fontWeight(.semibold)

            Button {
                withAnimation(.spring(response: 0.35)) {
                    direction = direction.swapped
                }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 13, weight: .bold))
            }

            Text(direction.targetLabel)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .foregroundStyle(direction == .signToText ? .white : .primary)
    }
}

#Preview {
    ContentView()
}
