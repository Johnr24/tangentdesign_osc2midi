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


This will download the necessary dependencies (like SwiftOSC) and compile the application. The first build might take a minute. The final executable will be placed in the `.build/debug/` directory.

### 3. Configure Your Tangent Controller

You need to configure your Tangent controller to send OSC messages to your computer's IP address.

1.  **Find your Mac's IP Address**: Go to `System Settings` > `Wi-Fi` (or `Ethernet`), click on the `Details...` button for your active network connection, and find your IP Address under the `TCP/IP` tab. It will look something like `192.168.1.100`.
2.  **Configure Tangent Mapper**:
    - Open the Tangent Mapper application.
    - Go to the "Configuration" tab.
    - Set the protocol to **OSC**.
    - Set the **Host** to your Mac's IP address.
    - Set the **Port** to `9000` (or whatever you configure in `main.swift`).
    - Make sure the controller is active and sending data.

### 4. Run the Bridge Application

In the same Terminal window (still in the project's root folder), you can run the application using the Swift command:

Alternatively, you can run the compiled executable directly:
