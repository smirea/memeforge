// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "ios-keyboard",
	platforms: [
		.iOS(.v17),
		.macOS(.v14),
	],
	products: [
		.executable(name: "ios-keyboard", targets: ["App"]),
	],
	targets: [
		.executableTarget(name: "App"),
	]
)