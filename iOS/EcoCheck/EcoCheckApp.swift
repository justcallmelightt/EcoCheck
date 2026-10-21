import CoreText
import SwiftUI

@main
struct EcoCheckApp: App {
    init() {
        for weight in ["Regular", "Medium", "SemiBold", "Bold", "ExtraBold"] {
            guard let url = Bundle.main.url(
                forResource: "Pretendard-\(weight)",
                withExtension: "otf",
                subdirectory: "Fonts"
            ) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
