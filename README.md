# SomaSense - iOS

SomaSense is a private symptom tracker: tap where you feel something on a 3D body or paint the area, describe it, and see where and when symptoms happen over time. This is the native Swift version for iPhone. Everything stays on the device unless you choose to share it.

Website and privacy policy: [ncubeeight.github.io/SomaSense-iOS](https://ncubeeight.github.io/SomaSense-iOS/). The site is built by GitHub Pages from the `docs` folder.

## Building

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen), so it isn't stored here:

```bash
xcodegen generate
```

```bash
open SomaSense.xcodeproj
```

It needs Xcode 26 and targets iOS 26 on iPhone. The body is drawn with Metal, and its shader is compiled when the app starts, so the separate Metal toolchain isn't needed.

## Tests

`SomaSenseTests` checks that taps on the body land on the same point, label and area as the original SomaSense app, for the default body and for reshaped ones. The fixtures in `SomaSenseTests/Fixtures` come from `tools/make_fixtures.js`, run against a checkout of the original [SomaSense](https://github.com/ncubeeight/SomaSense) repository:

```bash
node tools/make_fixtures.js <path to SomaSense checkout>
```

## Credits

Authored by ncubeeight LLC for distribution on GitHub and the Apple App Store. Body models are provided by [MakeHuman](https://github.com/makehumancommunity/makehuman). The base mesh and the body shape offsets are derived from MakeHuman assets, which are released under CC0 1.0 Universal. MakeHuman's license is included in [licenses/MakeHuman-LICENSE.md](licenses/MakeHuman-LICENSE.md), with the full CC0 text for its assets in [licenses/MakeHuman-LICENSE.ASSETS.md](licenses/MakeHuman-LICENSE.ASSETS.md). Please keep this reference to the MakeHuman license in any derivative code that uses the body map.

## License

Licensed under the [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for third-party material, which keeps its own terms.
