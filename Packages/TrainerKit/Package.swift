// swift-tools-version: 5.9
import PackageDescription

// NOOP Trainer (fork-only): pure plan + cue logic for guided workouts. No UIKit, AVFoundation or
// CoreBluetooth, so `swift test` runs on a Mac with no phone, strap or simulator. The app target owns
// the speech, timers and workout recording and only asks this package "what should be said, and when".
let package = Package(
    name: "TrainerKit",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "TrainerKit", targets: ["TrainerKit"]),
    ],
    targets: [
        .target(name: "TrainerKit"),
        .testTarget(name: "TrainerKitTests", dependencies: ["TrainerKit"]),
    ]
)
