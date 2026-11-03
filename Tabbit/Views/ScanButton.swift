import SwiftUI

/// The big "Scan Receipt" / "Scan Again" button.
struct ScanButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action, label: {
            Label(title, systemImage: "camera")
                .frame(maxWidth: .infinity)
        })
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}
