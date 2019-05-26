// Code inside modules can be shared between pages and other source files.
import Foundation
import AudioToolbox
import CoreAudio

let roots = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
let chord_intervals = ["M":[0,4,7], "m":[0,3,7], "M7":[0,4,7,11], "7":[0,4,7,10], "M9":[0,2,4,7],
                       "m7":[0,3,7,10], "m9":[0,2,3,7], "6":[0,4,7,9], "m6":[0,3,7,9], "m7#5":[0,3,8,10],
                       "mM7":[0,3,7,11], "aug":[0,4,8], "aug9":[0,2,4,8],
                       "dim":[0,3,6], "dim7":[0,3,6,9], "sus4":[0,5,7], "7sus4":[0,5,7,10], "7#5":[0,4,8,10],
                       "m7b5":[0,3,6,10], "5":[0,7], "1":[0]]

// MIDIナンバーの定義。直下の音名ファイル名も同じ並びになるようにセットで管理すること
let midibass = [48,49,50,51,52,53,54,55,56,57,58,59]
let midikeys = [60,61,62,63,64,65,66,67,68,69,70,71]

// Chord Structure Manager
public class ResourceManager: NSObject {
    public static func getMIDIBass() -> [Int] {
        return midibass
    }
    public static func getMIDIKeys() -> [Int] {
        return midikeys
    }
    public static func getRootNames() -> [String] {
        return roots
    }
    public static func getChordIntervals(chord_style: String) -> [Int] {
        return chord_intervals[chord_style]!
    }
}

// MIDI Synthesizer Controller (Player)
public class AudioUnitMIDISynth: NSObject {
    var processingGraph: AUGraph?
    var midisynthNode   = AUNode()
    var ioNode          = AUNode()
    var midisynthUnit: AudioUnit?
    var ioUnit: AudioUnit?
    var musicSequence: MusicSequence!
    var musicPlayer: MusicPlayer!
    let patch          = UInt32(0)    /// Piano
    var pitches: [UInt32] = []
    
    public override init() {
        super.init()
        augraphSetup()
        loadMIDISynthSoundFont()
        initializeGraph()
        startGraph()
    }
    
    func augraphSetup() {
        var status = OSStatus(noErr)
        
        status = NewAUGraph(&processingGraph)
        createIONode()
        createSynthNode()
        
        // now do the wiring. The graph needs to be open before you call AUGraphNodeInfo
        status = AUGraphOpen(self.processingGraph!)
        status = AUGraphNodeInfo(self.processingGraph!, self.midisynthNode, nil, &midisynthUnit)
        status = AUGraphNodeInfo(self.processingGraph!, self.ioNode, nil, &ioUnit)
        
        let synthOutputElement: AudioUnitElement = 0
        let ioUnitInputElement: AudioUnitElement = 0
        
        status = AUGraphConnectNodeInput(self.processingGraph!,
                                         self.midisynthNode, synthOutputElement, // srcnode, SourceOutputNumber
            self.ioNode, ioUnitInputElement) // destnode, DestInputNumber
    }
    
    /// Create the Output Node and add it to the `AUGraph`.
    func createIONode() {
        var cd = AudioComponentDescription(
            componentType: OSType(kAudioUnitType_Output),
            componentSubType: OSType(kAudioUnitSubType_RemoteIO),
            componentManufacturer: OSType(kAudioUnitManufacturer_Apple),
            componentFlags: 0, componentFlagsMask: 0)
        let status = AUGraphAddNode(self.processingGraph!, &cd, &ioNode)
    }
    
    /// Create the Synth Node and add it to the `AUGraph`.
    func createSynthNode() {
        var cd = AudioComponentDescription(
            componentType: OSType(kAudioUnitType_MusicDevice),
            componentSubType: OSType(kAudioUnitSubType_MIDISynth),
            componentManufacturer: OSType(kAudioUnitManufacturer_Apple),
            componentFlags: 0, componentFlagsMask: 0)
        let status = AUGraphAddNode(self.processingGraph!, &cd, &midisynthNode)
        
    }
    
    let soundFontFileName = "Perfect Sine"
    let soundFontFileExt = "sf2"
    func loadMIDISynthSoundFont() {
        if var bankURL = Bundle.main.url(forResource: soundFontFileName, withExtension: soundFontFileExt) {
            let status = AudioUnitSetProperty(
                self.midisynthUnit!,
                AudioUnitPropertyID(kMusicDeviceProperty_SoundBankURL),
                AudioUnitScope(kAudioUnitScope_Global),
                0,
                &bankURL,
                UInt32(MemoryLayout<URL>.size))
            
            AudioUnitSetParameter(self.midisynthUnit!,
                                  127,
                                  kAudioUnitScope_Global,
                                  0,
                                  127,
                                  0);
            
        } else {
            print("Could not load sound font")
        }
        print("loaded sound font")
    }
    
    func loadPatches() {
        if !isGraphInitialized() {
            fatalError("initialize graph first")
        }
        
        let channel = UInt32(0)
        var enabled = UInt32(1)
        
        var status = AudioUnitSetProperty(
            self.midisynthUnit!,
            AudioUnitPropertyID(kAUMIDISynthProperty_EnablePreload),
            AudioUnitScope(kAudioUnitScope_Global),
            0,
            &enabled,
            UInt32(MemoryLayout<UInt32>.size))
        
        let pcCommand = UInt32(0xC0 | channel)
        status = MusicDeviceMIDIEvent(self.midisynthUnit!, pcCommand, patch, 0, 0)
        
        enabled = UInt32(0)
        status = AudioUnitSetProperty(
            self.midisynthUnit!,
            AudioUnitPropertyID(kAUMIDISynthProperty_EnablePreload),
            AudioUnitScope(kAudioUnitScope_Global),
            0,
            &enabled,
            UInt32(MemoryLayout<UInt32>.size))
    }
    
    func isGraphInitialized() -> Bool {
        var outIsInitialized = DarwinBoolean(false)
        let status = AUGraphIsInitialized(self.processingGraph!, &outIsInitialized)
        return outIsInitialized.boolValue
    }
    
    func initializeGraph() {/// Initializes the `AUGraph.
        let status = AUGraphInitialize(self.processingGraph!)
    }
    func startGraph() {
        let status = AUGraphStart(self.processingGraph!)
    }
    func isGraphRunning() -> Bool {
        var isRunning = DarwinBoolean(false)
        let status = AUGraphIsRunning(self.processingGraph!, &isRunning)
        return isRunning.boolValue
    }
    
    // Public Method 1: ルートとコード形を指定して音を鳴らす。止めるまで鳴り続ける
    public func playPatchOn(bass: String?, chord: String?) {
        /// Send a note on message using patch on channel 0
        let channel = UInt32(0)
        let noteCommand = UInt32(0x90 | channel)
        let pcCommand = UInt32(0xC0 | channel)
        var status = OSStatus(noErr)
        
        playPatchOff()
        pitches = []
        var rootpos = 0
        if bass != nil {
            rootpos = ResourceManager.getRootNames().index(of: bass!)!
            if chord == nil {
                pitches.append(UInt32(ResourceManager.getMIDIKeys()[rootpos]))
            } else {
                pitches.append(UInt32(ResourceManager.getMIDIBass()[rootpos]))
            }
        } else {
            return
        }
        if chord != nil {
            let chord = ResourceManager.getChordIntervals(chord_style: chord!)
            for k in chord {
                pitches.append(UInt32(ResourceManager.getMIDIKeys()[(k+rootpos)%12]))
            }
        }
        for p in pitches {
            status = MusicDeviceMIDIEvent(self.midisynthUnit!, pcCommand, patch, 0, 0)
            status = MusicDeviceMIDIEvent(self.midisynthUnit!, noteCommand, p, 64, 0)
        }
    }
    
    // Public Method 2: 音を止める
    public func playPatchOff() {
        let channel = UInt32(0)
        let noteCommand = UInt32(0x80 | channel)
        var status = OSStatus(noErr)
        for p in pitches {
            status = MusicDeviceMIDIEvent(self.midisynthUnit!, noteCommand, p, 127, 0)
        }
    }
}
