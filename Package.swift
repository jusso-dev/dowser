// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "findphone",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "FindPhoneKit", targets: ["FindPhoneKit"])
    ],
    targets: [
        .target(name: "FindPhoneKit", path: "Sources/FindPhoneKit"),
        .executableTarget(name: "findphone", dependencies: ["FindPhoneKit"],
                          path: "Sources/findphone"),
        .testTarget(name: "FindPhoneKitTests", dependencies: ["FindPhoneKit"],
                    path: "Tests/FindPhoneKitTests"),
    ]
)
