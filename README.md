# Tangent to MIDI Bridge for DJAY Pro

This application acts as a bridge, converting OSC (Open Sound Control) messages from a Tangent Elements controller into MIDI messages that DJAY Pro can understand.

It creates a virtual MIDI device on your Mac, listens for commands from your Tangent controller over the network, and translates them into MIDI signals in real-time.

## Features

- Creates a virtual MIDI port on macOS, visible to any MIDI-aware application.
- Listens for OSC messages on a configurable IP address and port.
- Provides a simple, customizable Python dictionary to map OSC messages to MIDI notes or Control Change (CC) messages.
- Supports different control types:
  - **Buttons**: Map to MIDI Note On/Off messages.
  - **Absolute Controls (Faders)**: Map OSC values (e.g., 0.0-1.0) to MIDI CC values (0-127).
  - **Relative Controls (Knobs/Jog Wheels)**: Accumulates delta values from the controller to produce smooth MIDI CC changes.

## Requirements

- A Mac running macOS.
- Python 3 installed. You can check by running `python3 --version` in your Terminal. If not installed, you can install it from [python.org](https://www.python.org/downloads/) or using [Homebrew](https://brew.sh/) (`brew install python`).
- A Tangent Elements controller (or any other device that can send OSC messages).

## Setup Instructions

### 1. Download Files

Download the files from this project into a new folder on your computer:
- `tangent_to_midi.py`
- `requirements.txt`

### 2. Install Dependencies

Open the Terminal app on your Mac, navigate to the folder where you saved the files, and run the following command to install the necessary Python libraries:

