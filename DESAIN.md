# Product Design & Specifications: Rumpun

**Rumpun** is a user-friendly Fediverse desktop client focused on Linux, built with Flutter. Its core philosophy: simplify decentralized interaction (Mastodon & ActivityPub) into a calm, beautiful, human-centered conversation platform without protocol jargon.

---

## 1. User Targets & Design Principles

### User Targets
1. **New Users:** No need to understand servers/nodes/instances before reading. Server guidance is presented with simple language (community, language, topics of interest).
2. **Modern Linux Users:** Native interface, memory-efficient, full keyboard shortcut support, dark/light mode synced with system preferences (GNOME/KDE).
3. **Experienced Fediverse Users:** Full control over Content Warnings (CW), 4 levels of post visibility, accessible alt-text for media, and multi-server switching.

### Design Principles
- **Zero-Jargon Interface:** No complex terms in the main UI. Use "Server" instead of "Instance", "Repost" instead of "Boost", "Spoiler" instead of "CW", and "Post" instead of "Toot".
- **App-Owned Modern Chrome:** Replace separate system status bar with an integrated app header (*owned chrome*) 46px tall, seamlessly blending with the canvas background.
- **Minimalist Cupertino Typography:** Use Apple SF Pro Text font family (`.SF Pro Text`) with tight tracking, calm hierarchy, and smooth fallback to native Linux fonts (Cantarell, Inter, Roboto).
- **Spatial Breadcrumb Navigation:** Adaptive navigation rail on desktop (width >= 760px) and bottom navigation bar on compact viewports (< 760px).
- **Safe & Intentional Publishing:** Visual warnings before sending posts that have images without alt-text or contain sensitive words without CW.

---

## 2. Application Screen Structure

The application has 4 main screens and 2 interactive modal sheets:

```
┌────────────────────────────────────────────────────────┐
│ [Hub] Rumpun          ● ruang.id              [Avatar] │ <- App-Owned Chrome
├──────┬─────────────────────────────────────────────────┤
│ [🏠] │ SCREEN 1: HOME (Timeline & Tabs)              │
│ [🔍] │ SCREEN 2: EXPLORE & SEARCH (Accounts, Hashtags, Posts)     │
│ [🔔] │ SCREEN 3: ACTIVITY (Mentions, Likes, Reposts)       │
│ [👤] │ SCREEN 4: PROFILE (Bio, My Posts, Followers)  │
└──────┴─────────────────────────────────────────────────┘
```

### 2.1 Home Screen (Timeline)
- **Timeline Filter Pills:** Tabs for *Following* (user's feed), *Local* (ruang.id server), and *Federated* (entire fediverse).
- **Compact Composer Card:** Quick button "What do you want to share?" that opens the full Compose modal.
- **Feed Cards:** Displays sender avatar, name, handle (same-instance handles show `@username` only; cross-instance handles show `@username` with a server chip/favicon to prove they are not from ruang.id), timestamp, CW badge if present, post text, and action bar (Reply, Like, Repost, Copy/Share).
- **Thread Interaction:** Tapping any card opens a detail conversation sheet (Thread Modal).

### 2.2 Explore & Search Screen
- **Modern Search Bar:** Unified search input for finding accounts (`@name@domain`), hashtags (`#topic`), or post content.
- **Category Pills:** Accounts, Hashtags, and Recent Posts.
- **Trending Hashtags List:** Displays popular local and global hashtags with conversation volume.

### 2.3 Activity / Notifications Screen
- **Filter Segments:** *All*, *Mentions*, and *Likes/Reposts*.
- **Notification Items:** Cards with action-specific icons (pink star for likes, green loop for reposts, blue conversation bubble for replies).

### 2.4 User Profile Screen
- **Profile Header:** Large avatar, full name, handle display (same-instance: `@username`; cross-instance: `@username` + server chip/favicon), server connection status, and stats (Following, Followers, Posts).
- **Biography:** Bio text with clickable federated links.
- **Content Tabs:** Posts, Replies, and Media.

### 2.5 Full Interactive Composer Modal
- **Post Input:** Spacious text area with dynamic character counter (500 character Fediverse default).
- **CW Toggle:** Text spoiler input that automatically hides post content in the timeline.
- **4-Level Visibility:**
  1. *Public* (Appears in all timelines and search).
  2. *Unlisted* (Visible to anyone but not in public timelines).
  3. *Followers Only* (Only approved accounts can read).
  4. *Direct Message* (Only mentioned accounts).
- **Media & Alt-Text:** Important reminder about image descriptions for accessibility.

### 2.6 Conversation Sheet (Thread Modal View)
- Displays hierarchical chain: parent post -> active post highlighted with green border -> threaded replies with vertical guide lines.

---

## 3. Design System & Visual Tokens

| Token | Light Mode Value | Dark Mode Value | Description |
|---|---|---|---|
| **Primary Accent** | `#236B55` (Forest Teal) | `#83C9AE` (Mint Sage) | Primary action buttons, active tabs |
| **Surface Canvas** | `#F7F8F6` (Warm Paper) | `#161918` (Deep Slate) | App background base |
| **Surface Card** | `#FFFFFF` | `#202422` | Feed cards & modal surfaces |
| **App Chrome** | `#FFFFFF` (96% opacity) | `#202422` (96% opacity) | Integrated header bar |
| **Divider / Border** | 10% alpha on text | 12% alpha on text | Thin separator lines |
| **Status Connection** | `#38A979` (Active Green) | `#38A979` (Active Green) | Fediverse server live indicator |
| **Text Primary** | `#1A201E` | `#EDF2EF` | Titles, readable content |
| **Text Secondary** | `#6B7470` | `#9AA4A0` | Handle, timestamp, placeholder |
| **Font Family** | `.SF Pro Text`, sans-serif | `.SF Pro Text`, sans-serif | Minimalist Cupertino typography |

---

## 4. Planned Tech Stack

- **Frontend Framework:** Flutter 3.x (Dart 3.x) targeting Linux Desktop (GTK3 runner / Flatpak).
- **State Management:** Riverpod (Notifier & AsyncNotifier pattern).
- **Protocol / API:** Mastodon REST API v1/v2 & WebSockets Streaming.
- **Secure Storage:** Linux Secret Service via DBus (`libsecret`) for OAuth tokens.
- **Local Storage:** SQLite / Drift for offline drafts & feed caching.

---

## 5. Acceptance Criteria
1. All four screens (Home, Search, Activity, Profile) are accessible and navigable.
2. Timeline filters (Following / Local / Federated) respond to taps.
3. The interactive composer displays Spoiler, Visibility, and Alt-Text options.
4. Thread modal can be opened to read deep conversations.
5. All workflows validated via automated `flutter test` suite.