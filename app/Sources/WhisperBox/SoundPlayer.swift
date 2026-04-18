import AudioToolbox
import Foundation

enum SoundPlayer {
    private static var startSound: SystemSoundID = {
        var soundID: SystemSoundID = 0
        let url = URL(fileURLWithPath: "/System/Library/Sounds/Tink.aiff")
        AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        return soundID
    }()

    private static var stopSound: SystemSoundID = {
        var soundID: SystemSoundID = 0
        let url = URL(fileURLWithPath: "/System/Library/Sounds/Pop.aiff")
        AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        return soundID
    }()

    static func playRecordStart() {
        AudioServicesPlaySystemSound(startSound)
    }

    static func playRecordStop() {
        AudioServicesPlaySystemSound(stopSound)
    }
}
