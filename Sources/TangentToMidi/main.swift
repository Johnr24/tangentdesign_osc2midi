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

        // Use a buffer to construct the MIDIPacketList in the format CoreMIDI expects.
        // This is the recommended way to handle variable-size C structs in Swift.
        var buffer = [UInt8](repeating: 0, count: 1024)
        
        buffer.withUnsafeMutableBufferPointer { bufferPtr in
            guard let baseAddress = bufferPtr.baseAddress else { return }
            
            let packetList = UnsafeMutablePointer<MIDIPacketList>(OpaquePointer(baseAddress))
            
            var currentPacket = MIDIPacketListInit(packetList)
            
            currentPacket = MIDIPacketListAdd(
                packetList,
                bufferPtr.count,
                currentPacket,
                0, // timestamp (0 = now)
                bytes.count,
                bytes
            )
            
            MIDIReceived(source, packetList)
        }
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
            var isOn: Bool? = nil
            if let floatValue = arguments.first as? Float32 {
                if floatValue == 1.0 { isOn = true }
                else if floatValue == 0.0 { isOn = false }
            } else if let intValue = arguments.first as? Int32 {
                if intValue == 1 { isOn = true }
                else if intValue == 0 { isOn = false }
            }

            guard let noteState = isOn else {
                print("  -> OSC for noteOnOff (\(mapping.oscAddress)): argument not 0 or 1. Value: \(String(describing: arguments.first))")
                return
            }

            if noteState {
                // Note On: 0x90 | channel, note, velocity
                midiMessage = [0x90 | mapping.channel, mapping.control, 127]
            } else {
                // Note Off: 0x80 | channel, note, velocity (0)
                midiMessage = [0x80 | mapping.channel, mapping.control, 0]
            }

        case .ccAbsolute:
            var floatOscValue: Float?
            if let val = arguments.first as? Float32 {
                floatOscValue = val
            } else if let val = arguments.first as? Int32 {
                floatOscValue = Float(val)
            }

            guard let oscValue = floatOscValue,
                  let valueMap = mapping.valueMap else {
                print("  -> OSC for ccAbsolute (\(mapping.oscAddress)): argument not a valid number or no valueMap. Value: \(String(describing: arguments.first))")
                return
            }
            
            var finalMidiValue: UInt8
            if valueMap.inMin == valueMap.inMax {
                // print("  -> OSC for ccAbsolute (\(mapping.oscAddress)): inMin (\(valueMap.inMin)) and inMax (\(valueMap.inMax)) are the same. Clamping output based on comparison to inMin.")
                if oscValue <= valueMap.inMin {
                    finalMidiValue = valueMap.outMin
                } else {
                    finalMidiValue = valueMap.outMax
                }
            } else {
                let inSpan = valueMap.inMax - valueMap.inMin // Guaranteed non-zero by the check above
                let outSpan = Float(valueMap.outMax - valueMap.outMin)
                
                // Scale the OSC value to the MIDI output range.
                let scaledValue = ((oscValue - valueMap.inMin) / inSpan) * outSpan + Float(valueMap.outMin)
                
                // Clamp the result to the defined MIDI output range (outMin/outMax).
                finalMidiValue = UInt8(max(Float(valueMap.outMin), min(Float(valueMap.outMax), scaledValue.rounded())))
            }
            
            midiMessage = [0xB0 | mapping.channel, mapping.control, finalMidiValue]

        case .ccRelative:
            var delta: Int?
            if let intVal = arguments.first as? Int32 {
                delta = Int(intVal)
            } else if let floatVal = arguments.first as? Float32 {
                delta = Int(floatVal.rounded()) // Round float to nearest integer for delta
            }

            guard let actualDelta = delta else {
                print("  -> OSC for ccRelative (\(mapping.oscAddress)): argument not a valid integer or float. Value: \(String(describing: arguments.first))")
                return
            }
            
            let currentValue = ccValues[mapping.control, default: 64] // Default to middle value (64)
            var newValue = Int(currentValue) + actualDelta
            newValue = max(0, min(127, newValue)) // Clamp to MIDI range 0-127
            let newMidiValue = UInt8(newValue)
            ccValues[mapping.control] = newMidiValue // Store the new state for this control
            
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
