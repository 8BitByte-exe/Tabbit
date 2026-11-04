import SwiftUI

/// Settings: text recognition and a privacy summary.
struct SettingsView: View {
    @AppStorage(OCRSettings.languageCorrectionKey) private var languageCorrection: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    NeumorphicCard {
                        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                            SectionLabel(title: "Text recognition")
                            Toggle(isOn: $languageCorrection) {
                                Text("Correct words while reading")
                                    .font(Theme.Fonts.body)
                                    .foregroundColor(Theme.Colors.text)
                            }
                            .tint(Theme.Colors.accentBottom)
                            .frame(minHeight: Theme.Size.tapTarget)
                            Text("When on, Vision swaps letters it isn't sure about for dictionary words. That helps with ordinary words, but can turn receipt abbreviations like \"BNLS CHKN\" into different words. Off reads the letters as printed. Applies to your next scan.")
                                .font(Theme.Fonts.callout)
                                .foregroundColor(Theme.Colors.secondaryText)
                        }
                    }

                    NeumorphicCard {
                        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                            SectionLabel(title: "Privacy")
                            Label("Scanning, reading and parsing happen on this iPhone.", systemImage: "iphone")
                            Label("Receipts and photos are stored only on this iPhone, encrypted while it's locked, and left out of iCloud Backup.", systemImage: "lock")
                            Label("Nothing leaves the phone unless you tap Export.", systemImage: "square.and.arrow.up")
                        }
                        .font(Theme.Fonts.callout)
                        .foregroundColor(Theme.Colors.text)
                    }

                    Text(versionText)
                        .font(Theme.Fonts.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.vertical, Theme.Spacing.xl)
            }
            .themedScreen()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(Theme.Fonts.headline)
                }
            }
        }
        .tint(Theme.Colors.accentInk)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Tabbit \(version) (\(build))"
    }
}
