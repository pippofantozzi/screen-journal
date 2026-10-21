import Foundation
import JournalCore

/// Runs a journal command and exits when asked for one; otherwise starts the menu bar app.
@main
enum Entry {
    static func main() {
        switch Launch.parse(CommandLine.arguments, timeZone: .current) {
        case .app:
            ScreenJournalApp.main()
        case let .command(command, root):
            exit(JournalCLI(command: command, root: root).run())
        case .invalid(let message):
            FileHandle.standardError.write(Data((message + "\n").utf8))
            exit(2)
        }
    }
}
