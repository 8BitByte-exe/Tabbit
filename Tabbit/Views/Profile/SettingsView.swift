import SwiftUI

/// Settings: appearance, scanning, storage, CSV export, What's New and privacy.
struct SettingsView: View {
    @EnvironmentObject private var store: TabbitStore

    @AppStorage(AppearanceSetting.storageKey) private var appearance: AppearanceSetting = .system
    @AppStorage(OCRSettings.languageCorrectionKey) private var languageCorrection: Bool = false
    @AppStorage(OCRSettings.documentReaderKey) private var documentReader: Bool = true
    @AppStorage(ReceiptIntelligence.enabledKey) private var usesIntelligence: Bool = true
    @AppStorage(ReceiptIntelligence.photoKey) private var showsPhoto: Bool = true
    @AppStorage(MapSettings.enabledKey) private var mapEnabled: Bool = false
    @State private var intelligenceStatus: IntelligenceStatus = ReceiptIntelligence.status
    @State private var usage: StorageUsage?
    @State private var shareFile: ShareFile?
    @State private var showsWhatsNew = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                section("Appearance") {
                    ClaySegmentedPicker(selection: $appearance, options: AppearanceSetting.allCases.map { option in
                        ClaySegmentedPicker<AppearanceSetting>.Option(value: option, title: option.title,
                                                                      symbol: option.symbol,
                                                                      accessibilityName: option.title)
                    })
                }

                section("Scanning") {
                    Toggle(isOn: $languageCorrection) {
                        Text("Correct words while reading")
                    }
                    .toggleStyle(ClayToggleStyle())
                    Text("Swaps letters the scanner isn't sure about for dictionary words. Can turn abbreviations like “BNLS CHKN” into other words, so it's off by default.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if OCRSettings.hasDocumentReader {
                        Toggle(isOn: $documentReader) {
                            Text("Read receipts as documents")
                        }
                        .toggleStyle(ClayToggleStyle())
                        Text("Uses Vision's document reader, which finds the receipt's rows so prices stay with their names. Turn it off to use the older text reader.")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                section("Apple Intelligence") {
                    intelligenceSection
                }

                section("Map") {
                    Toggle(isOn: $mapEnabled) {
                        Text("Show receipts on a map")
                    }
                    .toggleStyle(ClayToggleStyle())
                    Text("Finds each receipt's store with Apple Maps, once, from the store's name and the address printed on the receipt. Apple Maps also draws the map. Items, amounts, people and photos stay on this iPhone.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                section("Your data") {
                    storageMeter
                    Button(action: exportCSV) {
                        Label("Export All Receipts (CSV)", systemImage: "tablecells")
                    }
                    .buttonStyle(NeumorphicButtonStyle(prominence: .secondary, compact: true))
                    .disabled(store.receipts.isEmpty)
                    Button(action: exportBusinessCSV) {
                        Label("Export Business Receipts (CSV)", systemImage: ExpenseKind.business.symbol)
                    }
                    .buttonStyle(NeumorphicButtonStyle(prominence: .secondary, compact: true))
                    .disabled(!store.receipts.contains { receipt in receipt.expense == .business })
                }

                section("About") {
                    Button(action: {
                        showsWhatsNew = true
                    }, label: {
                        HStack(spacing: Theme.Spacing.m) {
                            IconBadge(symbol: "sparkles", tone: .positive, size: 30)
                            Text("What's New")
                                .font(Theme.Fonts.body)
                                .foregroundStyle(Theme.Colors.text)
                        }
                    })
                    .buttonStyle(NeumorphicCardButtonStyle(padding: Theme.Spacing.m))
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        Label("Scanning, reading and splitting happen on this iPhone, including Apple Intelligence.",
                              systemImage: "iphone")
                        Label("Receipts and photos are stored only here, encrypted while the phone is locked, and left out of iCloud Backup.",
                              systemImage: "lock.fill")
                        Label("Nothing leaves your phone unless you share or export it. With the map on, Apple Maps gets each store's name and address, nothing else.",
                              systemImage: "square.and.arrow.up")
                    }
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Text(versionText)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.l)
        }
        .themedScreen()
        .clayNavigation("Settings")
        .onAppear {
            usage = store.storageUsage()
            intelligenceStatus = ReceiptIntelligence.status
        }
        .sheet(item: $shareFile) { file in
            ActivityView(items: [file.url])
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsWhatsNew) {
            WhatsNewView()
        }
    }

    @ViewBuilder
    private var intelligenceSection: some View {
        HStack(spacing: Theme.Spacing.m) {
            IconBadge(symbol: "sparkles", tone: intelligenceStatus == .available ? .positive : .neutral, size: 30)
            Text("Status")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.text)
            Spacer()
            StatusPill(title: intelligenceStatus.title,
                       symbol: intelligenceStatus == .available ? "checkmark" : "info.circle",
                       tone: intelligenceStatus == .available ? .positive : .neutral)
        }
        .accessibilityElement(children: .combine)
        if intelligenceStatus == .available {
            Toggle(isOn: $usesIntelligence) {
                Text("Read receipts with Apple Intelligence")
            }
            .toggleStyle(ClayToggleStyle())
            if usesIntelligence && ReceiptIntelligence.canSeePhotos {
                Toggle(isOn: $showsPhoto) {
                    Text("Look at the photo too")
                }
                .toggleStyle(ClayToggleStyle())
                Text("Apple Intelligence sees the receipt's photo next to the scanned text, on this iPhone. It helps with faded print and misspelled names; amounts still come from the scan. Turn it off for slightly faster reading.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        Text(intelligenceStatus.explanation)
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        Label("Every amount it reads is checked against the scan. If anything doesn't add up, Tabbit uses its built-in rules. Nothing leaves your iPhone.",
              systemImage: "checkmark.shield.fill")
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionLabel(title: title)
            InfoCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    content()
                }
            }
        }
    }

    @ViewBuilder
    private var storageMeter: some View {
        if let usage = usage {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    Text("Tabbit uses \(StorageUsage.format(usage.appBytes))")
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.Colors.text)
                    Spacer()
                    Text("\(store.receipts.count) receipts")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                if let total = usage.deviceTotalBytes, let free = usage.deviceFreeBytes, total > 0 {
                    let used = Double(max(total - free, 0)) / Double(total)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            ClayBackground(shape: Capsule(style: .continuous), style: .inset)
                            Capsule(style: .continuous)
                                .fill(Theme.Gradients.accent)
                                .frame(width: max(geometry.size.width * used, 14))
                                .padding(3)
                        }
                    }
                    .frame(height: 20)
                    .accessibilityHidden(true)
                    Text("iPhone: \(StorageUsage.format(free)) free of \(StorageUsage.format(total))")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                Text("Photos \(StorageUsage.format(usage.photoBytes)) · Receipts and groups \(StorageUsage.format(usage.dataBytes))")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .accessibilityElement(children: .combine)
        } else {
            ProgressView()
                .tint(Theme.Colors.text)
        }
    }

    private func exportCSV() {
        if let url = CSVExporter.write(receipts: store.receipts, groups: store.groups, me: store.me) {
            shareFile = ShareFile(url: url)
        } else {
            store.lastError = "Couldn't create the CSV file."
        }
    }

    private func exportBusinessCSV() {
        let business = store.receipts.filter { receipt in receipt.expense == .business }
        if let url = CSVExporter.write(receipts: business, groups: store.groups, me: store.me,
                                       fileName: "Tabbit-business-receipts.csv") {
            shareFile = ShareFile(url: url)
        } else {
            store.lastError = "Couldn't create the CSV file."
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Tabbit \(version) (\(build))"
    }
}

/// The changelog, newest first.
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                SheetHeader(title: "What's New", onClose: {
                    dismiss()
                })
                ForEach(Changelog.entries) { entry in
                    InfoCard {
                        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.title)
                                    .font(Theme.Fonts.title3)
                                    .foregroundStyle(Theme.Colors.text)
                                Spacer()
                                Text("Version \(entry.version)")
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                            ForEach(entry.highlights.indices, id: \.self) { index in
                                let highlight = entry.highlights[index]
                                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                                    IconBadge(symbol: highlight.symbol, tone: .positive, size: 30)
                                    Text(highlight.text)
                                        .font(Theme.Fonts.callout)
                                        .foregroundStyle(Theme.Colors.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                Button(action: {
                    dismiss()
                }, label: {
                    Text("Continue")
                })
                .buttonStyle(NeumorphicButtonStyle(prominence: .primary))
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.xl)
        }
        .themedScreen()
        .presentationDetents([.large])
        .claySheet()
    }
}
