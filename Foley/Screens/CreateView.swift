import SwiftUI

struct CreateView: View {
    var initialText: String
    var body: some View { Text("Create: \(initialText)").foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.Colors.bg) }
}
