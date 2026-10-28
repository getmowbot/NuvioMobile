// swift-tools-version: 6.1

import PackageDescription

// NuvioAetherKit wraps AetherEngine for Nuvio's iOS app.
//
// It MUST stay a dynamic library. MPVKit links a static FFmpeg into the app executable, and
// AetherEngine calls `avcodec_*` & co. as plain external symbols: linked statically beside
// MPVKit, the engine would bind to MPV's FFmpeg instead of its own. Linked into this framework,
// the engine's references resolve against the AetherLib* frameworks when the framework links,
// and the two-level namespace keeps them apart at runtime (AetherEngine docs/api.md,
// "Holding a second player beside the engine"). aether/scripts/verify-ipa.sh checks it.
//
// Optional AetherEngine components (all off by default upstream, and possibly subject to
// third-party patent licensing; the integrator is responsible for its own licensing):
//   TrueHDObjectAudio     TrueHD Atmos objects/heights rendered into a speaker bed
//   DTSXObjectAudio       DTS:X heights rendered into a speaker bed
//   DualLayerDolbyVision  Dolby Vision profile 7 FEL composed on the GPU
// Remove a name from `traits` to build without it; the matching setting then does nothing.

let package = Package(
    name: "NuvioAetherKit",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "NuvioAetherKit",
            type: .dynamic,
            targets: ["NuvioAetherKit"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/superuser404notfound/AetherEngine",
            from: "7.50.0",
            traits: ["TrueHDObjectAudio", "DTSXObjectAudio", "DualLayerDolbyVision"]
        ),
    ],
    targets: [
        .target(
            name: "NuvioAetherKit",
            dependencies: [
                .product(name: "AetherEngine", package: "AetherEngine"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
