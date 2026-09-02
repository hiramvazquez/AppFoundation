import AppFoundation
import SwiftUI

// Violates ArchLint.R4: a View referencing its Logic directly (outside any #Preview/#if
// DEBUG scaffolding), bypassing the ViewModel entirely.
public struct BadView: View {
    let logic: BadLogic

    public var body: some View {
        Text("bad")
    }
}
