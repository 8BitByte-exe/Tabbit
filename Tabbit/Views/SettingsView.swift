import SwiftUI

/// Text-recognition settings. Stored in UserDefaults and read when a scan starts.
struct SettingsView: View {
    @AppStorage(OCRSettings.languageCorrectionKey) private var languageCorrection: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Correct words while reading", isOn: $languageCorrection)
                } header: {
                    Text("Text recognition")
                } footer: {
                    Text("When on, Vision swaps letters it isn't sure about for dictionary words. That helps with ordinary words, but can turn receipt abbreviations like \"BNLS CHKN\" into different words. Off reads the letters as printed. Applies to your next scan.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
