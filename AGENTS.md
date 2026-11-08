# AGENTS.md

Operating instructions for automated agents in this repository.

## Before you start

1. Read `CLAUDE.md`: it holds the toolchain path, the layout, and the hard rules.
2. `git status`: the tree is expected to be clean; if it isn't, find out why before editing.
3. Confirm the build works before changing anything:
   `/home/neoncorp/development/flutter/bin/flutter analyze lib/`

## The loop

1. Locate the code with `grep`/`Read`. `lib/main.dart` is large; read the region you
   need, not the file.
2. Make the smallest edit that satisfies the request. No scaffolding, no
   abstractions with a single implementation, no config for a constant.
3. Verify, in this order, and do not skip steps:
   - `flutter analyze lib/` -> must say **No issues found!**
   - `flutter test` -> must say **All tests passed!**
   - `flutter build linux --release` when the change touches UI, assets, or deps.
4. Report real output. Never claim a green run you did not see.

## Non-negotiables

- **Do not put OAuth tokens in SQLite, files, or logs.** `flutter_secure_storage` only.
- **Navigation structure.** Five destinations fixed: Home, Tweets (public Fediverse feeds), Explore, Notifications, and You (personal profile / account).
- **Do not add a dependency** without checking whether the stdlib or an installed
  package already does it. If you do add one, the Linux release build must still pass.
- **Do not delete or rewrite `assets/l10n/en-us.xml` keys** — the English text is the
  lookup key. Removing a key silently breaks its translation everywhere. New visible
  strings must be added to all 5 XML files (`en-us`, `en-gb`, `en-sg`, `id-id`, `ja-jp`).

## Verification traps

- `pumpAndSettle` hangs forever if startup awaits an asset read. Keep `loadL10n`
  fire-and-forget.
- A tooltip whose text duplicates a visible label makes `find.byTooltip` ambiguous.
  Use a unique `find.text` target in widget tests.
- Flutter resolves `id_ID`/`ja_JP` only with `GlobalMaterialLocalizations.delegates`
  in `MaterialApp`. Without it, `TextField` throws a null check on build.
- `flutter build linux` can take longer than 10 minutes on a cold CMake cache.
  Run it in the background and read the output file rather than assuming failure.
- Never add the FFI `zstd` package: it fetches libzstd from gitee.com during the
  build and throws `ZstdApi is not implemented` under `flutter test`. Use `pure_zstd`.
- `NavigationRail` and `NavigationBar` indices range from 0 to 4 (Home: 0, Tweets: 1,
  Explore: 2, Notifications: 3, You/Profile: 4). Targeting index 5 causes `RangeError`.

## Commits

Only commit when asked. Message shape: a one-line summary in the imperative, a blank
line, then grouped bullets (`UI:`, `Localization:`, `Fediverse:`, `Performance:`).
End with `Co-Authored-By: Claude Code <noreply@anthropic.com>`.
