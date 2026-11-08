
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'compress.dart';

/// Small Linux-first store. OAuth tokens deliberately never enter SQLite.
class AppStore {
  AppStore._(this.mainDb, this.cacheDb, this.indexDb, this.weightDb);

  final Database mainDb;
  final Database cacheDb;
  final Database indexDb;
  final Database weightDb;

  static Future<AppStore> open() async {
    final dir = await getApplicationSupportDirectory();
    return at((name) => '${dir.path}/$name');
  }

  /// Accepts a filename resolver so tests can use `:memory:` databases.
  static AppStore at(String Function(String name) filename) {
    final store = AppStore._(
      sqlite3.open(filename('main.db')),
      sqlite3.open(filename('cache.db')),
      sqlite3.open(filename('index.db')),
      sqlite3.open(filename('weight.db')),
    );
    store._initialize();
    return store;
  }

  void _initialize() {
    mainDb.execute('''CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
    mainDb.execute('''CREATE TABLE IF NOT EXISTS accounts (
      id TEXT PRIMARY KEY, instance TEXT NOT NULL, username TEXT,
      display_name TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)''');
    mainDb.execute('''CREATE TABLE IF NOT EXISTS drafts (
      key TEXT PRIMARY KEY, text TEXT NOT NULL DEFAULT '',
      spoiler TEXT NOT NULL DEFAULT '', visibility TEXT NOT NULL DEFAULT 'public',
      in_reply_to_id TEXT, in_reply_to_acct TEXT,
      media_count INTEGER NOT NULL DEFAULT 0,
      saved_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)''');
    cacheDb.execute('''CREATE TABLE IF NOT EXISTS statuses (
      id TEXT PRIMARY KEY, timeline TEXT NOT NULL, payload TEXT NOT NULL,
      cached_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)''');
    cacheDb.execute('CREATE INDEX IF NOT EXISTS statuses_timeline ON statuses(timeline, cached_at)');
    indexDb.execute('''CREATE TABLE IF NOT EXISTS media (
      url TEXT PRIMARY KEY, mime_type TEXT, local_path TEXT,
      alt_text TEXT, indexed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)''');
    weightDb.execute('''CREATE TABLE IF NOT EXISTS weights (
      key TEXT PRIMARY KEY, value INTEGER NOT NULL DEFAULT 0)''');
  }

  String get preferredInstance {
    final rows = mainDb.select("SELECT value FROM settings WHERE key='instance'");
    return rows.isEmpty ? 'mastodon.social' : rows.first['value'] as String;
  }

  void setPreferredInstance(String instance) {
    mainDb.execute('''INSERT INTO settings(key, value) VALUES ('instance', ?)
      ON CONFLICT(key) DO UPDATE SET value=excluded.value''', [instance]);
  }

  /// UI language tag; 'system' follows the platform locale.
  String get preferredLanguage {
    final rows = mainDb.select("SELECT value FROM settings WHERE key='language'");
    return rows.isEmpty ? 'system' : rows.first['value'] as String;
  }

  void setPreferredLanguage(String language) {
    mainDb.execute('''INSERT INTO settings(key, value) VALUES ('language', ?)
      ON CONFLICT(key) DO UPDATE SET value=excluded.value''', [language]);
  }

  /// Drops cached timelines; media file cache is wiped by the caller.
  void clearCaches() {
    cacheDb.execute('DELETE FROM statuses');
  }

  void saveAccount({required String id, required String instance,
      String? username, String? displayName}) {
    mainDb.execute('''INSERT INTO accounts(id, instance, username, display_name)
      VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET instance=excluded.instance,
      username=excluded.username, display_name=excluded.display_name''',
      [id, instance, username, displayName]);
  }

  List<Map<String, Object?>> accounts() => mainDb
      .select('SELECT * FROM accounts ORDER BY created_at DESC')
      .map((row) => row).toList();

  void deleteAccount(String id) {
    mainDb.execute('DELETE FROM accounts WHERE id=?', [id]);
  }

  /// One composer draft per key: `compose` for a new post, `reply:<statusId>`
  /// for a thread reply. Media descriptions are not persisted: uploads are
  /// per-session server state and re-attaching them needs a re-upload.
  void saveDraft(String key, {String text = '', String spoiler = '',
      String visibility = 'public', String? inReplyToId,
      String? inReplyToAcct, int mediaCount = 0}) {
    mainDb.execute('''INSERT INTO drafts(key, text, spoiler, visibility,
      in_reply_to_id, in_reply_to_acct, media_count)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(key) DO UPDATE SET text=excluded.text, spoiler=excluded.spoiler,
      visibility=excluded.visibility, in_reply_to_id=excluded.in_reply_to_id,
      in_reply_to_acct=excluded.in_reply_to_acct,
      media_count=excluded.media_count, saved_at=CURRENT_TIMESTAMP''',
      [key, text, spoiler, visibility, inReplyToId, inReplyToAcct, mediaCount]);
  }

  Map<String, dynamic>? draft(String key) {
    final rows = mainDb.select('SELECT text, spoiler, visibility, '
        'in_reply_to_id, in_reply_to_acct, media_count FROM drafts WHERE key=?', [key]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return {
      'text': row['text'] as String? ?? '',
      'spoiler': row['spoiler'] as String? ?? '',
      'visibility': row['visibility'] as String? ?? 'public',
      'in_reply_to_id': row['in_reply_to_id'] as String?,
      'in_reply_to_acct': row['in_reply_to_acct'] as String?,
      'media_count': row['media_count'] as int? ?? 0,
    };
  }

  void deleteDraft(String key) {
    mainDb.execute('DELETE FROM drafts WHERE key=?', [key]);
  }

  void cacheStatuses(String timeline, List<Map<String, dynamic>> statuses) {
    final batch = cacheDb.prepare('''INSERT INTO statuses(id, timeline, payload)
      VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET timeline=excluded.timeline,
      payload=excluded.payload, cached_at=CURRENT_TIMESTAMP''');
    try {
      cacheDb.execute('BEGIN');
      for (final status in statuses) {
        final id = status['id'];
        if (id is String && id.isNotEmpty) {
          batch.execute(['$timeline:$id', timeline, encodeCache(status)]);
        }
      }
      cacheDb.execute('COMMIT');
    } catch (_) {
      cacheDb.execute('ROLLBACK');
      rethrow;
    } finally {
      batch.close();
    }
  }

  List<Map<String, dynamic>> cachedStatuses(String timeline, {int limit = 40}) =>
      cacheDb.select('SELECT payload FROM statuses WHERE timeline=? '
          'ORDER BY cached_at DESC, rowid ASC LIMIT ?', [timeline, limit])
          .map((row) => decodeCache(row['payload'] as String))
          .whereType<Map<String, dynamic>>()
          .toList();

  void indexMedia({required String url, String? mimeType, String? localPath,
      String? altText}) {
    indexDb.execute('''INSERT INTO media(url, mime_type, local_path, alt_text)
      VALUES (?, ?, ?, ?) ON CONFLICT(url) DO UPDATE SET
      mime_type=excluded.mime_type, local_path=excluded.local_path,
      alt_text=excluded.alt_text, indexed_at=CURRENT_TIMESTAMP''',
      [url, mimeType, localPath, altText]);
  }

  void incrementWeight(String key, [int amount = 1]) {
    weightDb.execute('''INSERT INTO weights(key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value=value+excluded.value''', [key, amount]);
  }

  int weight(String key) {
    final rows = weightDb.select('SELECT value FROM weights WHERE key=?', [key]);
    return rows.isEmpty ? 0 : rows.first['value'] as int;
  }
  void close() {
    mainDb.close();
    cacheDb.close();
    indexDb.close();
    weightDb.close();
  }
}
