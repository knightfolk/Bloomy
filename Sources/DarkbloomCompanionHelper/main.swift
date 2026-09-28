import Foundation

@main
enum CompanionHelperMain {
    static func main() {
        // Packaging, signed identity, and local approval are wired by the app.
        // A standalone SwiftPM launch has no provider, listener, or authority.
        FileHandle.standardError.write(Data("Darkbloom companion helper requires signed app registration.\n".utf8))
    }
}
