import AppKit

/// Plays a short cue when the internet drops or comes back. Uses the built-in system sounds so we
/// ship no audio assets, and `NSSound` is audible regardless of notification / Do-Not-Disturb
/// settings (unlike the banner notification's sound).
@MainActor
final class SoundPlayer {
    // Basso = a low "uh-oh" on loss; Glass = a bright ding on recovery. Swap names to retaste.
    private let lost = NSSound(named: "Basso")
    private let restored = NSSound(named: "Glass")

    func playLost() { play(lost) }
    func playRestored() { play(restored) }

    private func play(_ sound: NSSound?) {
        guard let sound else { return }
        if sound.isPlaying { sound.stop() }   // restart cleanly if a cue is still ringing
        sound.play()
    }
}
