<div align="center">

  <img src="lib/logo.png" alt="ResoHertz Logo" width="120" height="120" />

  # ResoHertz

  **Digital Signal Processing Guitar Tuner & Pitch Estimation Architecture**

  [![Developer](https://img.shields.io/badge/Developer-%C2%A9BAZUD3V-0055A4)](https://github.com)
  [![Platform](https://img.shields.io/badge/Platform-Android-003366)](https://github.com)
  [![Tests](https://img.shields.io/badge/Tests-113%20Passed-0055A4)](https://github.com)
  [![Status](https://img.shields.io/badge/Status-Proprietary-darkred)](https://github.com)

</div>

---

## System Architecture

ResoHertz is an offline digital signal processing application for monophonic fundamental frequency estimation, guitar string tracking, and real-time transient stabilization.

The following UML flowchart outlines the data pipeline from raw audio ingestion to visualization and feedback suppression:

```mermaid
graph TD
    subgraph Audio Acquisition
        MIC["Microphone Hardware (PCM Stream)"]
        SVC["MicrophoneService (Platform MethodChannel)"]
        CAP["AudioCaptureService (44.1 kHz, 16-bit PCM)"]
        MIC --> SVC --> CAP
    end

    subgraph Signal Processing Pipeline
        YIN["YinPitchDetector Engine"]
        DIFF["Difference Function: d_t(tau)"]
        CMNDF["Cumulative Mean Normalized Difference Function: d'_t(tau)"]
        THRESH["Absolute Threshold Selection (0.15 Dip Search)"]
        INTERP["Parabolic Interpolation (Sub-Sample Accuracy)"]

        CAP --> YIN
        YIN --> DIFF --> CMNDF --> THRESH --> INTERP
    end

    subgraph Analysis & Pitch Stabilization
        ENG["TunerEngine (String Mapping & Cents Calculation)"]
        STAB["PitchStabilizer Pipeline"]
        DEAD["Stage 1: Micro Dead-Band (< 0.25 Cents Noise Rejection)"]
        SMOOTH["Stage 2A: Adaptive Exponential Smoothing (< 2.5 Cents)"]
        SNAP["Stage 2B: Transient Snap (> 7.0 Cents / Target Switch)"]
        LOCK["Stage 3: Zero-Center Deadlock (|cents| <= 0.8)"]

        INTERP --> ENG
        ENG --> STAB
        STAB --> DEAD
        DEAD --> SMOOTH
        DEAD --> SNAP
        SMOOTH --> LOCK
        SNAP --> LOCK
    end

    subgraph Interface & Hardware Feedback
        SCALE["Horizontal Scale & Guitar-Pick Marker"]
        HEAD["6-String Headstock Peg Matrix"]
        CHIME["AudioFeedbackPlayer (In-Tune Chime)"]
        SUPPR["Microphone Mute Suppression Gate"]

        LOCK --> SCALE
        ENG --> HEAD
        LOCK --> CHIME
        CHIME -. Disables audio frame ingestion while playing .-> SUPPR
        SUPPR -. Inhibits input loop .-> CAP
    end
```

---

## Technical Specifications

| Parameter | Specification |
| :--- | :--- |
| **Audio Ingestion** | 44,100 Hz, 16-bit Signed Linear PCM, Mono Channel |
| **Analysis Window** | 2,048 samples (~46.4 ms buffer duration) |
| **Algorithm** | YIN Fundamental Frequency Estimator with Parabolic Interpolation |
| **Detection Bandwidth** | 60.0 Hz to 450.0 Hz (covers C2 to A4 register) |
| **CMNDF Threshold** | 0.15 strict fundamental extraction |
| **In-Tune Tolerance** | +/- 3.0 Cents window |
| **Stabilizer Dead-Band** | 0.25 Cents sub-acoustic noise gate |
| **Reference Calibration** | 415.0 Hz to 466.0 Hz (Default: A4 = 440.0 Hz) |
| **Acoustic Feedback Protection** | Dynamic frame discard during chime playback |

---

## Functional Subsystems

### 1. Pitch Detection Engine
- Implements cumulative mean normalized difference processing over real-time PCM ring buffers.
- Applies parabolic fitting on candidate minima to achieve continuous sub-cent frequency resolution.
- Enforces an absolute minimum energy threshold to prevent false positives from ambient room sound.

### 2. Dual-Stage Pitch Stabilizer
- **Acoustic Dead-Band**: Discards sub-cent acoustic noise in quiet environments to prevent indicator flutter.
- **Adaptive Smoothing**: Dynamically weighs previous and current pitch estimates based on rate of change.
- **Transient Snap**: Bypasses smoothing and snaps instantly to the target frequency when string transitions or large pitch variations exceed 7.0 cents.
- **In-Tune Lock**: Locks the visual indicator directly to zero deviation when pitch settles inside the target dead-zone.

### 3. Feedback Suppression System
- Prevents infinite acoustic resonance when the completion chime sounds through device speakers.
- The audio capture pipeline drops incoming microphone buffers for the duration of the audio feedback envelope, preserving pitch detector stability.

### 4. Headstock Visualizer & Tuning Profiles
- Maps detected frequencies to equal-tempered targets across 8 standard and alternate tuning configurations (Standard, Drop D, Half-Step Down, D Standard, Drop C, DADGAD, Open D, Open G).
- Fully supports custom tuning profiles with user-defined target notes, octaves, and string assignments.

---

## Module Layout

```
lib/
├── audio/
│   ├── audio_capture_service.dart
│   ├── audio_feedback_player.dart
│   └── microphone_service.dart
├── pitch/
│   ├── note_model.dart
│   ├── pitch_tracker.dart
│   └── yin_pitch_detector.dart
├── settings/
│   ├── app_settings.dart
│   ├── app_settings_service.dart
│   └── settings_dialog.dart
├── tuner/
│   ├── horizontal_tuning_scale.dart
│   ├── pitch_stabilizer.dart
│   └── tuner_engine.dart
├── tuning/
│   ├── custom_tuning_storage.dart
│   ├── guitar_string.dart
│   ├── reference_frequency.dart
│   └── tuning_preset.dart
├── logo.png
└── main.dart
```

---

## Legal Warning & Proprietary Rights Notice

**Copyright © BAZUD3V. All Rights Reserved.**

This software, its design, source code, architecture, algorithms, and visual assets are the exclusive intellectual property of **BAZUD3V**.

- **No License Granted**: No individual, entity, or organization is granted permission to copy, reproduce, clone, modify, distribute, publish, sublicense, decompile, disassemble, or reverse engineer any part of this project.
- **Strict Prohibition**: Unauthorized usage, redistribution, commercialization, or public reproduction of this codebase, in whole or in part, is strictly prohibited.
- **Legal Action**: Any unauthorized copying, duplication, or misappropriation of this work discovered in public or private repositories, application stores, or commercial distributions will be met with immediate legal prosecution, injunctions, and claims for statutory damages to the fullest extent permitted by applicable domestic and international intellectual property laws.
