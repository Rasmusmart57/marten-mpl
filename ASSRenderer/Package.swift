// swift-tools-version: 6.0

import PackageDescription

// ASS and SSA subtitles drawn by libass on the Mac, the Apple TV, iPhone and iPad (docs/ass-subtitles.md).
//
// libass 0.17.5 and what it needs (FreeType, HarfBuzz, FriBidi, libunibreak) come prebuilt from mpvkit's libass-build, the
// libass of MPVKit, pinned by checksum. Its archives are static. FriBidi is LGPL-2.1, and the Mac app is handed out directly,
// where the LGPL wants the person able to replace the library: so this package's product is `type: .dynamic`, one
// `ASSRenderer` library holding libass and its dependencies, which a person can build again from the same open sources and put
// in its place, as AetherEngine is built dynamic for the same reason (docs/licensing-and-release.md).
let package = Package(
    name: "ASSRenderer",
    platforms: [
        .iOS(.v18),
        .tvOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "ASSRenderer", type: .dynamic, targets: ["ASSRenderer"]),
    ],
    targets: [
        .target(
            name: "ASSRenderer",
            dependencies: ["Libass", "Libfreetype", "Libharfbuzz", "Libfribidi", "Libunibreak"],
            path: "Sources/ASSRenderer",
            linkerSettings: [
                // libass finds fonts through Core Text (`ASS_FONTPROVIDER_CORETEXT`); HarfBuzz and FreeType need the rest.
                .linkedFramework("CoreText"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedLibrary("z"),
                .linkedLibrary("iconv"),
            ]
        ),
        .testTarget(name: "ASSRendererTests", dependencies: ["ASSRenderer"], path: "Tests/ASSRendererTests"),
        .binaryTarget(
            name: "Libunibreak",
            url: "https://github.com/mpvkit/libass-build/releases/download/0.17.5/Libunibreak.xcframework.zip",
            checksum: "940d9833cf4477d0a260d9f2b4066125bc0ff7bbc111ac3c90e774765b77a559"
        ),
        .binaryTarget(
            name: "Libfreetype",
            url: "https://github.com/mpvkit/libass-build/releases/download/0.17.5/Libfreetype.xcframework.zip",
            checksum: "496ca62488530e14b1e4624d20ee2b237c0bd675cd70c19da578a5768302d02d"
        ),
        .binaryTarget(
            name: "Libfribidi",
            url: "https://github.com/mpvkit/libass-build/releases/download/0.17.5/Libfribidi.xcframework.zip",
            checksum: "bc15e097b892f2f90424e4a27ba287070cc2f98a74a4da10e6d2481d15cf5ff9"
        ),
        .binaryTarget(
            name: "Libharfbuzz",
            url: "https://github.com/mpvkit/libass-build/releases/download/0.17.5/Libharfbuzz.xcframework.zip",
            checksum: "aa8e0b9ca0387dac74e3e93c86e34d11982bb013b28022d0e6966a8427a35b2e"
        ),
        .binaryTarget(
            name: "Libass",
            url: "https://github.com/mpvkit/libass-build/releases/download/0.17.5/Libass.xcframework.zip",
            checksum: "3f4c576d2818ceb4544aa2a20e1f55846511c5e706fd19adc3ea9fd842270498"
        ),
    ],
    // Swift 5 language rules, as the apps' own code (macApp/Package.swift says why).
    swiftLanguageModes: [.v5]
)
