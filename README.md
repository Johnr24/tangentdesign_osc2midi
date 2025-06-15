# Tangent to MIDI Bridge (Swift)

This application acts as a bridge, converting OSC (Open Sound Control) messages from a Tangent Elements controller into MIDI messages that DJAY Pro can understand. This is a Swift version, designed to be compiled and run natively on macOS.

It creates a virtual MIDI device on your Mac, listens for commands from your Tangent controller over the network, and translates them into MIDI signals in real-time.

## Requirements

- A Mac running macOS 10.15 or newer.
- Xcode Command Line Tools installed. If you don't have them, run `xcode-select --install` in your Terminal.
- A Tangent Elements controller (or any other device that can send OSC messages).

## Setup and Run Instructions

### 1. Create the Project Structure

Create a new folder for the project. Inside that folder, you must create the following file structure and copy the code into the files:

- `Package.swift` (file)
- `Sources/` (folder)
  - `TangentToMidi/` (folder)
    - `main.swift` (file)

### 2. Build the Application

Open the Terminal app, navigate to the root of your project folder (the one containing `Package.swift`), and run the build command:

