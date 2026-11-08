import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_store.dart';
import 'fediverse_api.dart';
import 'l10n.dart';
import 'image_cache.dart';
import 'oauth_callback.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // One-time cap bump: the default 100 MiB evicts while scrolling feeds.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 256 << 20;
  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    // Native media backend unavailable; video playback won't work but the
    // rest of the app must still start.
    debugPrint('MediaKit init failed: $e');
  }
  runApp(const RumpunApp());
}

const _green = Color(0xFF236B55);
const _supportUrl = 'https://github.com/COXKPER/rumpun/issues';
FediverseApi? _activeApi;
AppStore? _appStore;
Map<String, dynamic>? _currentAccount;
String? _currentAccountId;
String _instance = 'mastodon.social';
List<Map<String, dynamic>> _serverCustomEmojis = [];
final ValueNotifier<int> _appConfigVersion = ValueNotifier<int>(0);
final ValueNotifier<int> _unreadNotifications = ValueNotifier<int>(0);

Future<void> _loadServerEmojis() async {
  final api = _activeApi;
  if (api == null) return;
  try {
    final emojis = await api.customEmojis();
    _serverCustomEmojis = emojis;
  } catch (_) {}
}

class RumpunApp extends StatefulWidget {
  const RumpunApp({super.key, this.api, this.store});
  final FediverseApi? api;
  final AppStore? store;
  @override
  State<RumpunApp> createState() => _RumpunAppState();
}

class _RumpunAppState extends State<RumpunApp> {
  bool _ready = false;
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final store = widget.store ?? await AppStore.open();
    _appStore = store;
    _instance = store.preferredInstance;
    // Fire-and-forget: the table lands a frame later via l10nVersion, and
    // startup never blocks on an asset read (which also spins the spinner
    // forever in widget tests when the bundle read is slow).
    loadL10n(store.preferredLanguage);
    if (widget.api != null) {
      _activeApi = widget.api;
      if (mounted) {
        setState(() => _ready = true);
        _loadServerEmojis();
      }
      return;
    }
    final accounts = store.accounts();
    if (accounts.isNotEmpty) {
      final saved = accounts.first;
      final api = FediverseApi(saved['instance'] as String);
      try {
        await api.restoreToken(saved['id'] as String);
        final account = await api.currentUser();
        _currentAccountId = saved['id'] as String;
        _currentAccount = account;
        _activeApi = api;
      } catch (_) {
        api.close();
        _activeApi = FediverseApi(_instance);
      }
    } else {
      _activeApi = FediverseApi(_instance);
    }
    if (mounted) {
      setState(() => _ready = true);
      _loadServerEmojis();
    }
  }

  /// Resolves the persisted language preference into a locale override.
  Locale? get _localeOverride {
    final tag = _appStore?.preferredLanguage ?? 'system';
    if (tag == 'system' || tag.isEmpty) return null;
    // Stored as `en-gb` / `id-id`; Flutter wants language and country apart.
    final parts = normalizeTag(tag).split('-');
    return parts.length > 1
        ? Locale(parts[0], parts[1].toUpperCase())
        : Locale(parts[0]);
  }

  ThemeMode get _themeMode =>
      switch (_appStore?.setting('theme_mode', 'system')) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  @override
  Widget build(BuildContext context) => DynamicColorBuilder(
        builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
          final lightScheme = lightDynamic != null
              ? lightDynamic.harmonized()
              : ColorScheme.fromSeed(
                  seedColor: _green,
                  surface: const Color(0xFFF7F8F6),
                );
          final darkScheme = darkDynamic != null
              ? darkDynamic.harmonized()
              : ColorScheme.fromSeed(
                  seedColor: const Color(0xFF83C9AE),
                  brightness: Brightness.dark,
                  surface: const Color(0xFF161918),
                );
          return ListenableBuilder(
            listenable: Listenable.merge([l10nVersion, _appConfigVersion]),
            builder: (context, _) => MaterialApp(
              title: 'Fediverse',
              debugShowCheckedModeBanner: false,
              themeMode: _themeMode,
              scrollBehavior: const MaterialScrollBehavior().copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                },
              ),
              theme: ThemeData(
                colorScheme: lightScheme,
                useMaterial3: true,
                fontFamily: '.SF Pro Text',
                scaffoldBackgroundColor: lightScheme.surface,
                snackBarTheme: SnackBarThemeData(
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  showCloseIcon: true,
                ),
                cardTheme: CardThemeData(
                  color: lightScheme.surfaceContainerLow,
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                navigationBarTheme: const NavigationBarThemeData(
                  elevation: 0,
                  indicatorShape: StadiumBorder(),
                ),
                bottomSheetTheme: const BottomSheetThemeData(
                  showDragHandle: true,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                ),
                dialogTheme: DialogThemeData(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
              ),
              darkTheme: ThemeData(
                colorScheme: darkScheme,
                useMaterial3: true,
                fontFamily: '.SF Pro Text',
                scaffoldBackgroundColor: darkScheme.surface,
                snackBarTheme: SnackBarThemeData(
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  showCloseIcon: true,
                ),
                cardTheme: CardThemeData(
                  color: darkScheme.surfaceContainerLow,
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                navigationBarTheme: const NavigationBarThemeData(
                  elevation: 0,
                  indicatorShape: StadiumBorder(),
                ),
                bottomSheetTheme: const BottomSheetThemeData(
                  showDragHandle: true,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                ),
                dialogTheme: DialogThemeData(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
              ),
              locale: _localeOverride,
              // DefaultMaterialLocalizations is English-only; without these an
              // `id_ID` locale leaves MaterialLocalizations null and every
              // TextField crashes on MaterialLocalizations.of.
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              supportedLocales: const [
                Locale('en', 'US'), Locale('en', 'GB'), Locale('en', 'SG'),
                Locale('id', 'ID'), Locale('ja', 'JP'),
              ],
              home: _ready ? const RumpunShell() : const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
            ),
          );
        },
      );
}

class Post {
  const Post(this.status, this.instance);
  final Map<String, dynamic> status;
  final String instance;

  Map<String, dynamic> get data =>
      status['reblog'] as Map<String, dynamic>? ?? status;
  Map<String, dynamic> get account =>
      data['account'] as Map<String, dynamic>? ?? {};
  String get id => data['id'] as String? ?? '';
  String get acct => account['acct'] as String? ?? 'unknown';
  String get handle => acct.contains('@') ? '@$acct' : '@$acct@$instance';
  String get name => (account['display_name'] as String?)?.isNotEmpty == true
      ? account['display_name'] as String
      : account['username'] as String? ?? acct;
  String get content => data['content'] as String? ?? '';
  String? get repostedBy {
    final reblog = status['reblog'];
    if (reblog is! Map<String, dynamic>) return null;
    final by = status['account'] as Map<String, dynamic>? ?? {};
    final display = by['display_name'] as String?;
    return display?.isNotEmpty == true ? display : by['username'] as String?;
  }
}

class RumpunShell extends StatefulWidget {
  const RumpunShell({super.key});
  @override
  State<RumpunShell> createState() => _RumpunShellState();
}

class _RumpunShellState extends State<RumpunShell> {
  final _homeKey = GlobalKey<_HomeScreenState>();
  final _tweetsKey = GlobalKey<_TweetsScreenState>();
  final _activityKey = GlobalKey<_ActivityScreenState>();
  int _page = 0;
  Timer? _pushTimer;
  String? _lastNotificationId;

  @override
  void initState() {
    super.initState();
    _pushTimer = Timer.periodic(
        const Duration(seconds: 45), (_) => _pollPushNotifications());
  }

  @override
  void dispose() {
    _pushTimer?.cancel();
    super.dispose();
  }

  Future<void> _pollPushNotifications() async {
    if (_currentAccount == null) return;
    if (!(_appStore?.boolSetting('push_enabled', fallback: true) ?? true)) return;
    try {
      final items = await _activeApi!.notifications(limit: 5);
      if (!mounted || items.isEmpty) return;
      final newestId = items.first['id'] as String?;
      if (newestId != null && newestId != _lastNotificationId) {
        final isFirstSeen = _lastNotificationId == null;
        _lastNotificationId = newestId;
        if (_page != 3) {
          _unreadNotifications.value = items.length;
        }
        if (!isFirstSeen && mounted) {
          final acct = items.first['account'] as Map<String, dynamic>? ?? {};
          final who = (acct['display_name'] as String?)?.isNotEmpty == true
              ? acct['display_name'] as String
              : acct['username'] as String? ?? 'Someone';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$who · ${t('Notifications')}'),
              action: SnackBarAction(
                label: t('Notifications'),
                onPressed: () => setState(() {
                  _page = 3;
                  _unreadNotifications.value = 0;
                }),
              ),
            ),
          );
        }
      }
    } catch (_) {}
  }

  List<String> get _titles => [
        t('Home'),
        t('Tweets'),
        t('Explore'),
        t('Notifications'),
        _profileAccount == null ? t('You') : t('Profile'),
      ];
  Map<String, dynamic>? _profileAccount;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final chromeColor =
        (isDark ? const Color(0xFF202422) : Colors.white).withValues(alpha: 0.96);
    final borderColor =
        theme.colorScheme.onSurface.withValues(alpha: isDark ? 0.12 : 0.10);
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final youLabel = _profileAccount == null ? t('You') : t('Profile');
    final pages = [
      HomeScreen(key: _homeKey, onOpenProfile: _openProfile, onCompose: _compose),
      TweetsScreen(key: _tweetsKey, onOpenProfile: _openProfile),
      ExploreScreen(onOpenProfile: _openProfile),
      ActivityScreen(key: _activityKey),
      _profileAccount == null
          ? ProfileScreen(account: _currentAccount, accountId: _currentAccountId,
              onOpenProfile: _openProfile)
          : ProfileScreen(account: _profileAccount,
              onOpenProfile: _openProfile),
    ];
    void selectTab(int i) {
      if (i == 0 && _page == 0) _homeKey.currentState?._scrollToTop();
      if (i == 1 && _page == 1) _tweetsKey.currentState?._scrollToTop();
      if (i == 3) _unreadNotifications.value = 0;
      setState(() {
        _page = i;
        _profileAccount = null;
      });
    }

    return ValueListenableBuilder<int>(
      valueListenable: _unreadNotifications,
      builder: (context, unreadCount, _) => Scaffold(
        appBar: _TopBar(
          title: _titles[_page],
          onAccount: _openAccount,
          onSettings: _settings,
          onBookmarks: _currentAccount == null
              ? null
              : () => _homeKey.currentState?._openBookmarks(),
          onRefresh: () {
            if (_page == 0) _homeKey.currentState?._refresh();
            if (_page == 1) _tweetsKey.currentState?.refresh();
            if (_page == 3) _activityKey.currentState?.refresh();
          },
          action: switch (_page) {
            0 => IconButton(
                tooltip: 'Bookmarks',
                onPressed: _currentAccount == null
                    ? null
                    : () => _homeKey.currentState?._openBookmarks(),
                icon: const Icon(Icons.bookmark_border)),
            1 => IconButton(
                tooltip: 'Refresh',
                onPressed: () => _tweetsKey.currentState?.refresh(),
                icon: const Icon(Icons.refresh)),
            3 => IconButton(
                tooltip: 'Refresh',
                onPressed: () => _activityKey.currentState?.refresh(),
                icon: const Icon(Icons.refresh)),
            _ => null,
          },
        ),
        floatingActionButton: _currentAccount == null
            ? null
            : FloatingActionButton.extended(
                tooltip: 'New post',
                onPressed: _compose,
                icon: const Icon(Icons.edit_outlined),
                label: Text(t('Post'))),
        body: SafeArea(
          child: Row(children: [
            if (wide)
              Container(
                decoration: BoxDecoration(
                  color: chromeColor,
                  border: Border(right: BorderSide(color: borderColor)),
                ),
                child: NavigationRail(
                  backgroundColor: Colors.transparent,
                  minWidth: 84,
                  labelType: NavigationRailLabelType.all,
                  indicatorColor: theme.colorScheme.primaryContainer,
                  indicatorShape: const StadiumBorder(),
                  selectedIndex: _page,
                  onDestinationSelected: selectTab,
                  destinations: [
                    NavigationRailDestination(
                        icon: const Badge(
                            isLabelVisible: false,
                            child: Icon(Icons.home_outlined)),
                        selectedIcon: const Badge(
                            isLabelVisible: false,
                            child: Icon(Icons.home_rounded)),
                        label: Text(t('Home'))),
                    NavigationRailDestination(
                        icon: const Badge(
                            isLabelVisible: false,
                            child: Icon(Icons.forum_outlined)),
                        selectedIcon: const Badge(
                            isLabelVisible: false,
                            child: Icon(Icons.forum_rounded)),
                        label: Text(t('Tweets'))),
                    NavigationRailDestination(
                        icon: const Badge(
                            isLabelVisible: false,
                            child: Icon(Icons.explore_outlined)),
                        selectedIcon: const Badge(
                            isLabelVisible: false,
                            child: Icon(Icons.explore_rounded)),
                        label: Text(t('Explore'))),
                    NavigationRailDestination(
                        icon: Badge(
                            isLabelVisible: unreadCount > 0,
                            label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
                            child: const Icon(Icons.notifications_none_rounded)),
                        selectedIcon: Badge(
                            isLabelVisible: unreadCount > 0,
                            label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
                            child: const Icon(Icons.notifications_rounded)),
                        label: Text(t('Notifications'))),
                    NavigationRailDestination(
                        icon: Badge(
                            isLabelVisible: _currentAccount != null,
                            smallSize: 7,
                            backgroundColor: _green,
                            child: const Icon(Icons.person_outline_rounded)),
                        selectedIcon: Badge(
                            isLabelVisible: _currentAccount != null,
                            smallSize: 7,
                            backgroundColor: _green,
                            child: const Icon(Icons.person_rounded)),
                        label: Text(youLabel)),
                  ],
                ),
              ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 780),
                  child: pages[_page],
                ),
              ),
            ),
          ]),
        ),
        bottomNavigationBar: wide
            ? null
            : Container(
                decoration: BoxDecoration(
                  color: chromeColor,
                  border: Border(top: BorderSide(color: borderColor)),
                ),
                child: NavigationBar(
                  height: 66,
                  backgroundColor: Colors.transparent,
                  indicatorColor: theme.colorScheme.primaryContainer,
                  selectedIndex: _page,
                  onDestinationSelected: selectTab,
                  destinations: [
                    NavigationDestination(
                        icon: const Badge(
                            isLabelVisible: false,
                            child: Icon(Icons.home_outlined)),
                        selectedIcon: const Badge(
                            isLabelVisible: false,
                            child: Icon(Icons.home_rounded)),
                        label: t('Home')),
                    NavigationDestination(
                        icon: const Badge(
                            isLabelVisible: false,
                            child: Icon(Icons.forum_outlined)),
                        selectedIcon: const Badge(
                            isLabelVisible: false,
                            child: Icon(Icons.forum_rounded)),
                        label: t('Tweets')),
                    NavigationDestination(
                        icon: const Badge(
                            isLabelVisible: false,
                            child: Icon(Icons.explore_outlined)),
                        selectedIcon: const Badge(
                            isLabelVisible: false,
                            child: Icon(Icons.explore_rounded)),
                        label: t('Explore')),
                    NavigationDestination(
                        icon: Badge(
                            isLabelVisible: unreadCount > 0,
                            label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
                            child: const Icon(Icons.notifications_none_rounded)),
                        selectedIcon: Badge(
                            isLabelVisible: unreadCount > 0,
                            label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
                            child: const Icon(Icons.notifications_rounded)),
                        label: t('Notifications')),
                    NavigationDestination(
                        icon: Badge(
                            isLabelVisible: _currentAccount != null,
                            smallSize: 7,
                            backgroundColor: _green,
                            child: const Icon(Icons.person_outline_rounded)),
                        selectedIcon: Badge(
                            isLabelVisible: _currentAccount != null,
                            smallSize: 7,
                            backgroundColor: _green,
                            child: const Icon(Icons.person_rounded)),
                        label: youLabel),
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _compose() {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    if (wide) {
      return showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: SingleChildScrollView(
              child: _ComposeSheet(
                onPosted: () async {
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  setState(() => _page = 0);
                  _message(t('Post published'));
                  await _homeKey.currentState?._refresh(silent: true);
                },
              ),
            ),
          ),
        ),
      );
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _ComposeSheet(
        onPosted: () async {
          if (sheetContext.mounted) Navigator.pop(sheetContext);
          setState(() => _page = 0);
          _message(t('Post published'));
          await _homeKey.currentState?._refresh(silent: true);
        },
      ),
    );
  }

  Future<void> _openProfile(String acct) async {
    final api = _activeApi;
    if (api == null) return;
    try {
      final result = await api.lookupAccount(acct);
      if (!mounted) return;
      setState(() {
        _profileAccount = result;
        _page = 4;
      });
    } catch (error) {
      if (mounted) _message('Could not load profile: $error');
    }
  }

  void _openAccount() {
    if (_currentAccount != null) {
      setState(() {
        _profileAccount = null;
        _page = 4;
      });
    } else {
      _login();
    }
  }

  Future<void> _login() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ConnectDialog(instance: _instance),
    );
    if (mounted) setState(() {});
  }

  /// Settings is reached from Profile, so it opens over the shell instead of
  /// taking a nav slot.
  void _settings() => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (routeContext) => Scaffold(
          appBar: AppBar(title: Text(t('Settings'))),
          body: SettingsScreen(
            instance: _instance,
            onSaveInstance: _saveInstance,
            onLogout: () {
              Navigator.pop(routeContext);
              _logout();
            },
          ),
        ),
      ));

  Future<void> _saveInstance(String value) async {
    if (value.isEmpty) return;
    try {
      final next = FediverseApi(value);
      _instance = next.instance.host;
      _appStore?.setPreferredInstance(_instance);
      if (_currentAccount == null) {
        _activeApi?.close();
        _activeApi = next;
      } else {
        next.close();
      }
      if (mounted) {
        setState(() {});
        _message('Default server: $_instance');
      }
    } catch (error) {
      if (mounted) _message('Invalid server address: $error');
    }
  }

  Future<void> _logout() async {
    final api = _activeApi;
    final id = _currentAccountId;
    if (api != null && id != null) await api.deleteToken(id);
    _appStore?.deleteAccount(id ?? '');
    api?.close();
    _currentAccount = null;
    _currentAccountId = null;
    _activeApi = FediverseApi(_instance);
    if (mounted) {
      setState(() {
        _page = 0;
        _profileAccount = null;
      });
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// Full-page settings: default server, language, cache, and account.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.instance,
      required this.onSaveInstance, required this.onLogout});
  final String instance;
  final ValueChanged<String> onSaveInstance;
  final VoidCallback onLogout;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _controller = TextEditingController(text: widget.instance);
  late String _language = _languageTag(_appStore?.preferredLanguage ?? 'system');
  late String _themeMode = _appStore?.setting('theme_mode', 'system') ?? 'system';
  late String _defaultVisibility =
      _appStore?.setting('default_visibility', 'public') ?? 'public';
  late bool _pushEnabled =
      _appStore?.boolSetting('push_enabled', fallback: true) ?? true;
  late String _pushEndpoint = _appStore?.setting('push_endpoint', '') ?? '';
  late bool _alwaysShowSensitive =
      _appStore?.boolSetting('always_show_sensitive') ?? false;
  late bool _compactCards = _appStore?.boolSetting('compact_cards') ?? false;

  /// Older builds stored the bare `en` / `id`; the dropdown only lists the
  /// regional tags, and an initialValue outside its items asserts.
  static String _languageTag(String tag) =>
      switch (tag.replaceAll('_', '-').toLowerCase()) {
        'system' => 'system',
        'en' || 'en-us' => 'en-us',
        'en-gb' => 'en-gb',
        'en-sg' => 'en-sg',
        'id' || 'id-id' => 'id-id',
        'ja' || 'ja-jp' => 'ja-jp',
        _ => 'en-us',
      };
  bool _clearing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    _appStore?.clearCaches();
    await CachedNetworkImage.wipe();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (mounted) {
      setState(() => _clearing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('Cache cleared'))),
      );
    }
  }

  Future<void> _configurePushEndpoint() async {
    final endpointCtrl = TextEditingController(text: _pushEndpoint);
    final saved = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('FCM / UnifiedPush endpoint')),
        content: TextField(
          controller: endpointCtrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://fcm.googleapis.com/fcm/send/...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, endpointCtrl.text.trim()),
            child: Text(t('Save')),
          ),
        ],
      ),
    );
    endpointCtrl.dispose();
    if (saved == null) return;
    setState(() => _pushEndpoint = saved);
    _appStore?.setSetting('push_endpoint', saved);
    if (saved.isNotEmpty && _currentAccount != null) {
      try {
        await _activeApi?.registerPushSubscription(endpoint: saved);
      } catch (_) {}
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('Push subscription updated'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _controller,
            decoration: InputDecoration(
                labelText: t('Default instance'),
                border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _language,
            decoration: InputDecoration(
                labelText: t('Language'),
                border: const OutlineInputBorder()),
            items: [
              DropdownMenuItem(
                  value: 'system', child: Text(t('System default'))),
              DropdownMenuItem(
                  value: 'en-us', child: Text(t('English (US)'))),
              DropdownMenuItem(
                  value: 'en-gb', child: Text(t('English (UK)'))),
              DropdownMenuItem(
                  value: 'en-sg', child: Text(t('English (SG)'))),
              DropdownMenuItem(
                  value: 'id-id', child: Text(t('Bahasa Indonesia'))),
              DropdownMenuItem(
                  value: 'ja-jp', child: Text(t('Japanese'))),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _language = value);
              _appStore?.setPreferredLanguage(value);
              // Hot swap: this bumps l10nVersion, and RumpunApp listens, so the
              // whole tree rebuilds with the new table and locale — no restart.
              loadL10n(value);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _defaultVisibility,
            decoration: InputDecoration(
                labelText: t('Default visibility'),
                border: const OutlineInputBorder()),
            items: [
              DropdownMenuItem(value: 'public', child: Text(t('Public'))),
              DropdownMenuItem(value: 'unlisted', child: Text(t('Quiet public'))),
              DropdownMenuItem(value: 'private', child: Text(t('Followers only'))),
              DropdownMenuItem(value: 'direct', child: Text(t('Mentioned only'))),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _defaultVisibility = value);
              _appStore?.setSetting('default_visibility', value);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _themeMode,
            decoration: InputDecoration(
                labelText: t('Theme'),
                border: const OutlineInputBorder()),
            items: [
              DropdownMenuItem(value: 'system', child: Text(t('System default'))),
              DropdownMenuItem(value: 'light', child: Text(t('Light'))),
              DropdownMenuItem(value: 'dark', child: Text(t('Dark'))),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _themeMode = value);
              _appStore?.setSetting('theme_mode', value);
              _appConfigVersion.value++;
            },
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => widget.onSaveInstance(_controller.text.trim()),
              child: Text(t('Save')),
            ),
          ),
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.notifications_active_outlined),
            title: Text(t('Push notifications (FCM)')),
            subtitle: Text(t('Receive background alerts for mentions, likes, and reposts')),
            value: _pushEnabled,
            onChanged: (value) {
              setState(() => _pushEnabled = value);
              _appStore?.setBoolSetting('push_enabled', value);
              if (!value && _currentAccount != null) {
                _activeApi?.deletePushSubscription().ignore();
              }
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cloud_sync_outlined),
            title: Text(t('FCM / UnifiedPush endpoint')),
            subtitle: Text(
              _pushEndpoint.isEmpty ? t('System default') : _pushEndpoint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _configurePushEndpoint,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.visibility_outlined),
            title: Text(t('Always show sensitive media')),
            value: _alwaysShowSensitive,
            onChanged: (value) {
              setState(() => _alwaysShowSensitive = value);
              _appStore?.setBoolSetting('always_show_sensitive', value);
              _appConfigVersion.value++;
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.view_compact_outlined),
            title: Text(t('Compact timeline cards')),
            value: _compactCards,
            onChanged: (value) {
              setState(() => _compactCards = value);
              _appStore?.setBoolSetting('compact_cards', value);
              _appConfigVersion.value++;
            },
          ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.help_outline),
            title: Text(t('Support & feedback')),
            subtitle: const Text('github.com/COXKPER/rumpun'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => launchUrl(Uri.parse(_supportUrl),
                mode: LaunchMode.externalApplication),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cleaning_services_outlined),
            title: Text(t('Clear cache')),
            subtitle: Text(t('Cache subtitle')),
            trailing: _clearing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : null,
            onTap: _clearing ? null : _clearCache,
          ),
          if (_currentAccount != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.logout,
                  color: Theme.of(context).colorScheme.error),
              title: Text(t('Log out'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: widget.onLogout,
            ),
        ],
      );
}

class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopBar({
    required this.title,
    required this.onAccount,
    required this.onSettings,
    this.onBookmarks,
    this.onRefresh,
    this.action,
  });
  final String title;
  final VoidCallback onAccount;
  final VoidCallback onSettings;
  final VoidCallback? onBookmarks;
  final VoidCallback? onRefresh;
  final Widget? action;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return AppBar(
      toolbarHeight: 52,
      scrolledUnderElevation: 0,
      backgroundColor:
          (isDark ? const Color(0xFF202422) : Colors.white).withValues(alpha: 0.96),
      shape: Border(
        bottom: BorderSide(
          color: theme.colorScheme.onSurface.withValues(alpha: isDark ? 0.12 : 0.10),
          width: 1,
        ),
      ),
      leadingWidth: 44,
      leading: const Icon(Icons.public, size: 20),
      titleSpacing: 0,
      title: Row(children: [
        Text(title,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFF38A979),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(_displayHost(_activeApi?.instance.host ?? _instance),
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark ? const Color(0xFF9AA4A0) : const Color(0xFF6B7470),
              )),
        ),
      ]),
      actions: [
        if (action != null) action!,
        IconButton(
          tooltip: _currentAccount == null ? t('Log in') : t('My account'),
          onPressed: onAccount,
          icon: _currentAccount == null
              ? const Icon(Icons.account_circle_outlined)
              : CircleAvatar(
                  radius: 14,
                  backgroundImage: CachedNetworkImage(
                      _currentAccount!['avatar'] as String? ?? '',
                      maxWidthPx: 56, maxHeightPx: 56),
                  onBackgroundImageError: (_, __) {},
                ),
        ),
        IconButton(
            tooltip: t('Settings'),
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined)),
        MenuAnchor(
          builder: (context, controller, _) => IconButton(
            tooltip: t('More'),
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            icon: const Icon(Icons.more_vert),
          ),
          menuChildren: [
            if (onRefresh != null)
              MenuItemButton(
                leadingIcon: const Icon(Icons.refresh, size: 18),
                onPressed: onRefresh,
                child: Text(t('Refresh')),
              ),
            if (onBookmarks != null)
              MenuItemButton(
                leadingIcon: const Icon(Icons.bookmark_border, size: 18),
                onPressed: onBookmarks,
                child: Text(t('Bookmarks')),
              ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.tune, size: 18),
              onPressed: onSettings,
              child: Text(t('Settings')),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.help_outline, size: 18),
              onPressed: () => launchUrl(Uri.parse(_supportUrl),
                  mode: LaunchMode.externalApplication),
              child: Text(t('Support & feedback')),
            ),
          ],
        ),
      ],
    );
  }
}

class _OAuthCancelled implements Exception {}

class _ComposeSheet extends StatefulWidget {
  const _ComposeSheet({required this.onPosted, this.replyTo});
  final Future<void> Function() onPosted;
  /// Set when the sheet is opened from a post's Reply button; the draft is
  /// kept under `reply:<statusId>` and the status is posted as a real reply.
  final Map<String, dynamic>? replyTo;
  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  final _text = TextEditingController();
  final _spoiler = TextEditingController();
  final _alt = <TextEditingController>[];
  final _attachments = <Map<String, dynamic>>[];
  String _visibility = 'public';
  bool _posting = false;
  String? _error;
  bool _hasDraft = false;
  bool _showMediaWarning = false;
  bool _spoilerEnabled = false;
  bool _sensitiveMedia = false;
  bool _pollEnabled = false;
  final _pollOptions = [TextEditingController(), TextEditingController()];
  static final _sensitiveWordPattern = RegExp(r'\b(suicide|kill myself|self[- ]?harm|cutting)\b', caseSensitive: false);

  String get _draftKey => widget.replyTo == null
      ? 'compose'
      : 'reply:${widget.replyTo!['id'] ?? ''}';
  String? get _replyToId => widget.replyTo?['id'] as String?;
  String? get _replyToName => _replyName(widget.replyTo);

  static String? _replyName(Map<String, dynamic>? status) {
    final account = status?['account'] as Map<String, dynamic>? ?? {};
    final name = (account['display_name'] as String?)?.isNotEmpty == true
        ? account['display_name'] as String?
        : account['username'] as String?;
    return name ?? account['acct'] as String?;
  }

  @override
  void initState() {
    super.initState();
    _visibility = _appStore?.setting('default_visibility', 'public') ?? 'public';
    // Restore the draft for this slot (a half-written reply survives a tab
    // switch), then keep it saved as the user types.
    final draft = _appStore?.draft(_draftKey);
    if (draft != null) {
      final text = draft['text'] as String? ?? '';
      final spoiler = draft['spoiler'] as String? ?? '';
      _visibility = draft['visibility'] as String? ?? 'public';
      _spoilerEnabled = spoiler.isNotEmpty;
      _hasDraft = text.trim().isNotEmpty || spoiler.trim().isNotEmpty;
      if (text.isNotEmpty) _text.text = text;
      if (spoiler.isNotEmpty) _spoiler.text = spoiler;
    }
    _text.addListener(_onChanged);
    _spoiler.addListener(_onChanged);
  }

  void _onChanged() {
    final hasDraft =
        _text.text.trim().isNotEmpty || _spoiler.text.trim().isNotEmpty;
    if (hasDraft != _hasDraft) setState(() => _hasDraft = hasDraft);
    _appStore?.saveDraft(_draftKey,
        text: _text.text,
        spoiler: _spoiler.text,
        visibility: _visibility,
        inReplyToId: _replyToId,
        inReplyToAcct: _replyToName,
        mediaCount: _attachments.length);
  }

  @override
  void dispose() {
    for (final controller in _alt) {
      controller.dispose();
    }
    for (final controller in _pollOptions) {
      controller.dispose();
    }
    _text.dispose();
    _spoiler.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    const typeGroup = XTypeGroup(label: 'Media', extensions: [
      'jpg', 'jpeg', 'png', 'gif', 'webp', 'mp4', 'webm', 'mov', 'mp3', 'ogg'
    ]);
    final files = await openFiles(acceptedTypeGroups: [typeGroup]);
    for (final file in files) {
      if (_attachments.length >= 4) break;
      // Keep the map itself: indexOf on a fresh literal always returned -1.
      final entry = <String, dynamic>{
        'path': file.path,
        'status': 'uploading'
      };
      final alt = TextEditingController();
      _alt.add(alt);
      setState(() => _attachments.add(entry));
      try {
        final media = await _activeApi!.uploadMedia(File(file.path));
        if (!mounted) return;
        setState(() {
          entry['status'] = 'done';
          entry['id'] = media['id'];
          entry['preview'] = media['preview_url'] as String?;
        });
        _saveAltDescriptions();
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _attachments.remove(entry);
          _error = t('Upload failed: $error');
        });
      }
    }
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments.removeAt(index);
      _alt.removeAt(index).dispose();
      // An unsent upload is just dropped; a finished one is abandoned on the
      // server, where it expires on its own.
    });
    _onChanged();
  }

  /// Pushes typed alt text to the server as each field loses focus. Deferred,
  /// not streamed, because /api/v1/media PUT is rate-limited.
  Future<void> _saveAltDescriptions() async {
    for (final (i, entry) in _attachments.indexed) {
      if (entry['status'] != 'done') continue;
      final description = _alt[i].text.trim();
      if (description.isEmpty || entry['altSaved'] == description) continue;
      try {
        await _activeApi!.updateMedia(entry['id'] as String,
            description: description);
        entry['altSaved'] = description;
      } catch (_) {
        // Alt text is best-effort; the post still goes out without it.
      }
    }
  }

  /// Compose guard from the product spec: images need descriptions, and
  /// sensitive words need a content warning. Warn once, don't block.
  bool _checkBeforeSend() {
    final needsAlt = _attachments.any((entry) =>
        entry['status'] == 'done' &&
        (_alt.isEmpty || _alt[_attachments.indexOf(entry)].text.trim().isEmpty));
    final needsSpoiler = !_spoilerEnabled &&
        _sensitiveWordPattern.hasMatch(_text.text);
    if (needsAlt || needsSpoiler) {
      setState(() => _showMediaWarning = true);
      return false;
    }
    return true;
  }

  Future<void> _submit({bool force = false}) async {
    final content = _text.text.trim();
    if (content.isEmpty && _attachments.isEmpty || _posting) return;
    if (!force && !_checkBeforeSend()) return;
    setState(() {
      _posting = true;
      _error = null;
      _showMediaWarning = false;
    });
    await _saveAltDescriptions();
    final pollData = _pollEnabled
        ? {
            'options': _pollOptions
                .map((c) => c.text.trim())
                .where((t) => t.isNotEmpty)
                .toList(),
            'expires_in': 86400,
          }
        : null;
    try {
      await _activeApi!.post(
        content.isEmpty ? '.' : content,
        visibility: _visibility,
        spoilerText: _spoilerEnabled ? _spoiler.text : null,
        inReplyToId: _replyToId,
        mediaIds: [
          for (final attachment in _attachments) attachment['id'] as String
        ],
        sensitive: _sensitiveMedia,
        poll: (pollData?['options'] as List?)?.length != null &&
                (pollData!['options'] as List).length >= 2
            ? pollData
            : null,
      );
      _appStore?.deleteDraft(_draftKey);
      _text.clear();
      _spoiler.clear();
      await widget.onPosted();
    } catch (error) {
      if (mounted) {
        setState(() {
          _posting = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = 500 - _text.text.length;
    final replyTo = widget.replyTo;
    return Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(replyTo == null ? t('New post') : t('Reply to @{name}', args: {'name': _replyToName ?? ''}),
                style: theme.textTheme.titleMedium),
            const Spacer(),
            if (_hasDraft)
              IconButton(
                  tooltip: t('Discard draft'),
                  onPressed: _posting
                      ? null
                      : () {
                          _appStore?.deleteDraft(_draftKey);
                          for (final controller in _alt) {
                            controller.dispose();
                          }
                          _alt.clear();
                          setState(() {
                            _attachments.clear();
                            _text.clear();
                            _spoiler.clear();
                            _hasDraft = false;
                          });
                        },
                  icon: const Icon(Icons.delete_outline)),
            IconButton(
                tooltip: t('Close'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close)),
          ]),
          if (replyTo != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_plainText(replyTo['content'] as String? ?? ''),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall)),
          TextField(
              controller: _text,
              autofocus: true,
              minLines: 4,
              maxLines: 8,
              maxLength: 500,
              decoration: InputDecoration(
                  hintText: replyTo == null
                      ? t('Write a post')
                      : t('Write your reply'),
                  border: const OutlineInputBorder())),
          if (_attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (index, attachment) in _attachments.indexed)
                  Stack(children: [
                    ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                            width: 88,
                            height: 88,
                            child: Stack(fit: StackFit.expand, children: [
                              Container(color: theme.colorScheme.surfaceContainerHighest),
                              if (attachment['preview'] is String)
                                Image(
                                    image: CachedNetworkImage(
                                        attachment['preview'] as String,
                                        maxWidthPx: 200),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined))
                              else if (attachment['status'] == 'uploading')
                                const Center(
                                    child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2))),
                            ]))),
                    Positioned(
                        right: 0, top: 0,
                        child: IconButton(
                            tooltip: t('Remove'),
                            onPressed: _posting ? null : () => _removeAttachment(index),
                            icon: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                    color: theme.colorScheme.surface.withValues(alpha: 0.85),
                                    shape: BoxShape.circle),
                                child: Icon(Icons.close, size: 16, color: theme.colorScheme.onSurface))))
                  ]),
              ]),
            ),
          // Alt text per attachment: a11y is a product requirement, so the
          // field sits inline rather than behind a dialog.
          for (final (index, attachment) in _attachments.indexed)
            if (attachment['status'] == 'done')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                    controller: _alt[index],
                    enabled: !_posting,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.accessibility_new, size: 18),
                      prefixIconConstraints: const BoxConstraints(minWidth: 36),
                      hintText: t('Describe image for screen readers'),
                      border: const OutlineInputBorder(),
                    ))),
          const SizedBox(height: 10),
          if (_spoilerEnabled)
            TextField(
                controller: _spoiler,
                enabled: !_posting,
                decoration: InputDecoration(
                    isDense: true,
                    hintText: t('Write a content warning'),
                    border: const OutlineInputBorder())),
          if (_pollEnabled)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(children: [
                for (final (idx, opt) in _pollOptions.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: opt,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: t('Option {index}', args: {'index': '${idx + 1}'}),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                if (_pollOptions.length < 4)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _pollOptions.add(TextEditingController())),
                      icon: const Icon(Icons.add, size: 16),
                      label: Text(t('Add option')),
                    ),
                  ),
              ]),
            ),
          if (_showMediaWarning)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Card(
                color: theme.colorScheme.errorContainer,
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 20, color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          _attachments.indexed.any((item) =>
                                  item.$2['status'] == 'done' &&
                                  _alt[item.$1].text.trim().isEmpty)
                              ? t('Add a description to your images before posting. '
                                  'People using screen readers cannot see them.')
                              : t('This post mentions sensitive topics. '
                                  'Consider adding a content warning.'),
                          style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                    ),
                    TextButton(
                      onPressed: _posting ? null : _submitAnyway,
                      child: Text(t('Post anyway'),
                          style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                    ),
                  ]),
                ),
              )),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
          Row(children: [
            IconButton(
                tooltip: t('Attach media'),
                onPressed: _attachments.length >= 4 || _posting ? null : _pickMedia,
                icon: const Icon(Icons.add_photo_alternate_outlined)),
            if (_serverCustomEmojis.isNotEmpty)
              PopupMenuButton<String>(
                tooltip: t('Custom emojis'),
                icon: const Icon(Icons.sentiment_satisfied_alt_outlined),
                onSelected: (code) {
                  final text = _text.text;
                  final selection = _text.selection;
                  final insertion = ' :$code: ';
                  if (selection.isValid && selection.start >= 0) {
                    _text.text = text.replaceRange(selection.start, selection.end, insertion);
                    _text.selection = TextSelection.collapsed(offset: selection.start + insertion.length);
                  } else {
                    _text.text = '$text$insertion';
                    _text.selection = TextSelection.collapsed(offset: _text.text.length);
                  }
                  _onChanged();
                },
                itemBuilder: (context) => [
                  for (final emoji in _serverCustomEmojis.take(30))
                    PopupMenuItem<String>(
                      value: emoji['shortcode'] as String? ?? '',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (emoji['static_url'] != null || emoji['url'] != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Image(
                                image: CachedNetworkImage(
                                  (emoji['static_url'] ?? emoji['url']) as String,
                                  maxWidthPx: 48,
                                  maxHeightPx: 48,
                                ),
                                width: 20,
                                height: 20,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Icon(Icons.tag_faces, size: 20),
                              ),
                            ),
                          Text(':${emoji['shortcode']}:'),
                        ],
                      ),
                    ),
                ],
              ),
            IconButton(
                tooltip: t('Poll'),
                onPressed: _posting
                    ? null
                    : () => setState(() => _pollEnabled = !_pollEnabled),
                icon: Icon(_pollEnabled ? Icons.poll : Icons.poll_outlined,
                    color: _pollEnabled ? theme.colorScheme.primary : null)),
            IconButton(
                tooltip: t('Content warning'),
                onPressed: _posting
                    ? null
                    : () => setState(() {
                          _spoilerEnabled = !_spoilerEnabled;
                          if (!_spoilerEnabled) _spoiler.clear();
                        }),
                icon: Icon(_spoilerEnabled ? Icons.shield : Icons.shield_outlined,
                    color: _spoilerEnabled ? theme.colorScheme.primary : null)),
            if (_attachments.isNotEmpty)
              IconButton(
                  tooltip: t('Mark as sensitive'),
                  onPressed: _posting
                      ? null
                      : () => setState(() => _sensitiveMedia = !_sensitiveMedia),
                  icon: Icon(_sensitiveMedia ? Icons.visibility_off : Icons.visibility_off_outlined,
                      color: _sensitiveMedia ? theme.colorScheme.error : null)),
            const SizedBox(width: 4),
            DropdownButton<String>(
              value: _visibility,
              underline: const SizedBox.shrink(),
              onChanged: _posting
                  ? null
                  : (value) => setState(() {
                        _visibility = value ?? 'public';
                        _onChanged();
                      }),
              items: [
                DropdownMenuItem(value: 'public', child: Row(children: [
                  const Icon(Icons.public, size: 16),
                  const SizedBox(width: 6),
                  Text(t('Public')),
                ])),
                DropdownMenuItem(value: 'unlisted', child: Row(children: [
                  const Icon(Icons.lock_open, size: 16),
                  const SizedBox(width: 6),
                  Text(t('Quiet public')),
                ])),
                DropdownMenuItem(value: 'private', child: Row(children: [
                  const Icon(Icons.lock_outline, size: 16),
                  const SizedBox(width: 6),
                  Text(t('Followers only')),
                ])),
                DropdownMenuItem(value: 'direct', child: Row(children: [
                  const Icon(Icons.alternate_email, size: 16),
                  const SizedBox(width: 6),
                  Text(t('Mentioned only')),
                ])),
              ],
            ),
            const Spacer(),
            SizedBox(
              width: 22,
              height: 22,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: (_text.text.length / 500.0).clamp(0.0, 1.0),
                    strokeWidth: 2.5,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    color: remaining < 20
                        ? theme.colorScheme.error
                        : remaining < 50
                            ? Colors.orange
                            : theme.colorScheme.primary,
                  ),
                  if (remaining < 50)
                    Text('$remaining',
                        style: theme.textTheme.labelSmall?.copyWith(fontSize: 8)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _text.text.trim().isEmpty && _attachments.isEmpty ||
                      _posting ||
                      _attachments.any((a) => a['status'] != 'done')
                  ? null
                  : _submit,
              child: Text(_posting ? t('Posting…') : t('Post')),
            ),
          ]),
        ]),
      );
  }

  Future<void> _submitAnyway() async {
    setState(() => _showMediaWarning = false);
    await _submit(force: true);
  }
}

class _ConnectDialog extends StatefulWidget {
  const _ConnectDialog({required this.instance});
  final String instance;
  @override
  State<_ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<_ConnectDialog> {
  late final _instanceController = TextEditingController(text: widget.instance);
  bool _busy = false;
  String? _error;
  Completer<void>? _cancelOAuth;
  @override
  void dispose() {
    _instanceController.dispose();
    super.dispose();
  }

  void _cancel() {
    if (_busy) {
      if (!(_cancelOAuth?.isCompleted ?? true)) _cancelOAuth!.complete();
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    _cancelOAuth = Completer<void>();
    final api = FediverseApi(_instanceController.text.trim());
    HttpServer? server;
    AppStore? store;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final redirectUri = 'http://127.0.0.1:${server.port}/oauth/callback';
      final random = Random.secure();
      final state = base64Url
          .encode(List<int>.generate(32, (_) => random.nextInt(256)))
          .replaceAll('=', '');
      final callback = receiveOAuthCode(server, state);
      final app = await api.registerApp(redirectUri);
      final clientId = app['client_id'] as String?;
      final clientSecret = app['client_secret'] as String?;
      if (clientId == null || clientSecret == null) {
        throw const FormatException('The server did not return OAuth app credentials.');
      }
      if (!await launchUrl(
          api.authorizationUri(
              clientId: clientId, redirectUri: redirectUri, state: state),
          mode: LaunchMode.externalApplication)) {
        throw StateError('Could not open the system browser.');
      }
      final code = await Future.any([
        callback.timeout(const Duration(minutes: 5),
            onTimeout: () => throw TimeoutException('Authorization timed out.')),
        _cancelOAuth!.future.then<String>((_) => throw _OAuthCancelled()),
      ]);
      await api.exchangeCode(
          clientId: clientId,
          clientSecret: clientSecret,
          code: code,
          redirectUri: redirectUri);
      final account = await api.currentUser();
      final accountId = account['id'];
      if (accountId == null) throw const FormatException('The server returned no account ID.');
      final id = '$accountId@${api.instance.host}';
      await api.saveToken(id);
      store = _appStore ?? await AppStore.open();
      store.saveAccount(
          id: id,
          instance: api.instance.toString(),
          username: account['username'] as String?,
          displayName: account['display_name'] as String?);
      final oldApi = _activeApi;
      _activeApi = api;
      _appStore = store;
      _currentAccount = account;
      _currentAccountId = id;
      store.setPreferredInstance(api.instance.host);
      _instanceController.text = api.instance.host;
      _instance = api.instance.host;
      oldApi?.close();
      if (mounted) Navigator.pop(context);
    } on _OAuthCancelled {
      api.close();
    } catch (error) {
      store?.close();
      api.close();
      if (mounted) setState(() => _error = error.toString());
    } finally {
      await server?.close(force: true);
      _cancelOAuth = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(t('Log in')),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Choose your home server. Authorization opens in your browser.'),
            const SizedBox(height: 12),
            TextField(
                controller: _instanceController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Instance')),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ]),
        ),
        actions: [
          TextButton(onPressed: _cancel, child: Text(t('Cancel'))),
          FilledButton(
              onPressed: _busy ? null : _connect,
              child: Text(_busy ? 'Waiting…' : 'Continue')),
        ],
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onOpenProfile, this.onCompose});
  final ValueChanged<String> onOpenProfile;
  final VoidCallback? onCompose;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _feed = 0;
  int _reqId = 0;
  List<Map<String, dynamic>> _statuses = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  final _scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // Show the cached feed instantly; the network refresh then updates it.
    final cached = _appStore?.cachedStatuses('feed-0');
    if (cached != null && cached.isNotEmpty) {
      _statuses = cached;
      _loading = false;
    }
    _refresh(silent: _statuses.isNotEmpty);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic);
    }
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 600) _loadMore();
  }

  /// Fetches the next page with max_id; silent on failure (pull-to-refresh retries).
  Future<void> _loadMore() async {
    final api = _activeApi;
    if (api == null || _loading || _loadingMore || !_hasMore || _statuses.isEmpty) {
      return;
    }
    final lastId = _statuses.last['id'] as String?;
    if (lastId == null || lastId.isEmpty) return;
    final reqId = _reqId;
    final feed = _feed;
    setState(() => _loadingMore = true);
    try {
      final data = await api.timeline(
          type: feed == 0 && _currentAccount != null ? 'home' : 'public',
          local: feed == 1,
          maxId: lastId);
      if (!mounted || reqId != _reqId) return;
      final seen = {for (final status in _statuses) status['id']};
      final fresh = data.where((s) => !seen.contains(s['id'])).toList();
      setState(() {
        _statuses = [..._statuses, ...fresh];
        _hasMore = fresh.isNotEmpty;
      });
      if (fresh.isNotEmpty) _appStore?.cacheStatuses('feed-$feed', fresh);
    } catch (_) {
      // Keep the current page; the next scroll retries.
    } finally {
      if (mounted && reqId == _reqId) setState(() => _loadingMore = false);
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    final api = _activeApi;
    if (api == null) return;
    final reqId = ++_reqId;
    final feed = _feed;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await api.timeline(
          type: feed == 0 && _currentAccount != null ? 'home' : 'public',
          local: feed == 1);
      if (!mounted || reqId != _reqId) return;
      _appStore?.cacheStatuses('feed-$feed', data);
      setState(() {
        _statuses = data;
        _hasMore = data.isNotEmpty;
      });
    } catch (error) {
      if (mounted && reqId == _reqId && !silent) setState(() => _error = '$error');
    } finally {
      if (mounted && reqId == _reqId) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(children: [
        _TimelineFilter(
          selected: _feed,
          options: [t('Following'), t('Local'), t('Federated')],
          onSelect: (i) {
            if (i == _feed) {
              _scrollToTop();
              _refresh(silent: _statuses.isNotEmpty);
              return;
            }
            // Cached feed renders instantly; refresh reconciles in the background.
            final cached = _appStore?.cachedStatuses('feed-$i');
            final hasCache = cached != null && cached.isNotEmpty;
            setState(() {
              _feed = i;
              _hasMore = true;
              _loadingMore = false;
              _error = null;
              _statuses = hasCache ? cached : [];
            });
            if (_scroll.hasClients) _scroll.jumpTo(0);
            _refresh(silent: hasCache);
          },
        ),
        if (_currentAccount != null && widget.onCompose != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Card(
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: widget.onCompose,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    _Avatar(account: _currentAccount!, radius: 16),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        t('What do you want to share?'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    Icon(Icons.edit_outlined,
                        size: 20, color: theme.colorScheme.primary),
                  ]),
                ),
              ),
            ),
          ),
        if (_currentAccount == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Material(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => context
                    .findAncestorStateOfType<_RumpunShellState>()
                    ?._openAccount(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(children: [
                    Icon(Icons.public, size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t('Public timeline · Sign in to follow accounts and post'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        size: 16, color: theme.colorScheme.onSurfaceVariant),
                  ]),
                ),
              ),
            ),
          ),
        SizedBox(
          height: 2,
          child: _loading ? const LinearProgressIndicator(minHeight: 2) : null,
        ),
        if (_error != null && _statuses.isEmpty)
          Expanded(child: _StateMessage(message: _error!, action: _refresh))
        else if (_statuses.isEmpty && !_loading)
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: 220,
                    child: Center(child: Text(t('No posts yet'))),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                itemCount: _statuses.length + (_loadingMore ? 1 : 0),
                // Ghost feeds the blur-ahead area so scrolling never shows blanks.
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) => i == _statuses.length
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                            child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2))))
                    : _PostTile(
                        key: ValueKey(_statuses[i]['id'] ?? i),
                        post: Post(_statuses[i], _activeApi!.instance.host),
                        onProfile: widget.onOpenProfile,
                        onTap: () => _openThread(context, _statuses[i]),
                        onReply: (status) =>
                            _openThread(context, status, focusReply: true),
                      ),
              ),
            ),
          ),
      ]);
  }

  void _openBookmarks() {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    if (wide) {
      showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
            child: const _BookmarksSheet(),
          ),
        ),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _BookmarksSheet(),
    );
  }

  Future<void> _openThread(BuildContext context, Map<String, dynamic> status,
      {bool focusReply = false}) {
    final target = status['reblog'] as Map<String, dynamic>? ?? status;
    final focusId = target['id'] as String? ?? '';
    return showDialog<void>(
      context: context,
      builder: (_) => _ThreadDialog(
          status: target,
          focusId: focusId,
          openReply: focusReply,
          onProfile: widget.onOpenProfile),
    );
  }
}

/// Conversation view: ancestors above, the opened post highlighted, then
/// descendants nested one indent per reply level.
class _ThreadDialog extends StatefulWidget {
  const _ThreadDialog({required this.status, required this.focusId,
      this.openReply = false, required this.onProfile});
  final Map<String, dynamic> status;
  final String focusId;
  /// Open with the composer already aimed at the focused post.
  final bool openReply;
  final ValueChanged<String> onProfile;

  @override
  State<_ThreadDialog> createState() => _ThreadDialogState();
}

class _ThreadDialogState extends State<_ThreadDialog> {
  late Future<List<Map<String, dynamic>>> _thread;
  @override
  void initState() {
    super.initState();
    _thread = _activeApi!.thread(widget.focusId);
    if (widget.openReply) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reply(widget.status));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(children: [
        Text(t('Conversation')),
        const Spacer(),
        IconButton(
            tooltip: t('Close'),
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close)),
      ]),
      content: SizedBox(
        width: 560,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _thread,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _StateMessage(
                  message: '${snapshot.error}', action: () => Navigator.pop(context));
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snapshot.data ?? const <Map<String, dynamic>>[];
            final ancestors = <Map<String, dynamic>>[];
            final descendants = <Map<String, dynamic>>[];
            for (final item in items) {
              if (item['id'] == widget.focusId) continue;
              if (item['in_reply_to_id'] == null) {
                ancestors.add(item);
              } else {
                descendants.add(item);
              }
            }
            return CustomScrollView(
              shrinkWrap: true,
              slivers: [
                for (final item in ancestors)
                  SliverToBoxAdapter(child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PostTile(
                        post: Post(item, _activeApi!.instance.host),
                        onProfile: widget.onProfile,
                        onReply: _reply,
                        onTap: null),
                  )),
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: _green.withValues(alpha: 0.7), width: 1.5),
                      borderRadius: BorderRadius.circular(12)),
                    child: _PostTile(
                        post: Post(widget.status, _activeApi!.instance.host),
                        onProfile: widget.onProfile,
                        onReply: _reply,
                        onTap: null),
                  ),
                )),
                for (final entry in _nested(descendants, widget.focusId))
                  SliverToBoxAdapter(child: Padding(
                    padding: EdgeInsets.only(
                        left: 12.0 * entry.depth, bottom: 8),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                          width: 2,
                          margin: const EdgeInsets.only(right: 8, top: 8),
                          color: theme.dividerColor),
                      Expanded(child: _PostTile(
                          post: Post(entry.status, _activeApi!.instance.host),
                          onProfile: widget.onProfile,
                          onReply: _reply,
                          onTap: null)),
                    ]),
                  )),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Flattens the descendant forest into (status, depth) pairs by walking
  /// in_reply_to_id. Mastodon's context is chronological, so a stable
  /// insertion-ordered DFS is enough.
  List<_ThreadNode> _nested(List<Map<String, dynamic>> descendants, String rootId) {
    final byParent = <String, List<Map<String, dynamic>>>{};
    for (final item in descendants) {
      final parent = item['in_reply_to_id'] as String? ?? '';
      byParent.putIfAbsent(parent, () => []).add(item);
    }
    final out = <_ThreadNode>[];
    void walk(String parentId, int depth) {
      for (final child in byParent[parentId] ?? const <Map<String, dynamic>>[]) {
        out.add(_ThreadNode(child, depth));
        walk(child['id'] as String? ?? '', depth + 1);
      }
    }
    walk(rootId, 0);
    return out;
  }

  Future<void> _reply(Map<String, dynamic> status) async {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    if (wide) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: SingleChildScrollView(
              child: _ComposeSheet(replyTo: status, onPosted: () async {}),
            ),
          ),
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _ComposeSheet(replyTo: status, onPosted: () async {}),
      );
    }
    // Replying changes reply counts; reload the thread when the sheet closes.
    if (mounted) setState(() => _thread = _activeApi!.thread(widget.focusId));
  }
}

class _ThreadNode {
  const _ThreadNode(this.status, this.depth);
  final Map<String, dynamic> status;
  final int depth;
}

/// Saved posts, fetched fresh each open; bookmarks are account-scoped.
class _BookmarksSheet extends StatefulWidget {
  const _BookmarksSheet();
  @override
  State<_BookmarksSheet> createState() => _BookmarksSheetState();
}

class _BookmarksSheetState extends State<_BookmarksSheet> {
  List<Map<String, dynamic>> _statuses = [];
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Bookmarks are account-scoped, so the key carries the account id.
    final key = 'bookmarks-${_currentAccountId ?? 'anon'}';
    final cached = _appStore?.cachedStatuses(key);
    if (cached != null && cached.isNotEmpty) {
      setState(() {
        _statuses = cached;
        _loading = false;
      });
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await _activeApi!.bookmarks();
      if (mounted) setState(() => _statuses = data);
      _appStore?.cacheStatuses(key, data);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(t('Bookmarks'), style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            IconButton(
                tooltip: t('Close'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close)),
          ]),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) _StateMessage(message: _error!, action: _load),
          if (_statuses.isEmpty && !_loading && _error == null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text(t('No bookmarks yet')))),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 20),
              itemCount: _statuses.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _PostTile(
                post: Post(_statuses[i], _activeApi!.instance.host),
                onProfile: (acct) {
                  // Capture the shell before popping: this sheet's context is
                  // defunct once the route is gone.
                  final shell =
                      context.findAncestorStateOfType<_RumpunShellState>();
                  Navigator.pop(context);
                  shell?._openProfile(acct);
                },
                onTap: () {},
              ),
            ),
          ),
        ]),
      );
}

/// Dedicated Fediverse posts stream (Federated, Local, Trending).
class TweetsScreen extends StatefulWidget {
  const TweetsScreen({super.key, required this.onOpenProfile});
  final ValueChanged<String> onOpenProfile;
  @override
  State<TweetsScreen> createState() => _TweetsScreenState();
}

class _TweetsScreenState extends State<TweetsScreen> {
  int _feed = 0;
  int _reqId = 0;
  List<Map<String, dynamic>> _statuses = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  final _scroll = ScrollController();

  String get _cacheKey => 'tweets-fediverse-$_feed';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    final cached = _appStore?.cachedStatuses(_cacheKey);
    if (cached != null && cached.isNotEmpty) {
      _statuses = cached;
      _loading = false;
    }
    refresh(silent: _statuses.isNotEmpty);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic);
    }
  }

  void _onScroll() {
    if (_feed < 2 && _scroll.position.extentAfter < 600) _loadMore();
  }

  Future<void> _loadMore() async {
    final api = _activeApi;
    if (api == null || _feed == 2 || _loading || _loadingMore || !_hasMore || _statuses.isEmpty) {
      return;
    }
    final lastId = _statuses.last['id'] as String?;
    if (lastId == null || lastId.isEmpty) return;
    final reqId = _reqId;
    final feed = _feed;
    setState(() => _loadingMore = true);
    try {
      final data = await api.timeline(
          type: 'public', local: feed == 1, maxId: lastId);
      if (!mounted || reqId != _reqId) return;
      final seen = {for (final status in _statuses) status['id']};
      final fresh = data.where((s) => !seen.contains(s['id'])).toList();
      setState(() {
        _statuses = [..._statuses, ...fresh];
        _hasMore = fresh.isNotEmpty;
      });
      if (fresh.isNotEmpty) _appStore?.cacheStatuses('tweets-fediverse-$feed', fresh);
    } catch (_) {
    } finally {
      if (mounted && reqId == _reqId) setState(() => _loadingMore = false);
    }
  }

  Future<void> refresh({bool silent = false}) async {
    final api = _activeApi;
    if (api == null) return;
    final reqId = ++_reqId;
    final feed = _feed;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = feed == 2
          ? await api.trendingStatuses(limit: 20)
          : await api.timeline(type: 'public', local: feed == 1);
      if (!mounted || reqId != _reqId) return;
      _appStore?.cacheStatuses('tweets-fediverse-$feed', data);
      setState(() {
        _statuses = data;
        _hasMore = feed < 2 && data.isNotEmpty;
      });
    } catch (error) {
      if (mounted && reqId == _reqId && !silent) setState(() => _error = '$error');
    } finally {
      if (mounted && reqId == _reqId) setState(() => _loading = false);
    }
  }

  Future<void> _openThread(BuildContext context, Map<String, dynamic> status,
      {bool focusReply = false}) {
    final target = status['reblog'] as Map<String, dynamic>? ?? status;
    final focusId = target['id'] as String? ?? '';
    return showDialog<void>(
      context: context,
      builder: (_) => _ThreadDialog(
          status: target,
          focusId: focusId,
          openReply: focusReply,
          onProfile: widget.onOpenProfile),
    );
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        _TimelineFilter(
          selected: _feed,
          options: [t('Federated'), t('Local'), t('Trending')],
          onSelect: (i) {
            if (i == _feed) {
              _scrollToTop();
              refresh(silent: _statuses.isNotEmpty);
              return;
            }
            final cached = _appStore?.cachedStatuses('tweets-fediverse-$i');
            final hasCache = cached != null && cached.isNotEmpty;
            setState(() {
              _feed = i;
              _hasMore = i < 2;
              _loadingMore = false;
              _error = null;
              _statuses = hasCache ? cached : [];
            });
            if (_scroll.hasClients) _scroll.jumpTo(0);
            refresh(silent: hasCache);
          },
        ),
        SizedBox(
          height: 2,
          child: _loading ? const LinearProgressIndicator(minHeight: 2) : null,
        ),
        if (_error != null && _statuses.isEmpty)
          Expanded(child: _StateMessage(message: _error!, action: refresh))
        else if (_statuses.isEmpty && !_loading)
          Expanded(
            child: RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: 220,
                    child: Center(child: Text(t('No posts yet'))),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: refresh,
              child: ListView.separated(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                itemCount: _statuses.length + (_loadingMore ? 1 : 0),
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) => i == _statuses.length
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                            child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2))))
                    : _PostTile(
                        key: ValueKey(_statuses[i]['id'] ?? i),
                        post: Post(_statuses[i], _activeApi!.instance.host),
                        onProfile: widget.onOpenProfile,
                        onTap: () => _openThread(context, _statuses[i]),
                        onReply: (status) =>
                            _openThread(context, status, focusReply: true),
                      ),
              ),
            ),
          ),
      ]);
}

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key, required this.onOpenProfile});
  final ValueChanged<String> onOpenProfile;
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _search = TextEditingController();
  String _category = 'Tags';
  String _query = '';
  List<Map<String, dynamic>> _results = [];
  List<Map<String, dynamic>> _tags = [];
  List<Map<String, dynamic>> _people = [];
  List<Map<String, dynamic>> _statuses = [];
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _trending();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _trending() async {
    // Trends move slowly; a cached paint beats a spinner on every tab switch.
    final cached = _appStore?.cachedStatuses('trending');
    if (cached != null && cached.isNotEmpty) {
      final snapshot = cached.first;
      setState(() {
        _tags = (snapshot['tags'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _people =
            (snapshot['people'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _statuses =
            (snapshot['statuses'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _loading = false;
      });
    }
    try {
      final api = _activeApi!;
      final results = await Future.wait([
        api.trendingTags(),
        api.trendingAccounts(),
        api.trendingStatuses(),
      ]);
      if (mounted) {
        setState(() {
          _tags = results[0];
          _people = results[1];
          _statuses = results[2];
          _loading = false;
        });
      }
      _appStore?.cacheStatuses('trending', [
        {'id': 'trending', 'tags': results[0],
          'people': results[1], 'statuses': results[2]},
      ]);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  Future<void> _doSearch(String query) async {
    setState(() {
      _query = query.trim();
      _error = null;
    });
    if (_query.isEmpty) {
      _trending();
      return;
    }
    setState(() => _loading = true);
    try {
      final type = switch (_category) {
        'People' => 'accounts',
        'Tags' => 'hashtags',
        'Posts' => 'statuses',
        _ => null,
      };
      final data = await _activeApi!.search(_query, type: type);
      if (mounted) {
        setState(() {
          _results = (data['accounts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _tags = (data['hashtags'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _statuses = (data['statuses'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) setState(() { _error = '$error'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SearchBar(
            controller: _search,
            hintText: t('Search accounts, tags, or posts'),
            leading: const Icon(Icons.search),
            onSubmitted: _doSearch,
            trailing: [
              if (_search.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                    _trending();
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'Tags', label: Text(t('Tags'))),
            ButtonSegment(value: 'People', label: Text(t('People'))),
            ButtonSegment(value: 'Posts', label: Text(t('Posts'))),
          ],
          selected: {_category},
          onSelectionChanged: (value) {
            setState(() => _category = value.first);
            if (_query.isNotEmpty) _doSearch(_query);
          },
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) _StateMessage(message: _error!, action: _trending),
        Expanded(
          child: ListView(children: [
            if (_category == 'People')
              for (final account in (_query.isNotEmpty ? _results : _people))
                _AccountRow(
                  account: account['account'] as Map<String, dynamic>? ?? account,
                  onTap: () => widget.onOpenProfile(
                      (account['account'] as Map<String, dynamic>?)?['acct'] as String? ??
                      account['acct'] as String? ?? ''),
                ),
            if (_category == 'Tags')
              for (final tag in _tags)
                ListTile(
                  leading: const Icon(Icons.tag),
                  title: Text(tag['name'] as String? ?? ''),
                  subtitle: Text('${tag['history']?.length ?? 0} ${t('posts')}'),
                  onTap: () {
                    final name = tag['name'] as String? ?? '';
                    _search.text = name;
                    _doSearch(name);
                  },
                ),
            if (_category == 'Posts')
              for (final status in _statuses)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _PostTile(
                    post: Post(status, _activeApi!.instance.host),
                    onProfile: widget.onOpenProfile,
                  ),
                ),
          ]),
        ),
      ]);
}

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});
  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  int _segment = 0;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Public hook for the top-bar refresh action.
  Future<void> refresh() => _load();

  Future<void> _load() async {
    if (_currentAccount == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _error = null);
    final key = 'notifications-${_currentAccountId ?? 'anon'}-$_segment';
    final cached = _appStore?.cachedStatuses(key);
    if (cached != null && cached.isNotEmpty) {
      setState(() {
        _items = cached;
        _loading = false;
      });
    }
    try {
      final types = switch (_segment) {
        1 => const ['mention'],
        2 => const ['favourite', 'reblog'],
        _ => null,
      };
      final items = await _activeApi!.notifications(types: types);
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
      _appStore?.cacheStatuses(key, items);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  Future<void> _dismiss(String id) async {
    setState(() => _items.removeWhere((item) => item['id'] == id));
    try {
      await _activeApi?.dismissNotification(id);
    } catch (_) {}
  }

  Future<void> _handleFollowRequest(String accountId, String notificationId, bool authorize) async {
    try {
      await _activeApi?.followRequestAuthorize(accountId, authorize: authorize);
      if (mounted) {
        setState(() => _items.removeWhere((item) => item['id'] == notificationId));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        if (_currentAccount != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text(t('All'))),
                ButtonSegment(value: 1, label: Text(t('Mentions'))),
                ButtonSegment(value: 2, label: Text(t('Likes / Reposts'))),
              ],
              selected: {_segment},
              onSelectionChanged: (value) {
                setState(() {
                  _segment = value.first;
                  _items = [];
                  _loading = true;
                });
                _load();
              },
            ),
          ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) _StateMessage(message: _error!, action: _load),
        Expanded(
          child: _currentAccount == null
              ? Center(child: FilledButton.tonalIcon(
                  onPressed: () {
                    final shell =
                        context.findAncestorStateOfType<_RumpunShellState>();
                    shell?._openAccount();
                  },
                  icon: const Icon(Icons.login),
                  label: Text(t('Log in to see notifications'))))
              : _items.isEmpty && !_loading
                  ? Center(child: Text(t('No notifications yet')))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(children: [
                        for (final item in _items)
                          _NotificationTile(
                            item: item,
                            onDismiss: () => _dismiss(item['id'] as String? ?? ''),
                            onAuthorize: (auth) {
                              final acct = item['account'] as Map<String, dynamic>? ?? {};
                              _handleFollowRequest(
                                acct['id'] as String? ?? '',
                                item['id'] as String? ?? '',
                                auth,
                              );
                            },
                          ),
                      ]),
                    ),
        ),
      ]);
}

/// Maps Mastodon notification types to readable text and action-specific icons.
class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, this.onDismiss, this.onAuthorize});
  final Map<String, dynamic> item;
  final VoidCallback? onDismiss;
  final ValueChanged<bool>? onAuthorize;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = item['account'] as Map<String, dynamic>? ?? {};
    final name = (account['display_name'] as String?)?.isNotEmpty == true
        ? account['display_name'] as String
        : account['username'] as String? ??
            account['acct'] as String? ??
            'Someone';
    final status = item['status'] as Map<String, dynamic>?;
    final type = item['type'] as String? ?? '';
    final (icon, color, text) = switch (type) {
      'follow' => (Icons.person_add, const Color(0xFF38A979), t('followed you')),
      'favourite' => (Icons.star, const Color(0xFFE0245E), t('liked your post')),
      'reblog' => (Icons.repeat, _green, t('boosted your post')),
      'mention' => (Icons.chat_bubble_outline, const Color(0xFF1D9BF0), t('mentioned you')),
      'poll' => (Icons.poll_outlined, theme.colorScheme.onSurface, t('poll ended')),
      'follow_request' => (Icons.person_add_alt_1_outlined, const Color(0xFFF59E0B), t('requested to follow you')),
      'status' => (Icons.notifications_none, theme.colorScheme.onSurface, t('posted')),
      _ => (Icons.notifications_none, theme.colorScheme.onSurface, type.isEmpty ? 'activity' : type),
    };
    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          _Avatar(account: account),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 14, color: color),
            ),
          ),
        ],
      ),
      title: Text.rich(TextSpan(children: [
        TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w600)),
        TextSpan(text: ' $text'),
      ])),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status != null)
            Text(_plainText(status['content'] as String? ?? ''),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          if (type == 'follow_request' && onAuthorize != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                FilledButton.tonal(
                  onPressed: () => onAuthorize!(true),
                  child: Text(t('Accept')),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => onAuthorize!(false),
                  child: Text(t('Reject')),
                ),
              ]),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status != null)
            Text(_relativeTime(status['created_at'] as String?),
                style: theme.textTheme.bodySmall),
          if (onDismiss != null)
            IconButton(
              tooltip: t('Dismiss'),
              icon: const Icon(Icons.close, size: 16),
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
            ),
        ],
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.account, this.accountId,
      required this.onOpenProfile});
  final Map<String, dynamic>? account;
  final String? accountId;
  final ValueChanged<String> onOpenProfile;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Map<String, dynamic>> _statuses = [];
  bool _loading = true;
  String? _error;
  /// Null until the relationship is known; the button is hidden until then.
  bool? _following;
  int _contentTab = 0;
  /// Tweets are the profile's own statuses — no separate page, no nav slot.
  String? get _cacheKey {
    final id = widget.account?['id'];
    return id is String ? 'tweets-$id-$_contentTab' : null;
  }
  bool _followPending = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account?['id'] != widget.account?['id']) {
      setState(() => _following = null);
      _load();
    }
  }

  /// Only shown for someone else's profile while signed in.
  Future<void> _loadRelationship(String accountId) async {
    if (_currentAccount == null || _currentAccountId == accountId) return;
    try {
      final rel = await _activeApi!.relationship(accountId);
      if (mounted) setState(() => _following = rel['following'] == true);
    } catch (_) {}
  }

  Future<void> _toggleFollow(String accountId) async {
    final next = !(_following ?? false);
    setState(() {
      _following = next;
      _followPending = true;
    });
    try {
      final result = await _activeApi!.follow(accountId, follow: next);
      if (mounted) {
        setState(() => _following =
            result['following'] == true || result['requested'] == true);
      }
    } catch (_) {
      if (mounted) setState(() => _following = !next);
    } finally {
      if (mounted) setState(() => _followPending = false);
    }
  }

  Future<void> _load() async {
    final account = widget.account;
    if (account == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _error = null);
    _loadRelationship(account['id'] as String);
    final key = _cacheKey;
    final cached = key == null ? null : _appStore?.cachedStatuses(key);
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() {
        _statuses = cached;
        _loading = false;
      });
    }
    try {
      final data = await _activeApi!.accountStatuses(
        account['id'] as String,
        excludeReplies: _contentTab == 0,
        onlyMedia: _contentTab == 2,
      );
      if (mounted) {
        setState(() {
          _statuses = data;
          _loading = false;
        });
      }
      if (_cacheKey != null) _appStore?.cacheStatuses(_cacheKey!, data);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    if (account == null) {
      return Center(child: Text(t('Choose Log in to connect an account.')));
    }
    final acct = account['acct'] as String? ?? '';
    final host = acct.contains('@') ? acct.split('@').last : _activeApi!.instance.host;
    final header = account['header'] as String? ?? '';
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          _ProfileBanner(header: header, account: account),
          const SizedBox(height: 54),
          Center(child: Text((account['display_name'] as String?)?.isNotEmpty == true ? account['display_name'] as String : account['username'] as String? ?? acct, style: Theme.of(context).textTheme.titleLarge)),
          Center(child: Text('@$acct')),
          if (_following != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: FilledButton.tonalIcon(
                  onPressed: _followPending
                      ? null
                      : () => _toggleFollow(account['id'] as String),
                  icon: Icon(_following! ? Icons.person_remove : Icons.person_add),
                  label: Text(_following! ? t('Unfollow') : t('Follow')),
                ),
              ),
            ),
          if (account['note'] is String && (account['note'] as String).isNotEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_plainText(account['note'] as String), textAlign: TextAlign.center)),
          Center(child: Wrap(spacing: 18, children: [
            Text('${account['statuses_count'] ?? 0} ${t('posts')}'),
            Text('${account['following_count'] ?? 0} ${t('following')}'),
            Text('${account['followers_count'] ?? 0} ${t('followers')}'),
          ])),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 0, label: Text(t('Posts'))),
              ButtonSegment(value: 1, label: Text(t('Replies'))),
              ButtonSegment(value: 2, label: Text(t('Media'))),
            ],
            selected: {_contentTab},
            onSelectionChanged: (value) {
              setState(() {
                _contentTab = value.first;
                _statuses = [];
                _loading = true;
              });
              _load();
            },
          ),
          if (widget.accountId != null)
            Align(alignment: Alignment.centerRight, child: TextButton.icon(
              onPressed: () => showModalBottomSheet<void>(context: context, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(leading: const Icon(Icons.tune), title: Text(t('Settings')), onTap: () {
                  final shell = context.findAncestorStateOfType<_RumpunShellState>();
                  Navigator.pop(context);
                  shell?._settings();
                }),
                ListTile(leading: const Icon(Icons.logout), title: Text(t('Log out')), onTap: () async { Navigator.pop(context); final shell = context.findAncestorStateOfType<_RumpunShellState>(); await shell?._logout(); }),
              ]))),
              icon: const Icon(Icons.more_horiz), label: Text(t('Account')))),
          const Divider(height: 28),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) _StateMessage(message: _error!, action: _load),
          if (_statuses.isEmpty && !_loading && _error == null)
            Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(t('No posts yet')))),
          for (final status in _statuses)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PostTile(post: Post(status, host), onProfile: widget.onOpenProfile),
            ),
        ]),
      ),
    ]);
  }

}

class _ProfileBanner extends StatelessWidget {
  const _ProfileBanner({required this.header, required this.account});
  final String header;
  final Map<String, dynamic> account;

  void _preview(BuildContext context, String url) {
    if (MediaQuery.sizeOf(context).width >= 760) {
      showDialog<void>(
        context: context,
        builder: (_) => Dialog.fullscreen(
            child: _MediaPreview(
                attachments: [
                  {'url': url, 'preview_url': url, 'type': 'image'}
                ],
                initialIndex: 0)),
      );
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _MediaPreview(
            attachments: [
              {'url': url, 'preview_url': url, 'type': 'image'}
            ],
            initialIndex: 0),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = (account['avatar_original'] as String?) ??
        account['avatar'] as String? ?? '';
    final hasHeader = header.isNotEmpty;
    return Stack(alignment: Alignment.bottomCenter, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 44),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 3,
            child: GestureDetector(
              onTap: hasHeader ? () => _preview(context, header) : null,
              child: hasHeader
                  ? Image(image: CachedNetworkImage(header, maxWidthPx: 1200),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _BannerFallback())
                  : const _BannerFallback(),
            ),
          ),
        ),
      ),
      GestureDetector(
        onTap: avatarUrl.isNotEmpty ? () => _preview(context, avatarUrl) : null,
        child: _Avatar(account: account, radius: 54),
      ),
    ]);
  }
}

class _BannerFallback extends StatelessWidget {
  const _BannerFallback();
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _green.withValues(alpha: 0.55),
              _green.withValues(alpha: 0.18),
            ],
          ),
        ),
      );
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account, required this.onTap});
  final Map<String, dynamic> account;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        leading: _Avatar(account: account),
        title: Text(account['display_name'] as String? ?? account['username'] as String? ?? ''),
        subtitle: Text('@${account['acct'] ?? ''}'),
        onTap: onTap,
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.account, this.radius = 20});
  final Map<String, dynamic> account;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final url = account['avatar'] as String? ?? '';
    if (url.isEmpty) {
      return CircleAvatar(
        radius: radius,
        child: Icon(Icons.person_outline, size: radius),
      );
    }
    // avatar_static is the smaller variant Mastodon serves for timelines.
    final small = (account['avatar_static'] as String?) ?? url;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final px = (radius * 2 * dpr).round();
    return CircleAvatar(
      radius: radius,
      backgroundImage: CachedNetworkImage(small, maxWidthPx: px, maxHeightPx: px),
      onBackgroundImageError: (_, __) {},
    );
  }
}

class _TimelineFilter extends StatelessWidget {
  const _TimelineFilter({required this.selected, required this.options, required this.onSelect});
  final int selected;
  final List<String> options;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final active = selected == i;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: active
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: active
                    ? scheme.primary.withValues(alpha: 0.35)
                    : scheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => onSelect(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: Text(
                    options[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: active
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Host without the noise most instances put in front of it.
String _displayHost(String host) => host.replaceFirst(RegExp(r'^www\.'), '');

class _StateMessage extends StatelessWidget {
  const _StateMessage({required this.message, required this.action});
  final String message;
  final VoidCallback action;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cleanMessage = message.replaceFirst(
        RegExp(r'^(Exception|FediverseException|Fediverse API error \(\d+\)):\s*'), '');
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 440),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.cloud_off_rounded,
                  size: 32,
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                t('Something went wrong'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                cleanMessage,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.tonalIcon(
                onPressed: action,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(t('Retry')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostTile extends StatefulWidget {
  const _PostTile({super.key, required this.post, required this.onProfile,
      this.onReply, this.onTap});
  final Post post;
  final ValueChanged<String> onProfile;
  /// Opens the composer pre-set to reply to this status.
  final ValueChanged<Map<String, dynamic>>? onReply;
  final VoidCallback? onTap;
  @override
  State<_PostTile> createState() => _PostTileState();
}

class _PostTileState extends State<_PostTile> {
  /// Local override for like/boost flags and counts so the tile reacts immediately.
  final _optimistic = <String, bool>{};
  final _countDeltas = <String, int>{};
  Post get post => widget.post;

  @override
  void didUpdateWidget(covariant _PostTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id) {
      _optimistic.clear();
      _countDeltas.clear();
    }
  }

  int? _count(String key, String flag) {
    final base = (post.data[key] as num?)?.toInt();
    final delta = _countDeltas[flag] ?? 0;
    return base == null && delta == 0 ? null : (base ?? 0) + delta;
  }

  @override
  Widget build(BuildContext context) {
    final attachments = post.data['media_attachments'] as List<dynamic>? ?? const [];
    final spoiler = post.data['spoiler_text'] as String? ?? '';
    final sensitive = post.data['sensitive'] == true;
    final favourited = _optimistic['favourited'] ?? post.data['favourited'] == true;
    final reblogged = _optimistic['reblogged'] ?? post.data['reblogged'] == true;
    final bookmarked = _optimistic['bookmarked'] ?? post.data['bookmarked'] == true;
    final repostedBy = post.repostedBy;
    final emojis = (post.data['emojis'] as List<dynamic>?) ?? const [];
    final theme = Theme.of(context);
    final signedIn = _currentAccount != null;
    final compact = _appStore?.boolSetting('compact_cards') ?? false;
    final alwaysShowSensitive =
        _appStore?.boolSetting('always_show_sensitive') ?? false;
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 10 : 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (repostedBy != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                const Icon(Icons.repeat, size: 15, color: _green),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '$repostedBy ${t('reposted')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ]),
            ),
          InkWell(
            onTap: () => widget.onProfile(post.acct),
            child: Row(children: [
              _Avatar(account: post.account, radius: 18),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(post.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (post.acct.contains('@'))
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('@${post.acct.split('@').first}', style: theme.textTheme.bodySmall),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        post.acct.split('@').last,
                        style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                      ),
                    ),
                  ])
                else
                  Text(post.handle, style: theme.textTheme.bodySmall),
              ])),
              Text(_relativeTime(post.data['created_at'] as String?), style: theme.textTheme.bodySmall),
            ]),
          ),
          const SizedBox(height: 12),
          if (spoiler.isNotEmpty)
            _Spoiler(content: post.content, warning: spoiler, emojis: emojis,
                onProfile: widget.onProfile, selectable: widget.onTap == null)
          else
            _HtmlText(html: post.content, emojis: emojis,
                onProfile: widget.onProfile, selectable: widget.onTap == null),
          if (attachments.isNotEmpty)
            _MediaGallery(attachments: [
              for (final attachment in attachments)
                if (attachment is Map<String, dynamic> && attachment['url'] != null)
                  attachment,
            ], sensitive: sensitive && spoiler.isEmpty && !alwaysShowSensitive),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              _ActionCount(
                  tooltip: t('Reply'),
                  onPressed: _handleReply,
                  icon: const Icon(Icons.mode_comment_outlined, size: 20),
                  count: (post.data['replies_count'] as num?)?.toInt()),
              _ActionCount(
                  tooltip: favourited ? t('Unlike') : t('Like'),
                  onPressed: signedIn ? () => _toggle('favourited', favourited, 'like', post.id) : null,
                  icon: Icon(favourited ? Icons.favorite : Icons.favorite_border,
                      size: 20, color: favourited ? const Color(0xFFE0245E) : null),
                  count: _count('favourites_count', 'favourited'),
                  highlighted: favourited),
              _ActionCount(
                  tooltip: reblogged ? t('Undo boost') : t('Boost'),
                  onPressed: signedIn ? () => _toggle('reblogged', reblogged, 'repost', post.id) : null,
                  icon: Icon(Icons.repeat, size: 20, color: reblogged ? _green : null),
                  count: _count('reblogs_count', 'reblogged'),
                  highlighted: reblogged),
              IconButton(
                  tooltip: bookmarked ? t('Remove bookmark') : t('Bookmark'),
                  visualDensity: VisualDensity.compact,
                  onPressed: signedIn
                      ? () => _toggle('bookmarked', bookmarked, 'bookmark', post.id)
                      : null,
                  icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border, size: 20)),
              const Spacer(),
              IconButton(
                  tooltip: t('Share'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _share(context, post),
                  icon: const Icon(Icons.ios_share, size: 20)),
            ]),
          ),
        ]),
        ),
      ),
    );
  }

  void _handleReply() {
    if (!signedInGate(context)) return;
    final onReply = widget.onReply;
    if (onReply != null) {
      onReply(post.data);
    } else {
      // The tile can live outside a thread (feeds, profiles); the reply goes
      // out the same way, just without the conversation around it.
      _openReply();
    }
  }

  Future<void> _openReply() async {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    if (wide) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: SingleChildScrollView(
              child: _ComposeSheet(replyTo: post.data, onPosted: () async {}),
            ),
          ),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ComposeSheet(replyTo: post.data, onPosted: () async {}),
    );
  }

  /// Flips the flag and count immediately, then reconciles or reverts on error.
  Future<void> _toggle(String flag, bool on, String action, String id) async {
    final prevDelta = _countDeltas[flag] ?? 0;
    setState(() {
      _optimistic[flag] = !on;
      _countDeltas[flag] = prevDelta + (on ? -1 : 1);
    });
    try {
      final result = await _activeApi!.action(id, on ? 'un$action' : action);
      if (mounted) setState(() => _optimistic[flag] = result[flag] == true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _optimistic[flag] = on;
        _countDeltas[flag] = prevDelta;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('Something went wrong'))));
    }
  }
}

/// Reply/like/boost need an account; offer to sign in instead of a dead button.
bool signedInGate(BuildContext context) {
  if (_currentAccount != null) return true;
  ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t('Log in to reply, like, and share'))));
  return false;
}

/// Icon button with a live count beside it, the shape every feed client uses
/// for reply/like/boost. Compact mode (count > 0 only) keeps the bar calm.
class _ActionCount extends StatelessWidget {
  const _ActionCount({required this.tooltip, required this.onPressed,
      required this.icon, required this.count, this.highlighted = false});
  final String tooltip;
  final VoidCallback? onPressed;
  final Widget icon;
  final int? count;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = count == null || count == 0 ? '' : _compactNumber(count!);
    return MergeSemantics(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            tooltip: label.isEmpty ? tooltip : '$tooltip · $label',
            onPressed: onPressed,
            icon: icon,
            visualDensity: VisualDensity.compact),
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(label,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: highlighted ? theme.colorScheme.primary : null)),
          ),
      ]),
    );
  }
}

String _compactNumber(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return '$value';
}

Future<void> _share(BuildContext context, Post post) async {
  final url = post.data['url'] as String? ?? '';
  final wide = MediaQuery.sizeOf(context).width >= 760;
  Widget buildItems(BuildContext ctx) => SafeArea(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(
        leading: const Icon(Icons.share),
        title: Text(t('Share to…')),
        onTap: () async {
          Navigator.pop(ctx);
          try {
            await SharePlus.instance.share(
                ShareParams(text: url, subject: 'Post by ${post.name}'));
          } catch (error) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not share: $error')));
            }
          }
        },
      ),
      ListTile(
        leading: const Icon(Icons.link),
        title: Text(t('Copy link')),
        onTap: () async {
          Navigator.pop(ctx);
          await Clipboard.setData(ClipboardData(text: url));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t('Link copied'))));
          }
        },
      ),
      ListTile(
        leading: const Icon(Icons.open_in_new),
        title: Text(t('Open in browser')),
        onTap: () {
          Navigator.pop(ctx);
          if (url.isNotEmpty) {
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          }
        },
      ),
    ]),
  );

  if (wide) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: buildItems(dialogContext),
        ),
      ),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => buildItems(sheetContext),
  );
}

class _Spoiler extends StatefulWidget {
  const _Spoiler({required this.content, required this.warning,
      this.emojis = const [], this.onProfile, this.selectable = false});
  final String content;
  final String warning;
  final List<dynamic> emojis;
  final ValueChanged<String>? onProfile;
  final bool selectable;
  @override
  State<_Spoiler> createState() => _SpoilerState();
}

class _SpoilerState extends State<_Spoiler> {
  late bool _show = _appStore?.boolSetting('always_show_sensitive') ?? false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.shield_outlined, size: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
          const SizedBox(width: 6),
          Flexible(child: Text(widget.warning,
              style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      ),
      TextButton.icon(
          onPressed: () => setState(() => _show = !_show),
          icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
          label: Text(_show ? t('Hide sensitive content') : t('Show sensitive content'))),
      if (_show)
        _HtmlText(html: widget.content, emojis: widget.emojis,
            onProfile: widget.onProfile, selectable: widget.selectable),
    ]);
  }
}

class _HtmlText extends StatefulWidget {
  const _HtmlText({required this.html, this.emojis = const [],
      this.onProfile, this.selectable = false});
  final String html;
  final List<dynamic> emojis;
  final ValueChanged<String>? onProfile;
  final bool selectable;
  @override
  State<_HtmlText> createState() => _HtmlTextState();
}

class _HtmlTextState extends State<_HtmlText> {
  final _recognizers = <TapGestureRecognizer>{};

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  Map<String, String> _buildEmojiMap() {
    final map = <String, String>{};
    for (final item in widget.emojis) {
      if (item is Map<String, dynamic>) {
        final code = item['shortcode'] as String?;
        final url = (item['static_url'] ?? item['url']) as String?;
        if (code != null && url != null) map[code] = url;
      }
    }
    for (final item in _serverCustomEmojis) {
      final code = item['shortcode'] as String?;
      final url = (item['static_url'] ?? item['url']) as String?;
      if (code != null && url != null) map.putIfAbsent(code, () => url);
    }
    return map;
  }

  List<InlineSpan> _parseSpans(String text, TextStyle? style, ValueChanged<String>? onProfile, Map<String, String> emojiMap) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    final spans = <InlineSpan>[];
    var start = 0;
    final combinedPattern = RegExp(r'(@[\w]+(?:@[\w\.\-]+)?)|(:[a-zA-Z0-9_]+:)');
    for (final match in combinedPattern.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start), style: style));
      }
      final matchedText = match[0]!;
      if (matchedText.startsWith('@') && onProfile != null) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => onProfile(matchedText.substring(1));
        _recognizers.add(recognizer);
        spans.add(TextSpan(
          text: matchedText,
          style: style?.copyWith(color: Theme.of(context).colorScheme.primary),
          recognizer: recognizer,
        ));
      } else if (matchedText.startsWith(':') && matchedText.endsWith(':')) {
        final code = matchedText.substring(1, matchedText.length - 1);
        final url = emojiMap[code];
        if (url != null) {
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Image(
                image: CachedNetworkImage(url, maxWidthPx: 48, maxHeightPx: 48),
                width: 18,
                height: 18,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Text(matchedText, style: style),
              ),
            ),
          ));
        } else {
          spans.add(TextSpan(text: matchedText, style: style));
        }
      } else {
        spans.add(TextSpan(text: matchedText, style: style));
      }
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: style));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final text = _plainText(widget.html);
    final theme = Theme.of(context);
    final emojiMap = _buildEmojiMap();
    final spans = _parseSpans(text, theme.textTheme.bodyMedium, widget.onProfile, emojiMap);
    final rich = Text.rich(TextSpan(style: theme.textTheme.bodyMedium, children: spans));
    return widget.selectable ? SelectionArea(child: rich) : rich;
  }
}

String _plainText(String html) => html
    .replaceAll(RegExp(r'<br\s*/?>|</p>|</div>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .trim();

String _relativeTime(String? value) {
  final date = DateTime.tryParse(value ?? '')?.toLocal();
  if (date == null) return '';
  final age = DateTime.now().difference(date);
  if (age.inDays > 0) return '${age.inDays}d';
  if (age.inHours > 0) return '${age.inHours}h';
  if (age.inMinutes > 0) return '${age.inMinutes}m';
  return 'now';
}

/// Inline gallery for a post's media. Single attachments render full-width;
/// multiple attachments use Material 3 [CarouselView].
class _MediaGallery extends StatelessWidget {
  const _MediaGallery({required this.attachments, this.sensitive = false});
  final List<Map<String, dynamic>> attachments;
  /// Server-flagged sensitive media with no CW text: blurred until tapped,
  /// unlike a CW which hides the whole post behind [_Spoiler].
  final bool sensitive;

  Widget _buildTile(BuildContext context, Map<String, dynamic> attachment,
      {required bool single}) =>
      Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Stack(fit: StackFit.expand, children: [
          if (_thumbnailUrl(attachment) case final thumb?)
            Image(
                image: CachedNetworkImage(thumb, maxWidthPx: 900),
                fit: single ? BoxFit.contain : BoxFit.cover,
                errorBuilder: (_, __, ___) => _mediaFallbackIcon(attachment))
          else
            Center(child: _mediaFallbackIcon(attachment)),
          if (attachment['type'] == 'video' || attachment['type'] == 'gifv')
            const Center(
              child: Icon(Icons.play_circle_fill,
                  color: Colors.white,
                  size: 44,
                  shadows: [Shadow(blurRadius: 8, color: Colors.black54)]),
            ),
          if (attachment['type'] == 'gifv')
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('GIF',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          if (sensitive) const _SensitiveScrim(),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    if (attachments.length == 1) {
      final attachment = attachments.first;
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: GestureDetector(
          onTap: () => _showPreview(context, attachments, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: _attachmentAspect(attachment),
              child: _buildTile(context, attachment, single: true),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        height: 190,
        child: CarouselView(
          itemExtent: 230,
          shrinkExtent: 150,
          padding: const EdgeInsets.only(right: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onTap: (index) => _showPreview(context, attachments, index),
          children: [
            for (final attachment in attachments)
              _buildTile(context, attachment, single: false),
          ],
        ),
      ),
    );
  }

  void _showPreview(BuildContext context,
      List<Map<String, dynamic>> attachments, int initialIndex) {
    if (MediaQuery.sizeOf(context).width >= 760) {
      showDialog<void>(
        context: context,
        builder: (_) => Dialog.fullscreen(
            child: _MediaPreview(attachments: attachments, initialIndex: initialIndex)),
      );
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _MediaPreview(attachments: attachments, initialIndex: initialIndex),
      ));
    }
  }
}

/// Blur scrim over server-flagged sensitive media. Tapping the tile still
/// opens the fullscreen view — the user opted in by tapping.
class _SensitiveScrim extends StatefulWidget {
  const _SensitiveScrim();
  @override
  State<_SensitiveScrim> createState() => _SensitiveScrimState();
}

class _SensitiveScrimState extends State<_SensitiveScrim> {
  bool _revealed = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_revealed) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => setState(() => _revealed = true),
      child: Stack(fit: StackFit.expand, children: [
        BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(color: theme.colorScheme.surface.withValues(alpha: 0.25))),
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.visibility_off_outlined, size: 26,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75)),
            const SizedBox(height: 6),
            Text(t('Sensitive content'),
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.75))),
            Text(t('Tap to show'),
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          ]),
        ),
      ]),
    );
  }
}

/// Fullscreen viewer: swipeable pages, alt text, and open-in-browser.
class _MediaPreview extends StatefulWidget {
  const _MediaPreview({required this.attachments, required this.initialIndex});
  final List<Map<String, dynamic>> attachments;
  final int initialIndex;
  @override
  State<_MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<_MediaPreview> {
  late int _index = widget.initialIndex;
  late final _pageController = PageController(initialPage: widget.initialIndex);
  bool _saving = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int next) {
    if (next < 0 || next >= widget.attachments.length) return;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _saveCurrentMedia() async {
    final url = (_current['url'] ?? _current['preview_url']) as String? ?? '';
    if (url.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      Directory? dir;
      try {
        dir = await getDownloadsDirectory();
      } catch (_) {}
      if (dir == null) {
        try {
          dir = await getApplicationDocumentsDirectory();
        } catch (_) {
          dir = Directory.systemTemp;
        }
      }
      final uri = Uri.parse(url);
      final rawName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'media.jpg';
      final safeName = rawName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final dest = File('${dir.path}/rumpun_$safeName');
      final saved = await CachedNetworkImage.saveTo(url, dest);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t('Saved to')} ${saved.path}')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t('Something went wrong')}: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.attachments.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: total > 1 ? Text('${_index + 1} / $total') : null,
        actions: [
          if (_altText.isNotEmpty)
            IconButton(
                icon: const Icon(Icons.closed_caption_outlined),
                tooltip: t('Description'),
                onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => AlertDialog(
                        title: Text(t('Description')),
                        content: Text(_altText),
                        actions: [TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(t('Close')))]))),
          IconButton(
              tooltip: t('Save image'),
              onPressed: _saving ? null : _saveCurrentMedia,
              icon: const Icon(Icons.download_outlined)),
          IconButton(
              tooltip: t('Open in browser'),
              onPressed: () => launchUrl(
                  Uri.parse(_current['url'] as String),
                  mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new)),
        ],
      ),
      body: GestureDetector(
        // Any tap that lands outside the media itself dismisses the preview;
        // taps on the image land on the child and are swallowed by it.
        onTap: () => Navigator.of(context).maybePop(),
        child: Container(
          color: Colors.transparent,
          child: Stack(fit: StackFit.expand, children: [
            total == 1
                ? _centered(_current)
                : PageView(
                    controller: _pageController,
                    onPageChanged: (i) => setState(() => _index = i),
                    children: [
                      for (final attachment in widget.attachments)
                        _centered(attachment),
                    ],
                  ),
            if (total > 1 && _index > 0)
              Positioned(
                left: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton.filledTonal(
                    onPressed: () => _goTo(_index - 1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                ),
              ),
            if (total > 1 && _index < total - 1)
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton.filledTonal(
                    onPressed: () => _goTo(_index + 1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Map<String, dynamic> get _current => widget.attachments[_index];

  String get _altText =>
      (_current['description'] as String? ?? '').trim();

  Widget _centered(Map<String, dynamic> attachment) {
    final type = attachment['type'] as String? ?? 'image';
    final src = attachment['url'] as String? ?? '';
    final preview = attachment['preview_url'] as String?;
    if ((type == 'video' || type == 'gifv' || type == 'audio') && src.isNotEmpty) {
      return Center(
        child: GestureDetector(
          onTap: () {},
          child: _VideoPlayerView(
            src: src,
            audioOnly: type == 'audio',
            loop: type == 'gifv',
            aspectRatio: _attachmentAspect(attachment),
            poster: preview,
          ),
        ),
      );
    }
    final primaryUrl = src.isNotEmpty ? src : (preview ?? '');
    return Center(
      child: GestureDetector(
        // Swallow taps on the media so only background taps close.
        onTap: () {},
        child: InteractiveViewer(
          maxScale: 4,
          child: Image(
            image: CachedNetworkImage(primaryUrl, maxWidthPx: 1600),
            fit: BoxFit.contain,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) return child;
              if (preview != null && preview.isNotEmpty && preview != primaryUrl) {
                return Image(
                  image: CachedNetworkImage(preview, maxWidthPx: 900),
                  fit: BoxFit.contain,
                );
              }
              return const Center(
                child: CircularProgressIndicator(color: Colors.white70),
              );
            },
            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined,
                color: Colors.white54, size: 48),
          ),
        ),
      ),
    );
  }
}

/// Single shared libmpv player per preview lifecycle.
class _VideoPlayerView extends StatefulWidget {
  const _VideoPlayerView({
    required this.src,
    this.audioOnly = false,
    this.loop = false,
    this.aspectRatio = 16 / 9,
    this.poster,
  });
  final String src;
  final bool audioOnly;
  final bool loop;
  final double aspectRatio;
  final String? poster;
  @override
  State<_VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<_VideoPlayerView> {
  late final _player = Player();
  late final _controller = VideoController(_player);
  @override
  void initState() {
    super.initState();
    _open();
  }

  /// Plays from the media cache when it fits; otherwise streams as before.
  Future<void> _open() async {
    final local = await CachedNetworkImage.cachedFile(widget.src);
    if (!mounted) return;
    if (widget.loop) {
      await _player.setPlaylistMode(PlaylistMode.single);
    }
    await _player.open(Media(local?.path ?? widget.src));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = Video(controller: _controller, controls: AdaptiveVideoControls);
    final themed = MaterialVideoControlsTheme(
      normal: _controlsTheme,
      fullscreen: _controlsTheme,
      child: video,
    );
    if (widget.audioOnly) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.audiotrack, size: 48, color: Colors.white54),
        const SizedBox(height: 8),
        SizedBox(width: 480, height: 120, child: themed),
      ]);
    }
    return AspectRatio(aspectRatio: widget.aspectRatio, child: themed);
  }

  static const _controlsTheme = MaterialVideoControlsThemeData(
      seekBarThumbColor: _green);
}

String? _thumbnailUrl(Map<String, dynamic> attachment) {
  final preview = attachment['preview_url'] as String?;
  if (preview != null && preview.isNotEmpty) return preview;
  final type = attachment['type'] as String? ?? 'image';
  if (type == 'image') {
    final url = attachment['url'] as String?;
    if (url != null && url.isNotEmpty) return url;
  }
  return null;
}

Widget _mediaFallbackIcon(Map<String, dynamic> attachment) => Icon(
    attachment['type'] == 'audio'
        ? Icons.audio_file_outlined
        : attachment['type'] == 'video' || attachment['type'] == 'gifv'
            ? Icons.videocam_outlined
            : Icons.image_outlined);

double _attachmentAspect(Map<String, dynamic> attachment) {
  final meta = attachment['meta'];
  if (meta is Map) {
    final orig = meta['original'];
    if (orig is Map) {
      final w = orig['width'];
      final h = orig['height'];
      if (w is num && h is num && h > 0) return (w / h).clamp(0.5, 3.0);
    }
    final small = meta['small'];
    if (small is Map) {
      final w = small['width'];
      final h = small['height'];
      if (w is num && h is num && h > 0) return (w / h).clamp(0.5, 3.0);
    }
  }
  return 16 / 9;
}
