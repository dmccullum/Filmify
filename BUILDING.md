# Building Granular

Granular can be built and ad-hoc signed locally without an Apple Developer
account. The resulting app is intended for use on the Mac that built it.

## Requirements

- macOS 26 or later
- The full Xcode 26 application from Apple
- Xcode opened at least once so it can install its required components

Command Line Tools by themselves are not sufficient because Granular uses
Apple's Icon Composer when assembling the app bundle.

## Easiest method

1. Download or copy the complete Granular source folder.
2. Double-click **Build Granular.command**.
3. Wait for the build to finish.
4. Finder will reveal `dist/Granular.app`.
5. Drag the app into Applications.

The script checks the important prerequisites, builds a release binary for the
Mac's current architecture, assembles the app bundle, creates the complete
Finder icon, applies the sandbox entitlements, and ad-hoc signs the result.

## Terminal method

From the Granular source folder:

```sh
./Scripts/build-app.sh
open -R dist/Granular.app
```

Run the tests with:

```sh
swift test
```

The rendering library, GranularCore, also builds for iOS. To run its tests on an iPhone simulator:

```sh
xcodebuild test -scheme GranularCore -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Troubleshooting

If more than one Xcode installation is present, select the one to use:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

If Xcode reports that its components or license are incomplete:

```sh
sudo xcodebuild -runFirstLaunch
```

If a ZIP utility removed the executable permission from the friendly build
script:

```sh
chmod +x "Build Granular.command"
```

Then double-click it again.

## Preparing a source ZIP

To create a clean source archive for sharing or distribution:

```sh
./Scripts/package-source.sh
```

The script creates `dist/Granular-1.4-source.zip`, excluding Git history,
previous builds, and local Finder metadata. It also verifies the ZIP after
creating it.

## Distribution note

This local workflow uses an ad-hoc signature and does not create a notarized
public release. Distributing one prebuilt copy that opens normally on other
Macs requires an Apple Developer account, a Developer ID signature, and Apple
notarization.
