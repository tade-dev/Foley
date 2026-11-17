import Testing
import Foundation
import SwiftData
@testable import Foley

@Suite struct DemoSeederTests {
    @MainActor @Test func seedsTwoScenesOnceAndFilesExist() throws {
        let container = try ModelContainer(for: SoundScene.self, Pad.self, Mix.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        #expect(try DemoSeeder.seedIfNeeded(context: ctx) == 2)
        #expect(try DemoSeeder.seedIfNeeded(context: ctx) == 0)
        let scenes = try ctx.fetch(FetchDescriptor<SoundScene>())
        let pirate = try #require(scenes.first { $0.title == "Pirate ship in a storm" })
        #expect(pirate.orderedPads.count == 6)
        #expect(pirate.orderedPads[0].name == "Creaking hull")
        for pad in scenes.flatMap(\.pads) {
            #expect(DemoSeeder.audioURL(file: pad.demoFile ?? "") != nil, "\(pad.name) audio missing")
        }
    }
}
