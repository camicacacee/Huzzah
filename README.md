<div align="center">

# Huzzah

**A close-combat video game with no controllers.**
**The front camera reads your movements — sword swings, blocks, magic — and turns them into in-game actions.**

![Platform](https://img.shields.io/badge/iPadOS-17%2B-lightgrey?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![Vision](https://img.shields.io/badge/Apple-Vision-blue?logo=apple)
![Speech](https://img.shields.io/badge/Apple-Speech-blue?logo=apple)

</div>

---

## The idea

What if the controller were your body?

No joystick, no touch — just the iPad in front of you and real-time skeleton tracking via **Apple Vision**. Physical combat is one of the few ways of playing that asks nothing of your fingers; *Wii Sports*, *Just Dance*, the Kinect installations all proved it works. Huzzah picks up that lesson and brings it to a device you already own, with no accessories, no external sensors — just a camera and a computer-vision framework.

## Game modes

| Mode | Combat | Defense |
|---|---|---|
| **⚔ Knight** | Wrist swing = sword attack. 1.5s cooldown. | Hand near the face = shield block. |
| **✦ Fairy** | Damage scales with swing speed — the faster, the harder. | None. Pure offense. |
| **✺ Wizard** *(soon)* | Hand gestures drawn in mid-air — spells recognized from the movement pattern. | TBD. |


## How it works

### Automatic calibration
A session starts by waiting for the player to be still — the system measures the variance of shoulder-Y across 20 frames. Once stability is detected, it collects 60 frames of baseline pose. The player isn't asked to do anything: they just stand there.

### Multi-player on the same screen
Up to two players are tracked simultaneously. Player identity (P1/P2) is preserved frame after frame by tracking the horizontal centroid of each body and matching it to the previous frame's assignment — even when players move sideways.

### Voice recalibration
A `SFSpeechRecognizer` listens in the background. The player can recalibrate mid-game by speaking a keyword, without pausing or returning to the menu.

### Damage logic
Attack only registers if the visualized weapon tip (drawn from the player's wrist position) intersects the opponent's body rectangle in the frame. Block cancels incoming damage. A 1.5s cooldown applies to both players' incoming-hit windows to prevent combo abuse.

## Architecture

```
battaglia/
├── battagliaApp.swift          — app entry
├── ContentView.swift           — SwiftUI menu (1 or 2 players)
├── TrackingViewController.swift— UIKit host, camera + skeleton + HUD
├── BodyTrackingDelegate.swift  — CameraManager, AVCaptureSession,
│                                  Vision pose detection, P1/P2 assignment
├── PlayerAction.swift          — BodyAnalyzer:
│                                  calibration · smoothing ·
│                                  attack/block detection ·
│                                  hold-and-cooldown FSM
└── sword.usdz                  — 3D asset
```

### Stack

| Layer | Technology |
|---|---|
| UI shell | SwiftUI |
| Real-time view | UIKit (`UIViewControllerRepresentable`) |
| Body tracking | Vision (`VNDetectHumanBodyPoseRequest`) |
| Camera pipeline | AVFoundation (`AVCaptureSession`) |
| Voice commands | Speech (`SFSpeechRecognizer`) |
| Reactivity | Combine |

## Run it

Requires iPadOS 17+ and an iPad with a front camera.

```bash
git clone https://github.com/camicacacee/Huzzah.git
cd Huzzah
open battaglia.xcodeproj
```

Build & run on a physical iPad (the simulator has no camera). Grant the app camera and microphone permissions on first launch.

## Credits

Developed by **Camilla Cacace** — all code: body-tracking pipeline, frame analysis, combat mechanics, speech recognition layer.

📍 Naples, Italy
🌐 [camillacacace.com](https://camillacacace.com)
