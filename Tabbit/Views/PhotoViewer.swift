import SwiftUI
import UIKit

/// Full-screen receipt photos, for checking fields against the paper.
/// Scroll to move around; zoom with the buttons or a double tap.
struct PhotoViewer: View {
    let receiptID: UUID
    let pageCount: Int

    @EnvironmentObject private var store: ReceiptStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pages: [UIImage] = []
    @State private var zoom: CGFloat = 1

    private static let zoomLevels: [CGFloat] = [1, 2, 3]

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Theme.Colors.background.ignoresSafeArea()

                ScrollView([.vertical, .horizontal]) {
                    VStack(spacing: Theme.Spacing.l) {
                        ForEach(pages.indices, id: \.self) { index in
                            Image(uiImage: pages[index])
                                .resizable()
                                .scaledToFit()
                                .frame(width: max(geometry.size.width - 2 * Theme.Spacing.screen, 100) * zoom)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
                                .accessibilityLabel("Receipt photo, page \(index + 1) of \(pages.count)")
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.screen)
                    .padding(.top, 88)
                    .padding(.bottom, Theme.Spacing.xxl)
                    .onTapGesture(count: 2) {
                        stepZoom()
                    }
                }

                controls
                    .padding(.horizontal, Theme.Spacing.screen)
                    .padding(.top, Theme.Spacing.s)
            }
        }
        .onAppear {
            var loaded: [UIImage] = []
            for page in 0..<max(pageCount, 0) {
                if let image = store.pageImage(for: receiptID, page: page) {
                    loaded.append(image)
                }
            }
            pages = loaded
        }
    }

    private var controls: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button(action: {
                dismiss()
            }, label: {
                Image(systemName: "xmark")
            })
            .buttonStyle(NeumorphicIconButtonStyle())
            .accessibilityLabel("Close")

            Spacer()

            Button(action: {
                changeZoom(to: max(zoom - 1, 1))
            }, label: {
                Image(systemName: "minus.magnifyingglass")
            })
            .buttonStyle(NeumorphicIconButtonStyle())
            .disabled(zoom <= 1)
            .accessibilityLabel("Zoom out")

            Button(action: {
                changeZoom(to: min(zoom + 1, 3))
            }, label: {
                Image(systemName: "plus.magnifyingglass")
            })
            .buttonStyle(NeumorphicIconButtonStyle())
            .disabled(zoom >= 3)
            .accessibilityLabel("Zoom in")
        }
    }

    private func stepZoom() {
        let next = PhotoViewer.zoomLevels.first(where: { level in level > zoom }) ?? 1
        changeZoom(to: next)
    }

    private func changeZoom(to level: CGFloat) {
        if reduceMotion {
            zoom = level
        } else {
            withAnimation(Theme.Motion.press) {
                zoom = level
            }
        }
    }
}
