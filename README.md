# rumpun

A minimalist Fediverse (Mastodon-compatible) client for Linux and Android,
built with Flutter.

## Features

- **Timelines** — Following (authenticated home), Local, and Federated feeds with
  instant cached rendering
- **Real profiles** — banner, avatar, bio, and post history via account lookup
- **Media** — inline galleries with a fullscreen preview: pinch-zoom, alt text,
  swipe for multiple attachments, in-preview video/audio playback (libmpv)
- **Posting** — compose with content warnings and up to 4 image/video/audio
  attachments
- **Interactions** — reply, like, boost, share (copy link / open in browser),
  notifications
- **Explore** — trending tags, people, and posts; account search
- **Caching** — timelines cached in SQLite and every image cached on disk, so
  restarts and scrolls don't re-fetch from servers
- **Settings** — default instance, language, clear cache, logout

## Security

OAuth tokens live only in the system credential store (Linux keyring / Android
Keystore via `flutter_secure_storage`) — never in SQLite, files, or logs.
SQLite stores account metadata and settings only.

## Requirements

- Flutter SDK (Linux desktop + Android enabled)
- GTK 3 development libraries
- `libmpv-dev` and ALSA headers (`libasound2-dev`) for Linux media playback
- Android SDK (for the Android build)

## Build & run

```sh
make build     # release bundle in build/linux/x64/release/bundle
make run       # build + launch
make debug     # debug build
make apk       # Android debug APK
```

## Development

```sh
make test      # run the test suite
make analyze   # static analysis
```

## First run

The app starts on `mastodon.social` public timelines, signed out. To post,
like, boost, or see notifications: use the account icon (top right) to log in
via your instance's browser authorization. The default instance is changeable
in Settings.

## License

[MIT](LICENSE)
