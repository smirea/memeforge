Fully test implementations with the built in ios simulator to make sure they work before comitting.

# Stack

- Language: Swift
- Package Manager: Swift Package Manager
- Minimum targets: iOS 17 and macOS 14
- Keep dependencies rare and intentional

# Product Notes

- When adding a feature, consider whether it belongs in both the app and keyboard surfaces. Usually it should, unless the request explicitly scopes it to one surface or it is clearly settings/configuration-only.
- Deployment is handled by Xcode Cloud: the TestFlight workflow can be started manually or by the daily `master` schedule, and its post-action assigns successful iOS archives to the internal `me` TestFlight group.
