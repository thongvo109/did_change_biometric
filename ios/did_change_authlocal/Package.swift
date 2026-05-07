// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "did_change_authlocal",
    platforms: [
        .iOS(.v12)
    ],
    products: [
        .library(name: "did-change-authlocal", targets: ["did_change_authlocal"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "did_change_authlocal",
            dependencies: [],
            resources: [
                // If your plugin requires a privacy manifest, for example if it
                // collects user data, update the PrivacyInfo.xcprivacy file to
                // describe your plugin's privacy impact, and then uncomment this
                // line. For more information, see:
                // https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
                // .process("PrivacyInfo.xcprivacy"),
            ]
        )
    ]
)
