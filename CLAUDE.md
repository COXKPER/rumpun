# CLAUDE.md

Guidance for agents working in this repo.

## What this is

`rumpun`: a user-friendly, minimalist Fediverse (Mastodon-compatible) client in Flutter,
targeting Linux and Android. Local-first: cached timelines paint instantly, network reconciles after.

## Toolchain

`flutter` is **not on PATH** in this environment. Use the absolute path:

```
/home/neoncorp/development/flutter/bin/flutter
```

Verify before reporting success: all three must pass:

```
/home/neoncorp/development/flutter/bin/flutter analyze lib/
/home/neoncorp/development/flutter/bin/flutter test
/home/neoncorp/development/flutter/bin/flutter build linux --release
```

`make build` / `make test` / `make analyze` wrap the same commands.

## Layout

| Path | Role |
| --- | --- |
| `lib/main.dart` | Shell, 5 nav destinations, post tile, compose, CarouselView, media preview, settings. |
| `lib/fediverse_api.dart` | Mastodon REST client (statuses, timelines, notifications, media, FCM push). |
| `lib/app_store.dart` | sqlite3 stores: settings, accounts, drafts, timeline cache, media index, weights. |
| `lib/l10n.dart` | XML string tables + `t(key)` + hot-swap notifier. |
| `lib/image_cache.dart` | `ImageProvider` with on-disk cache, shared media cache, and file download helper. |
| `lib/compress.dart` | zstd codec for cache rows, with plain-JSON fallback. |
| `assets/l10n/*.xml` | One table per locale (en-us, en-gb, en-sg, id-id, ja-jp). English text is the key. |

## Hard rules

- **OAuth tokens never touch SQLite, files, or logs.** They live only in
  `flutter_secure_storage` (key `fediverse:$accountId`). `AppStore` stores account
  metadata and settings only. Do not relax this for convenience.
- **Every string the user sees goes through `t('English text')`**, and the English
  text must exist in `assets/l10n/en-us.xml`. Missing keys silently fall back to the
  key itself. New keys must exist in all five tables.
- **Fixed navigation layout.** Five destinations: Home (0), Tweets (1), Explore (2),
  Notifications (3), and You/Profile (4). Features live inside pages.
- **Localization delegates are required.** Removing `GlobalMaterialLocalizations`
  makes `MaterialLocalizations.of` return null for `id_ID`/`ja_JP` and every
  `TextField` throws on build.

## Caching model

Three layers, all deliberate:

1. **Timeline rows**: `AppStore.cacheStatuses(timeline, statuses)` / `cachedStatuses`,
   payloads zstd-compressed via `encodeCache`/`decodeCache` (`lib/compress.dart`).
   Rows written before compression are plain JSON and still decode.
   Keys in use: `feed-$i` (home tabs), `tweets-fediverse-$feed` (public/trending stream),
   `tweets-$accountId-$tab` (profile posts/replies/media), `bookmarks-$accountId`,
   `notifications-$accountId-$segment`, `trending` (synthetic row holding 3 lists).
2. **Media files**: `CachedNetworkImage` writes decoded-source bytes under
   `<appSupport>/media-cache`; `cachedFile()` returns a `File` so media_kit plays
   video from disk instead of buffering it in memory.
3. **In-memory**: `imageCache.maximumSizeBytes = 256 MiB`, set once in `main()`.

Pattern for every screen: read cache -> paint -> fetch -> `setState` -> write cache.
Never block first paint on the network.

## Conventions

- Terse, comment only where the reason isn't visible in the code.
- Prefer stdlib/native over a package. A dependency needs to earn its build time.
  Compression uses `pure_zstd` (plain Dart) on purpose: the FFI `zstd` plugin
  git-clones libzstd from gitee.com at build time and fails in unit tests.
- Tests: `flutter_test` + `MockClient`. One assertion file per behaviour; no frameworks.
- Widget tests: use unique `find.text` targets rather than duplicate tooltips.

## Known deliberate gaps

- Media cache has no eviction (grows slowly). Upgrade path: LRU trim at ~200 MB.
- Images are cached without revalidation (`If-None-Match` not sent).
- Infinite scroll exists on Home and Tweets.
- `en_SG` and `ja_JP` have no Flutter Material table; built-in widget strings fall
  back to `en_GB`/`en`, app strings still come from their own XML.
