import SwiftUI

// Keep restored navigation valid without fetching upstream release notes.
struct ChangelogView: View {
    var body: some View {
        ContentUnavailableView(
            "Fork Builds",
            systemImage: "shippingbox",
            description: Text("This fork does not check upstream releases. Install new fork builds manually.")
        )
    }
}
