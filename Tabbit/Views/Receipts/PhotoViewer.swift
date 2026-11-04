import Photos
import PhotosUI
import SwiftUI
import UIKit

/// Full-screen receipt photos: pinch or double-tap to zoom, swipe between pages,
/// save to Photos, replace (camera or library) or remove.
struct PhotoViewer: View {
    let receiptID: UUID

    @EnvironmentObject private var store: TabbitStore
    @Environment(\.dismiss) private var dismiss

    @State private var pages: [UIImage] = []
    @State private var page = 0
    @State private var showsScanner = false
    @State private var showsPicker = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var confirmRemove = false
    @State private var isWorking = false
    @State private var toast: String?

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            if pages.isEmpty {
                emptyState
            } else {
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        ZoomableImageView(image: pages[index])
                            .accessibilityLabel("Receipt photo, page \(index + 1) of \(pages.count)")
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: pages.count > 1 ? .always : .never))
                .padding(.top, 72)
                .padding(.bottom, 96)
            }

            VStack {
                topBar
                Spacer()
                if !pages.isEmpty {
                    bottomBar
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.s)

            if isWorking {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.Colors.accentInk)
                    .frame(width: 88, height: 88)
                    .clayRaised(cornerRadius: 44)
            }
        }
        .toast($toast)
        .onAppear(perform: load)
        .fullScreenCover(isPresented: $showsScanner) {
            DocumentScannerView(onOutcome: { outcome in
                showsScanner = false
                if case .scanned(let images) = outcome {
                    replace(with: images)
                }
            })
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showsPicker, selection: $pickerItems, maxSelectionCount: 5,
                      selectionBehavior: .ordered, matching: .images)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else {
                return
            }
            pickerItems = []
            isWorking = true
            Task {
                let images = await ReceiptFlow.loadImages(items)
                if images.isEmpty {
                    isWorking = false
                    toast = "Couldn't open that photo"
                } else {
                    replace(with: images)
                }
            }
        }
        .confirmationDialog("Remove the photos?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove Photos", role: .destructive) {
                store.removePhotos(receiptID)
                load()
            }
            Button("Cancel", role: .cancel) {
            }
        } message: {
            Text("The receipt stays; only its pictures are deleted.")
        }
    }

    // MARK: - Bars

    private var topBar: some View {
        HStack {
            Button(action: {
                dismiss()
            }, label: {
                Image(systemName: "xmark")
            })
            .buttonStyle(NeumorphicIconButtonStyle())
            .accessibilityLabel("Close")
            Spacer()
            if pages.count > 1 {
                Text("\(page + 1) of \(pages.count)")
                    .font(Theme.Fonts.subheadline.weight(.bold))
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: Theme.Spacing.xl) {
            Button(action: saveCurrentPage) {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(NeumorphicIconButtonStyle(size: 56))
            .accessibilityLabel("Save to Photos")

            replaceMenu(symbol: "arrow.triangle.2.circlepath.camera", label: "Replace photo")

            Button(action: {
                confirmRemove = true
            }, label: {
                Image(systemName: "trash")
            })
            .buttonStyle(NeumorphicIconButtonStyle(size: 56, tint: Theme.Colors.danger))
            .accessibilityLabel("Remove photos")
        }
        .padding(.bottom, Theme.Spacing.s)
    }

    private func replaceMenu(symbol: String, label: String) -> some View {
        Menu {
            Button(action: {
                showsScanner = true
            }, label: {
                Label("Scan with Camera", systemImage: "camera.viewfinder")
            })
            Button(action: {
                showsPicker = true
            }, label: {
                Label("Choose from Photos", systemImage: "photo.on.rectangle")
            })
        } label: {
            ClayIconLabel(symbol: symbol, size: 56)
        }
        .accessibilityLabel(label)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.xl) {
            EmptyStateView(symbol: "photo", title: "No photo",
                           message: "Add a picture of the receipt to check it later.")
            HStack(spacing: Theme.Spacing.m) {
                Button(action: {
                    showsScanner = true
                }, label: {
                    Label("Scan", systemImage: "camera.viewfinder")
                })
                .buttonStyle(NeumorphicButtonStyle(prominence: .primary))
                Button(action: {
                    showsPicker = true
                }, label: {
                    Label("Photos", systemImage: "photo.on.rectangle")
                })
                .buttonStyle(NeumorphicButtonStyle(prominence: .secondary))
            }
        }
        .padding(Theme.Spacing.screen)
    }

    // MARK: - Actions

    private func load() {
        let count = store.receipt(receiptID)?.pageImageCount ?? 0
        var loaded: [UIImage] = []
        for index in 0..<max(count, 0) {
            if let image = store.pageImage(for: receiptID, page: index) {
                loaded.append(image)
            }
        }
        pages = loaded
        page = min(page, max(loaded.count - 1, 0))
    }

    private func replace(with images: [UIImage]) {
        isWorking = true
        Task {
            let encoded: (pages: [Data], thumbnail: Data?) = await Task.detached(priority: .userInitiated) {
                let pages = images.compactMap { image in
                    ScanProcessor.jpegData(for: image, maxDimension: 2000, quality: 0.7)
                }
                let thumbnail = images.first.flatMap { image in
                    ScanProcessor.jpegData(for: image, maxDimension: 320, quality: 0.75)
                }
                return (pages: pages, thumbnail: thumbnail)
            }.value
            do {
                try store.replacePhotos(receiptID, pageJPEGs: encoded.pages, thumbnailJPEG: encoded.thumbnail)
                page = 0
                load()
                toast = "Photo replaced"
                Haptics.success()
            } catch {
                toast = "Couldn't save the photo"
            }
            isWorking = false
        }
    }

    private func saveCurrentPage() {
        guard page < pages.count else {
            return
        }
        let image = pages[page]
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                toast = "Allow Photos access in Settings"
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    _ = PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                toast = "Saved to Photos"
                Haptics.success()
            } catch {
                toast = "Couldn't save to Photos"
            }
        }
    }
}

/// A photo in a UIKit scroll view: pinch to zoom, double-tap to zoom in or out.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomingImageScrollView {
        let view = ZoomingImageScrollView()
        view.setImage(image)
        return view
    }

    func updateUIView(_ uiView: ZoomingImageScrollView, context: Context) {
        uiView.setImage(image)
    }
}

final class ZoomingImageScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var laidOutSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        bouncesZoom = true
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.layer.cornerRadius = 12
        imageView.layer.cornerCurve = .continuous
        imageView.clipsToBounds = true
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func setImage(_ image: UIImage) {
        guard imageView.image !== image else {
            return
        }
        imageView.image = image
        laidOutSize = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize else {
            return
        }
        laidOutSize = bounds.size
        fitImage()
    }

    /// Fits the image to the view at zoom 1 and centers it.
    private func fitImage() {
        zoomScale = 1
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0,
              bounds.width > 0, bounds.height > 0 else {
            return
        }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        imageView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
        centerContent()
    }

    private func centerContent() {
        let horizontal = max((bounds.width - contentSize.width) / 2, 0)
        let vertical = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }
        let point = gesture.location(in: imageView)
        let scale: CGFloat = 2.5
        let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                          width: size.width, height: size.height)
        zoom(to: rect, animated: true)
    }
}
