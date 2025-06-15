import Foundation
import CoreMIDI
import SwiftOSC

// --- CONFIGURATION ---

let MIDI_PORT_NAME = "Tangent Elements Bridge (Swift)"
let OSC_PORT = 9000

// --- MIDI MAPPING ---
struct MidiMapping {
    enum MappingType {
        case noteOnOff
        case ccAbsolute
        case ccRelative
    }
    let type: MappingType
    let channel: UInt8 // 0-15
    let control: UInt8 // MIDI Note or CC number (0-127)
    // For ccAbsolute
    let inMin: Float?
    let inMax: Float?
    let outMin: UInt8?
    let outMax: UInt8?
}

// This is the main dictionary you will edit to customize your controls.
let MIDI_MAPPINGS: [String: MidiMapping] = [
    // --- Example for a Button (like Play/Pause) ---
    "/tangent/bt/A/press": MidiMapping(type: .noteOnOff, channel: 0, control: 60),

    // --- Example for a Knob (like an EQ control) ---
    "/tangent/kn/A/delta": MidiMapping(type: .ccRelative, channel: 0, control: 20),

    // --- Example for a Jog Wheel ---
    "/tangent/wh/A/delta": MidiMapping(type: .ccRelative, channel: 0, control: 21),
    
    // --- Example for a Fader/Slider (Absolute Position) ---
    "/tangent/sl/A/value": MidiMapping(type: .ccAbsolute, channel: 0, control: 22, inMin: 0.0, inMax: 1.0, outMin: 0, outMax: 127)
]

// --- GLOBAL STATE ---
var ccValues: [UInt8: UInt8] = [:] // [control: value]

// --- MIDI MANAGER ---
// This class handles creating the virtual MIDI port and sending messages.
class MIDIManager {
    private var client: MIDIClientRef = 0
    private var source: MIDIEndpointRef = 0

    init?(name: String) {
        let status = MIDIClientCreate(name as CFString, nil, nil, &client)
        if status != noErr {
            print("Error creating MIDI client: \(status)")
            return nil
        }

        let sourceStatus = MIDISourceCreate(client, name as CFString, &source)
        if sourceStatus != noErr {
            print("Error creating MIDI source: \(sourceStatus)")
            MIDIClientDispose(client)
            return nil
        }
        print("Successfully created virtual MIDI port: '\(name)'")
    }

    deinit {
        MIDIEndpointDispose(source)
        MIDIClientDispose(client)
        print("MIDI resources cleaned up.")
    }

    func send(bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }

        var packet = MIDIPacket()
        packet.timeStamp = 0 // Send immediately
        packet.length = UInt16(bytes.count)
        
        // Copy the MIDI message bytes into the packet data structure.
        withUnsafeMutableBytes(of: &packet.data) { (rawBufferPointer) in
            let bufferPointer = rawBufferPointer.bindMemory(to: UInt8.self)
            bufferPointer.baseAddress!.initialize(from: bytes, count: bytes.count)
        }

        var packetList = MIDIPacketList(numPackets: 1, packet: packet)
        
        // Send the packet to the virtual source.
        MIDIReceived(source, &packetList)
    }
}

// --- OSC to MIDI Translator ---
// This function is called for every incoming OSC message.
func handleOSCMessage(address: String, arguments: [Any]) {
    guard let mapping = MIDI_MAPPINGS[address] else {
        print("Received unmapped OSC: \(address) \(arguments)")
        return
    }
    
    print("Received OSC: \(address) \(arguments)")

    var midiMessage: [UInt8] = []

    switch mapping.type {
    case .noteOnOff:
        guard let value = arguments.first as? Float, (value == 0.0 || value == 1.0) else { return }
        let velocity: UInt8 = (value == 1.0) ? 127 : 0
        // Note On message: 0x90 | channel, note, velocity
        midiMessage = [0x90 | mapping.channel, mapping.control, velocity]

    case .ccAbsolute:
        guard let oscValue = arguments.first as? Float,
              let inMin = mapping.inMin, let inMax = mapping.inMax,
              let outMin = mapping.outMin, let outMax = mapping.outMax else { return }
        
        // Scale value from OSC range (e.g., 0.0-1.0) to MIDI range (0-127)
        let inSpan = inMax - inMin
        let outSpan = Float(outMax - outMin)
        let scaledValue = ((oscValue - inMin) / inSpan) * outSpan + Float(outMin)
        let midiValue = UInt8(max(Float(outMin), min(Float(outMax), scaledValue.rounded())))
        
        // Control Change message: 0xB0 | channel, control, value
        midiMessage = [0xB0 | mapping.channel, mapping.control, midiValue]

    case .ccRelative:
        guard let delta = arguments.first as? Int else { return }
        
        // Get current value, default to 64 (center)
        let currentValue = ccValues[mapping.control, default: 64]
        
        // Calculate new value and clamp between 0-127
        var newValue = Int(currentValue) + delta
        newValue = max(0, min(127, newValue))
        
        let newMidiValue = UInt8(newValue)
        ccValues[mapping.control] = newMidiValue
        
        // Control Change message: 0xB0 | channel, control, value
        midiMessage = [0xB0 | mapping.channel, mapping.control, newMidiValue]
    }

    if !midiMessage.isEmpty {
        print("  -> Sending MIDI: \(midiMessage.map { String(format: "0x%02X", $0) }.joined(separator: " "))")
        midiManager?.send(bytes: midiMessage)
    }
}

// --- OSC Server Delegate ---
// This class handles incoming OSC messages, conforming to the new library's API.
class OSCHandler: OSCServerDelegate {
    func didReceive(_ message: OSCMessage) {
        handleOSCMessage(address: message.address.string, arguments: message.arguments)
    }
}


// --- Main Application ---

print("--- Tangent to MIDI Bridge (Swift) ---")

// Global instance of the MIDI Manager
let midiManager = MIDIManager(name: MIDI_PORT_NAME)

guard midiManager != nil else {
    print("Fatal: Could not initialize MIDI Manager. Exiting.")
    exit(1)
}

// Set up the OSC Server using the delegate pattern
let server = OSCServer(address: "", port: OSC_PORT)
server.delegate = OSCHandler()
server.start()

print("Listening for OSC messages on port \(OSC_PORT)")
print("Application started. Press Ctrl+C to exit.")

// Keep the application running until it's terminated (e.g., with Ctrl+C)
RunLoop.main.run()
