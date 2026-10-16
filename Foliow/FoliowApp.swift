import SwiftUI

@main
struct FoliowApp: App {
    @StateObject private var store = ReviewStore()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .tint(Palette.green)
                .preferredColorScheme(.light)
        }
    }
}

enum Palette {
    static let green = Color(red: 0.19, green: 0.34, blue: 0.27)
    static let background = Color(red: 0.97, green: 0.98, blue: 0.95)
    static let soft = Color(red: 0.90, green: 0.93, blue: 0.86)
    static let muted = Color(red: 0.49, green: 0.56, blue: 0.45)
    static let pass = Color(red: 0.68, green: 0.40, blue: 0.34)
}
