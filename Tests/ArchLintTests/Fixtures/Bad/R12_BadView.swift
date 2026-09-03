import AppFoundation
import SwiftUI

// Violates ArchLint.R12: `let viewModel:` instead of `@State private var viewModel:` — a
// transient ViewModel built in a navigation destination builder is silently replaced the
// next time SwiftUI reevaluates that builder, and whatever `.load()` sent it is lost
// (PRD-X-05, A3/A7).
public struct BadView: View {
    let viewModel: BadViewModel

    public init(viewModel: BadViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Text("bad")
    }
}
