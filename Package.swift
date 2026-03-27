// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WWStreamPlayer",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(name: "WWStreamPlayer", targets: ["WWStreamPlayer"]),
    ],
    targets: [
        .target(
            name: "WWStreamPlayer",
            dependencies: ["FFmpegWrapper"]
        ),
        .target(
            name: "FFmpegWrapper",
            dependencies: ["FFMpeg_AVCodec", "FFMpeg_AVDevice", "FFMpeg_AVFilter", "FFMpeg_AVFormat", "FFMpeg_AVUtil", "FFMpeg_SwreSample", "FFMpeg_SwScale"],
            publicHeadersPath: "."
        ),
        .binaryTarget(
            name: "FFMpeg_AVCodec",
            url: "https://github.com/William-Weng/FFMpeg_XCFramework/releases/download/n7.1/libavcodec.xcframework.zip",
            checksum: "365232ae6c2342a0ce49a8c124694751a11f8c56d76442e38666239fbbc33b20"
        ),
        .binaryTarget(
            name: "FFMpeg_AVDevice",
            url: "https://github.com/William-Weng/FFMpeg_XCFramework/releases/download/n7.1/libavdevice.xcframework.zip",
            checksum: "9dbb27336fc5e53bc6d9a6bd8bd261171860ed407e364455f0d2c1e7e133649d"
        ),
        .binaryTarget(
            name: "FFMpeg_AVFilter",
            url: "https://github.com/William-Weng/FFMpeg_XCFramework/releases/download/n7.1/libavfilter.xcframework.zip",
            checksum: "60ac56073eaf44c7d0c57a9d1ceb3cb5b72f6b8d08a7fd8b37702b560bdd96d1"
        ),
        .binaryTarget(
            name: "FFMpeg_AVFormat",
            url: "https://github.com/William-Weng/FFMpeg_XCFramework/releases/download/n7.1/libavformat.xcframework.zip",
            checksum: "c0ef46a86757a0c925fa94b6d646756895e11793e1fec2f0dedbf3d86dc9c9de"
        ),
        .binaryTarget(
            name: "FFMpeg_AVUtil",
            url: "https://github.com/William-Weng/FFMpeg_XCFramework/releases/download/n7.1/libavutil.xcframework.zip",
            checksum: "6157c78d578810aa8c9cecdf5acd43eb188d3bfb13c29373a3c90249ab107c51"
        ),
        .binaryTarget(
            name: "FFMpeg_SwreSample",
            url: "https://github.com/William-Weng/FFMpeg_XCFramework/releases/download/n7.1/libswresample.xcframework.zip",
            checksum: "24cd2a5370af9b38bb59dc6f78f793f3d6643285ca8b79a5a3842c177707409b"
        ),
        .binaryTarget(
            name: "FFMpeg_SwScale",
            url: "https://github.com/William-Weng/FFMpeg_XCFramework/releases/download/n7.1/libswscale.xcframework.zip",
            checksum: "bea9270a7b9a60b29538cef371e2a00ee57825aa1d1c25fb52b7e6b6e37a8b20"
        )
    ]
)
