import Foundation
import CoreMIDI
import OSCKit
import Yams

// --- CONFIGURATION ---

let MIDI_PORT_NAME = "Tangent Elements Bridge (Swift)"
let OSC_PORT: UInt16 = 9000

// --- CONFIGURATION & MAPPING MODELS (Decodable from YAML) ---

// Represents the root of the YAML file
struct Config: Decodable {
    let mappings: [MidiMapping]
}

// Represents the type of a mapping
enum MappingType: String, Decodable {
    case noteOnOff = "note_on_off"
    case ccAbsolute = "cc_absolute"
    case ccRelative = "cc_relative"
}

// Represents the value_map section for absolute CC controls
struct ValueMap: Decodable {
    let inMin: Float
    let inMax: Float
    let outMin: UInt8
    let outMax: UInt8

    enum CodingKeys: String, CodingKey {
        case inMin = "in_min"
        case inMax = "in_max"
        case outMin = "out_min"
        case outMax = "out_max"
    }
}

// Represents a single mapping item from the YAML file
struct MidiMapping: Decodable {
    let oscAddress: String
    let type: MappingType
    let channel: UInt8
    let control: UInt8
    let valueMap: ValueMap?

    enum CodingKeys: String, CodingKey {
        case oscAddress = "osc_address"
        case type, channel, control
        case valueMap = "value_map"
    }
}

// --- GLOBAL STATE ---
var ccValues: [UInt8: UInt8] = [:] // [control: value]

// --- MIDI MANAGER ---
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
        packet.timeStamp = 0
        packet.length = UInt16(bytes.count)
        withUnsafeMutableBytes(of: &packet.data) {
            $0.copyBytes(from: bytes)
        }
        var packetList = MIDIPacketList(numPackets: 1, packet: packet)
        MIDIReceived(source, &packetList)
    }
}

// --- CONFIGURATION LOADER ---
func loadConfig() -> [String: MidiMapping]? {
    let configFileName = "config.yaml"
    // Assume config.yaml is in the same directory as the executable
    let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    let configURL = executableURL.deletingLastPathComponent().appendingPathComponent(configFileName)

    print("Looking for config file at: \(configURL.path)")

    do {
        let yamlString = try String(contentsOf: configURL)
        let decoder = YAMLDecoder()
        let config = try decoder.decode(Config.self, from: yamlString)
        
        // Convert the array of mappings into a dictionary for fast lookups
        let mappingsDict = Dictionary(uniqueKeysWithValues: config.mappings.map { ($0.oscAddress, $0) })
        
        print("Successfully loaded \(mappingsDict.count) mappings from \(configFileName).")
        return mappingsDict
    } catch {
        print("---")
        print("Error loading or parsing \(configFileName): \(error)")
        print("Please ensure a valid '\(configFileName)' file exists in the same directory as the executable.")
        print("---")
        return nil
    }
}


// --- Main Application ---

print("--- Tangent to MIDI Bridge (Swift) ---")

// Load mappings from config file
guard let MIDI_MAPPINGS = loadConfig() else {
    exit(1)
}

// Global instance of the MIDI Manager
let midiManager = MIDIManager(name: MIDI_PORT_NAME)

guard midiManager != nil else {
    print("Fatal: Could not initialize MIDI Manager. Exiting.")
    exit(1)
}

// Set up the OSC Server using OSCKit
let oscServer = OSCServer(
    port: OSC_PORT,
    receiveQueue: DispatchQueue.global(qos: .background),
    handler: { message, _, _, _ in
        
        let address = message.addressPattern.stringValue
        let arguments = message.values
        
        guard let mapping = MIDI_MAPPINGS[address] else {
            print("Received unmapped OSC: \(address) \(arguments)")
            return
        }
        
        print("Received OSC: \(address) \(arguments)")

        var midiMessage: [UInt8] = []

        switch mapping.type {
        case .noteOnOff:
            guard let value = arguments.first as? Float32, (value == 0.0 || value == 1.0) else { return }
            let velocity: UInt8 = (value == 1.0) ? 127 : 0
            midiMessage = [0x90 | mapping.channel, mapping.control, velocity]

        case .ccAbsolute:
            guard let oscValue = arguments.first as? Float32,
                  let valueMap = mapping.valueMap else { return }
            
            let inSpan = valueMap.inMax - valueMap.inMin
            let outSpan = Float(valueMap.outMax - valueMap.outMin)
            let scaledValue = ((Float(oscValue) - valueMap.inMin) / inSpan) * outSpan + Float(valueMap.outMin)
            let midiValue = UInt8(max(Float(valueMap.outMin), min(Float(valueMap.outMax), scaledValue.rounded())))
            
            midiMessage = [0xB0 | mapping.channel, mapping.control, midiValue]

        case .ccRelative:
            guard let delta32 = arguments.first as? Int32 else { return }
            let delta = Int(delta32)
            
            let currentValue = ccValues[mapping.control, default: 64]
            var newValue = Int(currentValue) + delta
            newValue = max(0, min(127, newValue))
            let newMidiValue = UInt8(newValue)
            ccValues[mapping.control] = newMidiValue
            
            midiMessage = [0xB0 | mapping.channel, mapping.control, newMidiValue]
        }

        if !midiMessage.isEmpty {
            print("  -> Sending MIDI: \(midiMessage.map { String(format: "0x%02X", $0) }.joined(separator: " "))")
            midiManager?.send(bytes: midiMessage)
        }
    }
)

do {
    try oscServer.start()
    print("Listening for OSC messages on port \(OSC_PORT)")
} catch {
    print("Error: Could not start OSC Server. \(error.localizedDescription)")
    exit(1)
}

print("Application started. Press Ctrl+C to exit.")

RunLoop.main.run()
