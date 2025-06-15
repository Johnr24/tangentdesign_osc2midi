# tangent_to_midi.py

import mido
import time
import threading
from pythonosc import dispatcher
from pythonosc import osc_server


# --- CONFIGURATION ---

# Network settings for the OSC server
OSC_IP = "0.0.0.0"  # Listen on all available network interfaces
OSC_PORT = 9000      # The port to listen on. Make sure your Tangent controller sends to this port.

# MIDI settings
MIDI_PORT_NAME = 'Tangent Elements Bridge' # The name of the virtual MIDI device DJAY Pro will see.

# --- OSC to MIDI Mapping ---
# This is the core of the translator. You need to customize this section.
#
# How to find your controller's OSC messages:
# 1. Use the Tangent Mapper software to see what OSC messages are sent for each control.
# 2. Or, you can see all incoming messages in the console when you run this script.
#
# MAPPING FORMAT:
#   'osc_address': {
#       'type': 'note_on_off', 'cc_absolute', or 'cc_relative',
#       'channel': MIDI channel (0-15),
#       'control' or 'note': MIDI note number (0-127) or CC number (0-127),
#       'value_map': (optional) for cc_absolute, maps OSC value range to MIDI value range
#   }

MIDI_MAPPING = {
    # --- Example for a Button (like Play/Pause) ---
    # This maps a button press/release to a MIDI Note On/Off message.
    # Assumes the button sends 1 on press and 0 on release.
    "/tangent/bt/A/press": {
        "type": "note_on_off",
        "channel": 0,
        "note": 60,  # Middle C
    },

    # --- Example for a Knob (like an EQ control) ---
    # This maps a knob's movement to a MIDI Control Change (CC) message.
    # Tangent knobs often send delta (change) values. We'll accumulate them.
    # This example maps it to CC #20.
    "/tangent/kn/A/delta": {
        "type": "cc_relative",
        "channel": 0,
        "control": 20,
    },

    # --- Example for a Jog Wheel ---
    # This maps a jog wheel's movement to a different CC message.
    "/tangent/wh/A/delta": {
        "type": "cc_relative",
        "channel": 0,
        "control": 21,
    },
    
    # --- Example for a Fader/Slider (Absolute Position) ---
    # This maps a control that sends its absolute position (e.g., 0.0 to 1.0)
    # to a MIDI CC message (0 to 127).
    "/tangent/sl/A/value": {
        "type": "cc_absolute",
        "channel": 0,
        "control": 22,
        "value_map": {"in_min": 0.0, "in_max": 1.0, "out_min": 0, "out_max": 127}
    }
}

# --- Global State ---
# To store the current value for relative CC controls
cc_values = {} 

# --- Main Application Logic ---

def scale_value(value, in_min, in_max, out_min, out_max):
    """Helper function to scale a value from one range to another."""
    # Clamp the value to the input range
    value = max(in_min, min(in_max, value))
    # Perform the scaling
    in_span = in_max - in_min
    out_span = out_max - out_min
    scaled = float(value - in_min) / float(in_span)
    return int(out_min + (scaled * out_span))

def osc_handler(address, *args):
    """Handles incoming OSC messages and translates them to MIDI."""
    global midi_out_port
    print(f"Received OSC: {address} {args}")

    if address in MIDI_MAPPING:
        mapping = MIDI_MAPPING[address]
        msg = None

        try:
            if mapping["type"] == "note_on_off":
                # For buttons that send 1 on press, 0 on release
                velocity = 127 if args[0] > 0 else 0
                msg = mido.Message('note_on', channel=mapping['channel'], note=mapping['note'], velocity=velocity)

            elif mapping["type"] == "cc_absolute":
                # For controls sending an absolute value (e.g., 0.0 to 1.0)
                osc_val = args[0]
                v_map = mapping['value_map']
                midi_val = scale_value(osc_val, v_map['in_min'], v_map['in_max'], v_map['out_min'], v_map['out_max'])
                msg = mido.Message('control_change', channel=mapping['channel'], control=mapping['control'], value=midi_val)

            elif mapping["type"] == "cc_relative":
                # For knobs/wheels sending delta values
                delta = int(args[0])
                control = mapping['control']
                
                # Initialize current value if not present
                if control not in cc_values:
                    cc_values[control] = 64 # Start at center
                
                # Update value and clamp to 0-127
                cc_values[control] = max(0, min(127, cc_values[control] + delta))
                
                msg = mido.Message('control_change', channel=mapping['channel'], control=mapping['control'], value=cc_values[control])

            if msg:
                print(f"  -> Sending MIDI: {msg}")
                midi_out_port.send(msg)

        except Exception as e:
            print(f"Error processing message for {address}: {e}")

def main():
    global midi_out_port

    # Explicitly set the Mido backend to portmidi.
    # This backend supports virtual ports on macOS, but requires the
    # PortMidi library to be installed on the system.
    try:
        mido.set_backend('mido.backends.portmidi')
    except Exception as e:
        print(f"Warning: Could not set mido backend to portmidi. Will use default. Error: {e}")

    print("--- Tangent to MIDI Bridge ---")

    # Create a virtual MIDI output port
    try:
        midi_out_port = mido.open_output(MIDI_PORT_NAME, virtual=True)
        print(f"Successfully created virtual MIDI port: '{MIDI_PORT_NAME}'")
    except Exception as e:
        print(f"Error: Could not create virtual MIDI port. Is a MIDI backend installed?")
        print(f"On macOS, this requires the PortMidi library.")
        print(f"Try installing it with Homebrew: 'brew install portmidi'")
        print(f"Then reinstall the python wrapper: 'pip install --force-reinstall python-portmidi'")
        print(f"Details: {e}")
        return

    # Set up OSC server
    disp = dispatcher.Dispatcher()
    # Map all addresses to our generic handler
    disp.set_default_handler(osc_handler)

    server = osc_server.ThreadingOSCUDPServer((OSC_IP, OSC_PORT), disp)
    print(f"Listening for OSC messages on {server.server_address}")

    # Run the server in a separate thread
    server_thread = threading.Thread(target=server.serve_forever)
    server_thread.daemon = True
    server_thread.start()

    print("Application started. Press Ctrl+C to exit.")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()
        midi_out_port.close()
        print("Goodbye!")

if __name__ == "__main__":
    main()
