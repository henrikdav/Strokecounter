import SwiftUI

// The one club list, used after a swing (SwingClubsView) and to change a stroke's club (ClubPickerView), so both
// look and work the same: the screen's title in the system bar, the bag scrolling in the middle, and one button
// fixed at the bottom edge. The club in the middle of the list is marked; the Digital Crown (or a swipe) moves the
// list a club at a time, so the crown moves the mark. A tap on a club picks it, marked or not. There is no back
// button: the bottom button is the way out without picking.
struct ClubListView: View {
    let clubs: [String]
    let start: String                    // marked and in the middle when the list opens
    let bottomLabel: String
    let onPick: (String) -> Void
    let onBottom: () -> Void

    @State private var centered: String?

    static let rowHeight: CGFloat = 34

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(clubs, id: \.self) { club in row(club) }
                    }
                    .scrollTargetLayout()
                }
                // Room above the first and below the last club, so each can stand in the middle.
                .contentMargins(.vertical, max(0, (geometry.size.height - Self.rowHeight) / 2), for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $centered, anchor: .center)
                .scrollIndicators(.hidden)
            }
            Button(action: onBottom) {
                Text(bottomLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(Capsule().fill(Color(white: 0.2)))
            }
            .buttonStyle(.plain)
            // Inset from the sides, so the display's rounded corners don't cut it at the bottom edge.
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
        // Down to the bottom edge, so the list gets the room the bottom margin would take.
        .ignoresSafeArea(edges: .bottom)
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if centered == nil { centered = start } }
    }

    private func row(_ club: String) -> some View {
        let marked = club == (centered ?? start)
        return Button {
            onPick(club)
        } label: {
            Text(club)
                .font(.system(size: 15, weight: marked ? .bold : .regular))
                .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(marked ? accent.opacity(0.18) : tile)
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(marked ? accent : .clear))
                )
        }
        .buttonStyle(.plain)
        .id(club)
        .accessibilityAddTraits(marked ? .isSelected : [])
    }
}
