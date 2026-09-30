import SwiftUI

/// Help menu: Granular has no help book, so its README on GitHub is the help.
struct HelpCommands: Commands {
    @Environment(\.openURL) private var openURL

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Granular Help") {
                openURL(URL(string: "https://github.com/dmccullum/Granular#readme")!)
            }
        }
    }
}
