import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Bumped whenever a string table finishes loading, so the app can rebuild.
final ValueNotifier<int> l10nVersion = ValueNotifier<int>(0);

const _tags = ['en-us', 'en-gb', 'en-sg', 'id-id', 'ja-jp'];
var _strings = const <String, String>{};

/// The English text is the key, so a missing entry falls back to English for
/// free — a partial translation is always usable.
String t(String key) => _strings[key] ?? key;

/// Maps legacy (`en`, `id_ID`), bcp47 (`en-GB`) and `system` onto a table name.
/// `system` resolves against the platform locale, so the tables follow the
/// device instead of pinning English.
String normalizeTag(String tag) {
  final raw = tag == 'system' || tag.isEmpty
      ? PlatformDispatcher.instance.locale.toLanguageTag()
      : tag;
  final lower = raw.replaceAll('_', '-').toLowerCase();
  for (final candidate in _tags) {
    if (lower == candidate) return candidate;
  }
  // Fall back on the language subtag alone: `id` -> id-id, `ja` -> ja-jp.
  final language = lower.split('-').first;
  for (final candidate in _tags) {
    if (candidate.split('-').first == language) return candidate;
  }
  return 'en-us';
}

/// Loads a table; never throws — a missing asset just leaves English in place.
/// Called on startup and again on every language change, which is what makes
/// the switch live: [l10nVersion] rebuilds MaterialApp with the new locale.
Future<void> loadL10n(String tag) async {
  final name = normalizeTag(tag);
  try {
    final xml = await rootBundle.loadString('assets/l10n/$name.xml');
    final strings = <String, String>{};
    for (final match in RegExp(r'<string name="([^"]+)">([\s\S]*?)</string>')
        .allMatches(xml)) {
      strings[match[1]!] = match[2]!;
    }
    _strings = strings;
  } catch (_) {
    _strings = const {};
  }
  l10nVersion.value++;
}
