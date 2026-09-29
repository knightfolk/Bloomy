# Bloomy branding

Bloomy is the macOS companion for the official Darkbloom provider and CLI. The
new app mark is an original Bloomy character, separate from the provider's
identity. The approved concept image is `assets/brand/bloomy-concept.png`;
the production app icon master is `assets/brand/bloomy-app-icon.png`.

- App icon master: `assets/brand/bloomy-app-icon.png`.
- Popup mark: `Sources/DarkbloomMonitor/Resources/bloomy-mark.svg`.
- Menu-bar mask: `Sources/DarkbloomMonitor/Resources/bloomy-menubar.svg`.
- Native icon: `Sources/DarkbloomMonitor/Resources/AppIcon.icns`.

The native icon is generated from the app icon master. To regenerate it, run
`swift tools/render_app_icon.swift assets/brand/bloomy-app-icon.png /new/output-directory`,
then run `iconutil -c icns` on the generated `AppIcon.iconset`. The renderer
refuses to overwrite an existing output directory. The concept image documents
the approved direction; package the finalized native icon.

Packaging produces `Bloomy.app` with Bloomy as its bundle and display name.
The bundle identifier remains `dev.darkbloom.monitor`. The internal executable
and resource bundle, preference keys, data locations, window restoration keys,
single-instance lock, and Sparkle update signature identity retain their prior
names and values for upgrade compatibility. The Swift package target and the
existing local checkout directory may also retain `DarkbloomMonitor` and
`DarkbloomCLIMenuBarMonitor`; neither is the product display name. The
GitHub repository URL is `https://github.com/knightfolk/Bloomy`.

Keep the earlier `dc-app-icon.svg`, `dc-mark.svg`, and `dc-menubar.svg` assets
as provenance for Darkbloom Control releases. Older release notes and appcast
items retain their historical names. Qwen, Google and OpenAI marks identify
models, not Bloomy, and retain their existing attribution. Historical official
provider logo files are excluded from the package.

When replacing an installed app, follow [the review-launch procedure](REVIEW_LAUNCH.md); identify its
running bundle before relaunching, and leave the provider running.
