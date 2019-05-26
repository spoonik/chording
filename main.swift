import UIKit
let chord_player = AudioUnitMIDISynth()
while true {
    chord_player.playPatchOn(bass: "A", chord: "m7")
    sleep(3)
    chord_player.playPatchOff()
    sleep(1)
}
