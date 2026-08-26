#if canImport(SwiftUI) && DEBUG
import SwiftUI

// MARK: - Shared sample content used across all ScreenContainer previews

struct PreviewSampleList: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach([Int](0..<20), id: \.self) { (i: Int) in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Text("\(i + 1)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.accentColor)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Item \(i + 1)").font(.body.weight(.medium))
                            Text("Subtitle for item \(i + 1)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    Divider().padding(.leading, 76)
                }
            }
        }
    }
}

#endif
