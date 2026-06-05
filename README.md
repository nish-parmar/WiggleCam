# Wigglegram

An iOS app that creates real wigglegrams from actual camera viewpoints.

> **No AI image generation. No depth estimation. No face alteration. No beautification. No synthetic parallax.**
> Just two real photographs from two real viewpoints, aligned and animated.

## How It Works

1. The app detects whether your iPhone supports simultaneous rear-camera capture (`AVCaptureMultiCamSession`).
2. If supported, it shoots both rear lenses **at the same time** in the order:
   1. Wide + Ultra Wide
   2. Wide + Telephoto
3. If not supported, it falls back to **two rapid sequential photographs** from the wide lens.
4. The two frames are:
   - **Aligned** using classical (non-ML) image registration via the Vision framework
   - **Cropped** to their shared overlap to remove any black borders
   - **Assembled** into a ping-pong sequence (A, B, A, B) at 8 FPS by default
5. Export as **GIF**, **MP4**, or **JPG source frames** — saved directly to your Photos library.

## Requirements

- **iOS 17+** (uses `NavigationStack`, `@AppStorage`, modern SwiftUI APIs)
- **Xcode 15+**
- A physical iPhone for capture (the camera does not work in the simulator)
- A device with at least one rear camera; dual-cam mode requires an iPhone XS / XR or newer

## Project Structure

```
Wigglegram/
├── WigglegramApp.swift         # @main entry, environment objects
├── AppRouter.swift             # NavigationStack coordinator
├── Info.plist                  # Permissions: Camera, Photos add-only
├── Models/
│   ├── AppSettings.swift       # @AppStorage-backed preferences
│   ├── CaptureMode.swift       # dual / sequential mode + LensType
│   ├── CapturedPair.swift      # raw A + B from camera
│   ├── ExportFormat.swift      # gif / mp4 / frames
│   └── Wigglegram.swift        # processed pair + ping-pong sequence
├── Services/
│   ├── CameraService.swift             # AVCaptureMultiCamSession + fallback
│   ├── ImageAlignmentService.swift     # Vision-based registration (no AI)
│   ├── CropService.swift               # shared-overlap cropping
│   ├── WigglegramBuilder.swift         # align → crop → build pipeline
│   └── ExportService.swift             # GIF (ImageIO) / MP4 (AVAssetWriter) / JPG → Photos
├── ViewModels/
│   ├── CaptureViewModel.swift
│   ├── ProcessingViewModel.swift
│   └── PreviewViewModel.swift
├── Views/
│   ├── HomeView.swift
│   ├── CaptureView.swift
│   ├── CameraPreviewView.swift         # UIViewRepresentable wrapping AVCaptureVideoPreviewLayer
│   ├── ProcessingView.swift
│   ├── PreviewView.swift
│   └── SettingsView.swift
├── Utilities/
│   ├── UIImage+Extensions.swift
│   ├── FilmLook.swift                  # optional Core Image grading pass
│   └── HapticManager.swift
└── Resources/
    └── Assets.xcassets/                # AppIcon + AccentColor placeholders
```

## Setup

You have two options for opening the project in Xcode.

### Option A — XcodeGen (recommended)

[XcodeGen](https://github.com/yonaskolb/XcodeGen) creates the `.xcodeproj` from `project.yml`.

```bash
brew install xcodegen
cd wigglecam
xcodegen generate
open Wigglegram.xcodeproj
```

Regenerate the project any time you add/move files:

```bash
xcodegen generate
```

### Option B — Create the project manually in Xcode

1. Open **Xcode → File → New → Project → iOS → App**
2. Product Name: `Wigglegram`, Interface: **SwiftUI**, Language: **Swift**
3. Save it **inside this repository**, *overwriting* the generated `Wigglegram` folder is fine — but the easier route is:
   - Save the new project to a temp folder
   - Delete the new project's `Wigglegram/` source folder
   - Drag this repo's `Wigglegram/` folder into the Xcode project navigator (choose *Copy items if needed: OFF*, *Create groups*)
4. Point the target's **Info.plist** at `Wigglegram/Info.plist`
5. Set the deployment target to **iOS 17.0**

### Run

1. Plug in a physical iPhone.
2. Select your device in Xcode.
3. **⌘R** to build and run.
4. Grant camera + Photos (add-only) permissions when prompted.

## Permissions

The app declares only what it actually uses:

| Key | Purpose |
| --- | --- |
| `NSCameraUsageDescription` | Capture the two rear-lens photographs |
| `NSPhotoLibraryAddUsageDescription` | Save exported GIF / MP4 / frames |
| `NSPhotoLibraryUsageDescription` | Same — for older OS prompts |

## Design Choices

- **MVVM** with `@MainActor`-isolated view models and `ObservableObject`-based services.
- **`AVCaptureMultiCamSession`** for true simultaneous capture; falls back gracefully on devices that don't support it.
- **`VNTranslationalImageRegistrationRequest`** for alignment — classical feature-based registration, not ML.
- **`ImageAligning` protocol** lets you swap in an OpenCV (homography / ECC) backend later without touching the pipeline.
- **ImageIO** for GIF, **AVAssetWriter** for MP4 — both natively bundled, no third-party dependencies.

## Future Features (intentionally out of scope)

- Community feed
- User accounts
- AI editing
- Filters marketplace
- Paid features
- Android support

## License

TBD.
