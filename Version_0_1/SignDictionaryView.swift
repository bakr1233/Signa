//
//  SignDictionaryView.swift
//  Version_0_1
//
//  Browse, search, and contribute ASL dictionary entries. User
//  contributions are persisted locally and feed the English → ASL
//  avatar playback path.
//

import SwiftUI

struct SignDictionaryView: View {
    @EnvironmentObject private var dictionary: SignDictionaryStore
    @State private var query = ""
    @State private var showingAdd = false

    private var filtered: [SignEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return dictionary.entries }
        return dictionary.entries.filter {
            $0.english.contains(q) || $0.aslGloss.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    var body: some View {
        List {
            Section {
                Text("\(dictionary.entries.count) signs · \(dictionary.entries.filter(\.isUserContributed).count) contributed by users")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Dictionary") {
                ForEach(filtered) { entry in
                    HStack(spacing: 14) {
                        Image(systemName: entry.symbolName)
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.english.capitalized)
                                .font(.headline)
                            Text(entry.aslGloss)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                            Text(entry.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if entry.isUserContributed {
                            Button(role: .destructive) {
                                dictionary.delete(entry)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if let url = dictionary.exportURL() {
                Section {
                    ShareLink(item: url) {
                        Label("Export dictionary data", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search English or ASL gloss")
        .navigationTitle("Sign Dictionary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddSignEntryView()
                .environmentObject(dictionary)
        }
    }
}

struct AddSignEntryView: View {
    @EnvironmentObject private var dictionary: SignDictionaryStore
    @Environment(\.dismiss) private var dismiss

    @State private var english = ""
    @State private var aslGloss = ""
    @State private var description = ""
    @State private var symbolName = "hand.raised.fill"
    @State private var contributor = ""

    private let symbols = [
        "hand.raised.fill", "hand.wave", "hand.point.right.fill", "hand.thumbsup.fill",
        "hand.thumbsdown.fill", "hands.clap.fill", "figure.wave", "person.fill",
        "heart.fill", "mouth.fill", "questionmark.circle.fill"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("English") {
                    TextField("Word or phrase", text: $english)
                }
                Section("ASL") {
                    TextField("Gloss (e.g. THANK-YOU)", text: $aslGloss)
                        .textInputAutocapitalization(.characters)
                    TextField("How to sign it", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Avatar pose") {
                    Picker("Symbol", selection: $symbolName) {
                        ForEach(symbols, id: \.self) { name in
                            Label(name, systemImage: name).tag(name)
                        }
                    }
                }
                Section("Contributor") {
                    TextField("Your name (optional)", text: $contributor)
                }
            }
            .navigationTitle("Add Sign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        dictionary.add(
                            SignEntry(
                                english: english,
                                aslGloss: aslGloss.isEmpty ? english.uppercased() : aslGloss,
                                description: description.isEmpty ? "User-contributed sign." : description,
                                symbolName: symbolName,
                                contributor: contributor.isEmpty ? "Anonymous" : contributor,
                                isUserContributed: true
                            )
                        )
                        dismiss()
                    }
                    .disabled(english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SignDictionaryView()
            .environmentObject(SignDictionaryStore())
    }
}
