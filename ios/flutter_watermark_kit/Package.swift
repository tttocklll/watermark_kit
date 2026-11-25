// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "flutter_watermark_kit",
    platforms: [
        .iOS("15.0"),
    ],
    products: [
        .library(name: "flutter-watermark-kit", targets: ["flutter_watermark_kit"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "flutter_watermark_kit",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        ),
    ]
)