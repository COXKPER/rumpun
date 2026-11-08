# rumpun

A modern, user-friendly, and minimalist Fediverse (Mastodon-compatible) client for Linux and Android, built with Flutter. Local-first: cached timelines paint instantly, network reconciles in the background.

## Features

- **Timelines (Home)**: Following, Local, and Federated feeds with instant SQLite cache, animated pill filters, race-free tab switches, and smooth scroll-to-top.
- **Fediverse Posts (Tweets)**: Dedicated public stream covering Federated, Local, and Trending posts with infinite scrolling.
- **Explore & Search**: Trending hashtags, people, and statuses with unified search across accounts, tags, and posts.
- **Notifications**: Mentions, Likes, Reposts, and Follow Requests with live unread Badges on both mobile NavigationBar and desktop NavigationRail.
- **Personal Profile (You)**: View personal posts, replies, and media attachments with header and avatar previews, follow stats, and account switcher.
- **Modern Chrome**: Integrated Material 3 Top App Bar (`AppBar`) with server status indicator, action buttons, and `MenuAnchor` overflow menu.
- **Extended FAB**: Clean floating action button with text and icon for composing posts.
- **Rich Media & Carousel**: Multi-image attachments glide with Material 3 `CarouselView`; single images scale smoothly without cropping.
- **Media Preview**: Fullscreen viewer with pinch-to-zoom, alt-text reader, video and audio playback via `AdaptiveVideoControls`, looping gifv support, and one-tap image saving to the Downloads directory.
- **Push Notifications**: Live background notification polling with floating alert SnackBars, plus configurable FCM and UnifiedPush endpoints.
- **Flexible Settings**:
  - Theme mode (System Default, Light, Dark)
  - Multi-language support (English US/UK/SG, Bahasa Indonesia, Japanese) with live hot-swapping
  - Default post visibility (Public, Quiet public, Followers only, Mentioned only)
  - Always show sensitive media toggle
  - Compact timeline card density
  - Custom default instance configuration
  - One-tap timeline and disk media cache cleaner

## Security

OAuth tokens live only in the system credential store (Linux Secret Service / Android Keystore via `flutter_secure_storage`), never in SQLite, plain files, or logs. SQLite stores account metadata, draft content, and timeline cache only.

## Requirements

- Flutter SDK (Linux desktop and Android enabled)
- GTK 3 development libraries (`libgtk-3-dev`)
- `libmpv-dev` and ALSA headers (`libasound2-dev`) for media playback
- Android SDK (for Android builds)

## Build & run

```sh
make build     # release bundle in build/linux/x64/release/bundle
make run       # build and launch
make debug     # debug build
make apk       # Android debug APK
```

## Development

```sh
make test      # run the full test suite
make analyze   # static analysis
```

## First run

The app launches on `mastodon.social` public timelines in signed-out mode. Tap the account avatar in the top bar to sign in via your server browser authorization. You can change the default server at any time in Settings.

## Support & Feedback

For bug reports, questions, or feature requests, visit the project repository:

- Support and Issues: https://github.com/COXKPER/rumpun/issues
- Repository: https://github.com/COXKPER/rumpun

## License

[MIT](LICENSE)
