import AppKit

// AppKit accessory-app entry point (file is intentionally NOT named main.swift so @main applies).
@main
enum NetCheckMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon (with LSUIElement)
        app.run()
    }
}
