import CoreText
import SwiftUI

@main
struct GranularApp: App {
    @State private var darkroom: Darkroom
    @State private var editor: Editor

    init() {
        let darkroom = Darkroom()
        _darkroom = State(initialValue: darkroom)
        _editor = State(initialValue: Editor(darkroom: darkroom))
        // The nameplate's Barlow Condensed ships with the app, shared with the Mac.
        if let font = Bundle.main.url(forResource: "BarlowCondensed-SemiBold", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            CameraView()
                .environment(darkroom)
                .environment(editor)
        }
    }
}
