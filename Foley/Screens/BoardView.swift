import SwiftUI

struct BoardView: View {
    var scene: SoundScene
    var body: some View { Text("Board: \(scene.title)").foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.Colors.sceneBg) }
}
