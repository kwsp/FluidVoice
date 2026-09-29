import SwiftUI

/// Kept for restored navigation state from upstream installations.
struct FeedbackView: View {
    var body: some View {
        ContentUnavailableView("Feedback uploads removed", systemImage: "lock.shield",
            description: Text("This fork does not send feedback, email addresses, or transcript examples."))
    }
}
