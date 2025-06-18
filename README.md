# Tangent to MIDI Bridge (Swift)

This application acts as a bridge, converting OSC (Open Sound Control) messages from a Tangent Elements controller into MIDI messages that DJAY Pro can understand. This is a Swift version, designed to be compiled and run natively on macOS.

It creates a virtual MIDI device on your Mac, listens for commands from your Tangent controller over the network, and translates them into MIDI signals in real-time.
