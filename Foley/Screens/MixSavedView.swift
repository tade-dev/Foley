import SwiftUI

struct MixSavedView: View {
    var mix: Mix
    var body: some View { Text("Mix \(mix.id)").foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.Colors.bg) }
}
