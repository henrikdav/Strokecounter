import SwiftUI

// A grey button and Done (green) side by side at the bottom edge, the same on every screen that ends with them:
// Cancel on the club lists, Undo on the confirmation of a stroke. Placed last in a VStack that ignores the bottom
// safe area.
struct CancelDoneButtons: View {
    var cancelTitle = "Cancel"
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            button(cancelTitle, fill: Color(white: 0.2), ink: .primary, action: onCancel)
            button("Done", fill: accent, ink: accentInk, action: onDone)
        }
        // Inset from the sides, so the display's rounded corners don't cut them at the bottom edge.
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func button(_ title: String, fill: Color, ink: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(Capsule().fill(fill))
        }
        .buttonStyle(.plain)
    }
}
