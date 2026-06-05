// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "memeforge",
	platforms: [
		.iOS(.v17),
		.macOS(.v14),
	],
	products: [
		.executable(name: "memeforge", targets: ["App"]),
	],
	targets: [
		.executableTarget(name: "App"),
	]
)
