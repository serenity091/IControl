// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "IControlCore", platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "IControlCore", targets: ["IControlCore"])],
    targets: [.target(name: "IControlCore", path: "IControl", exclude: ["IControlApp.swift", "TouchSurface.swift", "QRScanner.swift", "ControllerModel.swift", "MotionSource.swift", "Info.plist", "Assets.xcassets", "PrivacyInfo.xcprivacy", "PrivacyPolicy.txt"], sources: ["ControllerCore.swift"]),
              .testTarget(name: "IControlCoreTests", dependencies: ["IControlCore"], path: "Tests/IControlCoreTests")])
