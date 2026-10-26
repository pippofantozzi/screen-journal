import AppKit

/// Short cues for dictation, made with earshot's sound bank and tuned to one key (`Resources/Sounds`):
/// a pop when listening starts, a soft wooden tick when the writing starts, a rising chime once pasted.
@MainActor
enum Sounds {
    enum Cue: String {
        case start, working, done
    }

    private static var loaded: [Cue: NSSound] = [:]

    static func play(_ cue: Cue) {
        guard let sound = sound(cue) else { return }
        sound.stop()
        sound.play()
    }

    /// nil when the file is missing, as in a `swift run` build without the bundle.
    private static func sound(_ cue: Cue) -> NSSound? {
        if let sound = loaded[cue] { return sound }
        guard let url = Bundle.main.url(forResource: "dictation-\(cue.rawValue)", withExtension: "wav"),
              let sound = NSSound(contentsOf: url, byReference: true)
        else { return nil }
        loaded[cue] = sound
        return sound
    }
}
