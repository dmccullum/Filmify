import CoreText
import SwiftUI

@main
struct GranularApp: App {
    @State private var darkroom = Darkroom()

    init() {
        // The nameplate's Barlow Condensed ships with the app, shared with the Mac.
        if let font = Bundle.main.url(forResource: "BarlowCondensed-SemiBold", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            InstantView()
                .environment(darkroom)
        }
    }
}
