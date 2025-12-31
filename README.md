# Track Day Racing 🏁

 high-speed racing experience for the F256 family of retro computers, created for the Oct-Dec 2025 F256 Game Jam.

## Overview

Track Day Racing is a top-down racing game featuring 80s arcade-style physics, AI-controlled opponents, and several racers to choose from. Race against three computer-controlled opponents on a scrolling race track with parallax effects and real-time speedometer display.

## Features

- **Player-Controlled Racing**: 80s-style physics with acceleration, braking, and steering
- **AI Opponents**: 3 intelligent computer-controlled cars with pathfinding
- **Chase Helicopter**: Helicopter sprite that follows the action
- **Track Position System**: Waypoint-based lap tracking
- **Collision Detection**: Car-to-car collisions with physics response
- **Parallax Scrolling**: Smooth tilemap-based track rendering
- **Real-Time Speedometer**: Live speed display during gameplay
- **Audio**: Background music (SID chip) and sound effects (PSG)
- **Animated Elements**: Crowds, starting lights, and environmental details

## System Requirements

### Hardware
- **Platform**: Foenix F256K, F256K2, F256Jr, or F256Jr2
- **CPU**: WDC 65C02 (8-bit mode on 65C816 hardware)
- **Graphics**: TinyVicky II (Tilemap + Sprite Engine)
- **Sound**: PSG + SID chip
- **Input**: Joystick

### Software
- Foenix Kernel (for event handling and hardware abstraction)

## Installation

1. Copy `race.pgz` to your Foenix system
2. Type `/- race.pgz` from your BASIC screen


## Controls

### Joystick (Recommended)
- **Up**: Accelerate
- **Down**: Brake/Reverse
- **Left/Right**: Steer left/right
- **Button**: Start race / Select options


## Gameplay

### Starting a Race
1. The game begins at the title screen
2. Press the joystick button to advance through the menu
3. Select your driver and number of laps
4. Watch the starting lights countdown
5. After all lights go dark, the race begins!

### Racing
- Accelerate to gain speed around the track
- Use the steering to navigate corners
- Stay on the track for optimal speed (off-road destroys performance)
- Avoid collisions with opponent cars
- Complete the required number of laps to finish

## Building from Source

### Prerequisites
- **Assembler**: 64tass (Turbo Assembler Macro V1.59.3120 or later)
### Build Command
```bash
64tass --output-exec=start --c256-pgz race.asm --output race.pgz
```
### Project Structure
```
Race/
├── race.asm                # Main program and game logic (7792 lines)
├── setup.asm               # Hardware register definitions
├── api.asm                 # Kernel API interface
├── race.pgz                # Compiled executable
│
├── Sprite Assets:
│   ├── bluecar.s           # Player car sprite data
│   ├── greencar.s          # AI opponent sprite
│   ├── redcar.s            # AI opponent sprite
│   ├── yellowcar.s         # AI opponent sprite
│   ├── helicopter_*.s      # Helicopter camera sprites
│   └── 8x8_sprites.s       # UI elements
│
├── Graphics Assets:
│   ├── track2a_tileset.s   # Race track tiles
│   ├── crowds_tileset.s    # Spectator graphics
│   ├── title_screen_set.s  # Title screen tiles
│   ├── speedo_set.s        # Speedometer graphics
│   └── portraits.s         # Driver portraits
│
└── Tilemap Data:
    ├── tilemap_road.tlm    # Main track layout
    ├── tilemap_speedo.tlm  # Speedometer overlay
    └── title_tilemap.tlm   # Title screen layout
```

## Technical Details

### Architecture
- **Memory**: Uses zero-page optimization for performance-critical variables
- **Graphics**: Hardware sprites (64 available) + 3 tilemap layers
- **AI**: Waypoint-based pathfinding with distance calculations
- **Physics**: Fixed-point math using hardware MULU/DIV/ADD accelerators
- **Event System**: Kernel-driven event loop (60Hz timer, joystick)

### Code Organization
- **Modular Design**: Separate sprite initialization, AI logic, physics, and rendering
- **Well-Documented**: Extensive inline comments explaining algorithms and data structures
- **Zero-Page Variables**: Optimized temporary storage for math operations ($60-$8F)
- **Hardware Acceleration**: Leverages F256 math coprocessor for performance

### Memory Map
- **Code**: Starts at $1000
- **Sprite Data**: Various locations in RAM
- **Tilemap Data**: Configured via TinyVicky II registers
- **Character RAM**: $C100+ (I/O page 1)
- **Zero-Page**: $60-$8F (temporary variables)

## Credits

**Author**: Michael Cassera  
**Year**: 2025  
**Platform**: Foenix F256 Family  
**Event**: Foenix Game Jam (Oct-Dec 2025)

## Additional Resources

- [Wildbits Computing Company](https://wildbitscomputing.com/)
- [64tass Assembler](https://sourceforge.net/projects/tass64/)

## Version History

- **v1.0** (Dec 2025): Initial release for Game Jam

---

*Ready, Set, Race! 🏁*
