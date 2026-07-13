//
//  Version_0_1App.swift
//  Version_0_1
//
//  App entry point. Owns the persistent dictionary + feedback stores
//  so every screen can read and contribute collected user data.
//

import SwiftUI

@main
struct Version_0_1App: App {
    @StateObject private var dictionary = SignDictionaryStore()
    @StateObject private var feedback = FeedbackStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dictionary)
                .environmentObject(feedback)
        }
    }
}
