//
//  FeedbackView.swift
//  Version_0_1
//
//  Collects structured product feedback from users and persists it
//  locally so the team can export / share the dataset later.
//

import SwiftUI

struct FeedbackView: View {
    @EnvironmentObject private var feedbackStore: FeedbackStore
    @State private var category = "Suggestion"
    @State private var message = ""
    @State private var rating = 4
    @State private var contactEmail = ""
    @State private var didSubmit = false

    private let categories = ["Suggestion", "Bug", "Sign Accuracy", "Avatar", "Other"]

    var body: some View {
        Form {
            Section("How are we doing?") {
                Picker("Rating", selection: $rating) {
                    ForEach(1...5, id: \.self) { value in
                        Text("\(value) ★").tag(value)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Category", selection: $category) {
                    ForEach(categories, id: \.self, content: Text.init)
                }
            }

            Section("Your feedback") {
                TextField("Tell us what to improve…", text: $message, axis: .vertical)
                    .lineLimit(4...10)
                TextField("Email (optional)", text: $contactEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Button {
                    guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    feedbackStore.submit(
                        category: category,
                        message: message,
                        rating: rating,
                        contactEmail: contactEmail
                    )
                    message = ""
                    contactEmail = ""
                    rating = 4
                    didSubmit = true
                } label: {
                    Text("Submit Feedback")
                        .frame(maxWidth: .infinity)
                }
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !feedbackStore.entries.isEmpty {
                Section("Collected (\(feedbackStore.entries.count))") {
                    ForEach(feedbackStore.entries.prefix(20)) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.category).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(entry.rating)★").foregroundStyle(.secondary)
                            }
                            Text(entry.message)
                                .font(.subheadline)
                            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let url = feedbackStore.exportURL() {
                        ShareLink(item: url) {
                            Label("Export collected feedback", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .navigationTitle("Send Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Thanks!", isPresented: $didSubmit) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your feedback was saved on this device and added to the collection.")
        }
    }
}

#Preview {
    NavigationStack {
        FeedbackView()
            .environmentObject(FeedbackStore())
    }
}
