# Galleryze ← Aves Migration Guide

> **Goal:** Fork Aves (production-grade Flutter gallery), rebrand it to Galleryze, then layer MobileCLIP semantic search on top.
> **Aves source:** https://github.com/deckerst/aves  
> **License:** BSD-3-Clause — forking is explicitly permitted with attribution.

---

## Is This Feasible?

**Yes.** Aves provides the entire gallery layer for free. The MobileCLIP pipeline from current Galleryze slots in cleanly as an additive feature. The biggest cost is understanding Aves' architecture well enough to hook into it correctly — not rewriting anything fundamental.

---

## Mental Model: What We Are Actually Doing

**The Galleryze codebase is split into two halves:**

| Half | Components | Fate in Aves migration |
|------|-----------|------------------------|
| **Gallery half** | `PhotoProvider`, `AlbumProvider`, `PhotoManagerService`, `PhotoItem`, `PhotoManagerImageProvider`, `PermissionsHandler`, all UI screens & widgets, `VideoPlayerScreen`, `SelectionAppBarActions`, `media_dialogs.dart` | **Thrown away entirely** — Aves replaces all of this, better |
| **ML + Cleanup half** | `MobileClipService`, `BpeTokenizer`, `TensorUtils`, `IndexingProvider`, `CleanupProvider` (DBSCAN), `SearchScreen` (rebuilt as `GalleryzeSearchPage`), `SmartCleanupScreen` (rebuilt as `SmartCleanupPage`), search history from `PreferenceService`, ONNX assets | **Ported into Aves** — these two features are the only code that migrates |

The guide is about adding the ML half into Aves. Everything else Galleryze ever did for gallery functionality is now Aves' problem to solve — and it already solved it.

---

## Overview of the Three Phases

| Phase | Goal | Realistic Effort |
|-------|------|--------|
| **1. Fork & Rename** | Working Aves build under `com.galleryze.app` package | 1–2 days |
| **2. UI Reskin** | Bottom nav structure, home layout, Galleryze typography | 2–4 days |
| **3. MobileCLIP Search + Smart Cleanup** | Semantic search + DBSCAN duplicate cleanup ported into Aves | 8–12 days |

> Phase 3 is longer than it first appears — see the detailed breakdown below.

---

## Known Challenges Summary

These are the non-obvious problems the guide addresses in detail:

| # | Challenge | Severity | Section |
|---|-----------|----------|---------|
| A | `IndexingProvider` needs full adaptation — type, source, and storage all change | High | 3.2 |
| B | `PhotoProvider`'s embedding half doesn't exist in Aves — must create `EmbeddingProvider` | High | 3.3 |
| C | `semanticSearch()` needs a new home in Aves' architecture | High | 3.4 |
| D | `AvesEntry.id` is `int`; embeddings.bin stores `String` keys — must use `.toString()` consistently | High | 3.6 |
| E | Aves nav tabs are **data-driven from SharedPrefs**, not hardcoded — wrong mechanism in old guide | High | 3.9 |
| F | Galleryze favorites (in `photo_metadata.json`) must be migrated to Aves' SQLite `Favourites` | High | 3.10 |
| G | Provider injected in `lib/widgets/aves_app.dart`, NOT `main_common.dart` | Medium | 3.3 |
| H | `CollectionSource` is NOT a `ChangeNotifier` — must not use it like one | Medium | 3.2 |
| I | `search_history` SharedPrefs key **confirmed collision** with Aves — must prefix all keys | Medium | 3.5 |
| J | `google-services.json` / `agconnect-services.json` are Aves-specific — must be replaced | Medium | 1.9 |
| K | `minSdk` is **definitively 21** in Aves (`flutter.minSdkVersion`); ORT requires 24 | Medium | 3.8 |
| L | JVM toolchain is **21** in Aves vs **17** in Galleryze — must keep 21, verify ORT compat | Medium | 3.8 |
| M | `flutter_onnxruntime` correct version is `1.6.3`, not `1.22.0` | Medium | 3.7 |
| N | Plugin Kotlin source uses `deckerst` path prefix — verify before bulk rename | Low | 1.4b |
| O | `AvesEntry.isVideo` is an **extension getter** — needs correct import from `props.dart` | Low | 3.2 |
| P | `MlThumbnailChannel` handles images only — skip video entries explicitly | Low | 3.1 |

---

## Phase 1: Fork & Rename (Detailed)

> **AI focus for this phase:** Your only job is to get a buildable Galleryze app from the Aves fork — correct package ID, correct app name, correct icon, no Firebase/Huawei keys. Do not touch any ML code, providers, or UI logic. Stop after §1.11 and wait for the user to test.

### 1.1 — Fork on GitHub

1. Go to https://github.com/deckerst/aves
2. Click **Fork → Create fork**
3. Rename the fork repo to `GlrzApp` on GitHub Settings
4. Clone **your fork** locally and pin to a stable release tag:
   ```bash
   git clone https://github.com/YOUR_USERNAME/GlrzApp.git GlrzApp_aves
   cd GlrzApp_aves

   # Aves uses 'develop' as its active branch — the tip may have in-progress
   # breaking changes. Pin to the latest release tag instead.
   git fetch --tags
   git tag --sort=-v:refname | head -5   # see available release tags

   # Checkout the latest stable tag and create your working branch from it:
   git checkout v1.x.x                   # replace with the actual latest tag
   git checkout -b galleryze-main
   ```
   > **Why a tag, not `develop`?** Aves' `develop` branch is where active work happens and internal APIs shift between releases. A release tag is a stable, tested snapshot — safe to build on. To get upstream bug fixes later, cherry-pick specific commits or bump to a newer tag on your `galleryze-main` branch.

5. **Remove the `.flutter` submodule immediately** (Aves pins its own Flutter version — use your system Flutter instead):
   ```bash
   git submodule deinit -f .flutter
   git rm -f .flutter
   rm -rf .git/modules/.flutter
   git commit -m "remove flutter submodule, use system flutter"
   ```

6. Delete the `flutterw` wrapper script:
   ```bash
   rm flutterw
   git add -A && git commit -m "remove flutterw wrapper"
   ```

7. Add upstream remote for future Aves bug-fix pulls:
   ```bash
   git remote add upstream https://github.com/deckerst/aves.git
   ```

> From this point on, use your normal `flutter` command — same as any plain Flutter project.

---

### 1.2 — Understand the Repo Layout

```
GlrzApp_aves/
├── lib/                        # Dart app code
│   ├── main_play.dart          # Entry point — Google Play flavor
│   ├── main_libre.dart         # Entry point — F-Droid flavor
│   ├── main_izzy.dart          # Entry point — IzzyOnDroid flavor
│   ├── main_common.dart        # Shared app bootstrap (initializes plugins)
│   ├── model/                  # Data models (AvesEntry / MediaItem, Album, etc.)
│   ├── services/               # Business logic
│   ├── view/                   # Screens / pages
│   ├── widgets/                # Reusable UI components
│   ├── theme/                  # App theme / colors
│   └── l10n/                   # Localization ARB files
├── plugins/                    # 15 internal Flutter plugins
│   ├── aves_model/             # Core data model (AvesEntry, MediaItem)
│   ├── aves_services/          # Core native services (MediaStore, albums, delete)
│   ├── aves_ui/                # UI helpers
│   ├── aves_video/             # Video player abstraction
│   ├── aves_video_exo/         # ExoPlayer implementation
│   ├── aves_video_mpv/         # MPV implementation (optional)
│   ├── aves_magnifier/         # Pinch-zoom viewer
│   ├── aves_map/               # Map/GPS integration
│   ├── aves_report/            # Crash reporting abstraction
│   ├── aves_report_console/    # Console crash reporter
│   ├── aves_report_crashlytics/# Firebase Crashlytics reporter
│   ├── aves_services_google/   # Google Play services
│   ├── aves_services_none/     # No-op services fallback
│   ├── aves_screen_state/      # Screen on/off detection
│   └── aves_utils/             # Kotlin/Java utilities
├── android/
│   └── app/
│       ├── build.gradle.kts    # applicationId = "deckers.thibault.aves"
│       ├── google-services.json        # ← Must replace (challenge F)
│       ├── agconnect-services.json     # ← Must replace or remove (challenge F)
│       └── src/
│           ├── main/
│           │   ├── AndroidManifest.xml
│           │   ├── kotlin/deckers/thibault/aves/   # Main app Kotlin source
│           │   └── res/
│           └── libre/res/values/strings.xml
└── pubspec.yaml                # name: aves
```

**Key identifiers to replace globally:**

| Find | Replace With | Where |
|------|-------------|-------|
| `deckers.thibault.aves` | `com.galleryze.app` | build.gradle.kts, AndroidManifest, Kotlin `package` & `import` declarations |
| `deckers/thibault/aves` | `com/galleryze/app` | Directory paths in `android/app/src/main/kotlin/` |
| `package:aves/` | `package:galleryze/` | All `.dart` imports in `lib/` and `plugins/` |
| `name: aves` | `name: galleryze` | `pubspec.yaml` only |
| App label `"Aves"` | `"Galleryze"` | `res/values/strings.xml` + flavor variants |

---

### 1.3 — Simplify Flavors

Aves has 4 store flavors: `play`, `izzy`, `libre`, `libre_rom`. Keep only `play`.

**a.** In `android/app/build.gradle.kts`, delete `izzy`, `libre`, `libre_rom` blocks:
```kotlin
productFlavors {
    create("play") {
        dimension = "store"
    }
}
```

**b.** Delete flavor source directories:
```bash
rm -rf android/app/src/libre android/app/src/libreDebug android/app/src/libreProfile
```

**c.** Delete unused entry points:
```bash
rm lib/main_libre.dart lib/main_izzy.dart
# Keep: lib/main_play.dart → rename to lib/main.dart
```

---

### 1.4 — Rename the Android Package

**a. Rename Kotlin source directory (main app only):**
```bash
mkdir -p android/app/src/main/kotlin/com/galleryze/app
cp -r android/app/src/main/kotlin/deckers/thibault/aves/. \
      android/app/src/main/kotlin/com/galleryze/app/
rm -rf android/app/src/main/kotlin/deckers
```

**b. Update `package`/`import` declarations in ALL Kotlin and Java files.**

> **Important:** This covers the main app AND the test directory. The plugins' own Kotlin source files live under `plugins/<name>/android/src/main/kotlin/` and use their own namespaces (e.g. `deckers.thibault.aves_model`). We keep plugin names as `aves_*` so they do NOT need renaming. However, if any plugin Kotlin file `import`s or cross-references the main app package `deckers.thibault.aves` (without an `_` suffix), those lines need updating.

> **Note (Challenge N):** Research shows plugin Kotlin source paths may use `deckerst` (not `deckers`) as the directory name — e.g. `kotlin/deckerst/thibault/aves/`. Verify the actual directory names after cloning before running bulk renames. Use `find plugins -type d -name "aves"` to confirm.

```bash
# Main app + tests
find android -name "*.kt" -exec sed -i 's/deckers\.thibault\.aves/com.galleryze.app/g' {} +
find android -name "*.java" -exec sed -i 's/deckers\.thibault\.aves/com.galleryze.app/g' {} +

# Check if any plugin Kotlin file cross-references the main app package (not plugin packages)
# The regex [^_] excludes matches like "deckers.thibault.aves_model" (those are fine)
grep -r "deckers\.thibault\.aves[^_]" plugins/ --include="*.kt" --include="*.java"
# If hits appear, apply the same sed to those specific files
```

**c. Update `build.gradle.kts`:**
```kotlin
applicationId = "com.galleryze.app"
namespace = "com.galleryze.app"
```

**d. Update `AndroidManifest.xml`:**
```bash
sed -i 's/deckers\.thibault\.aves/com.galleryze.app/g' android/app/src/main/AndroidManifest.xml
```
Key places this fixes: `android:authorities` on ContentProviders, `android:name` with full package paths, FileProvider authorities.

---

### 1.5 — Rename in Dart / pubspec

> **⚠️ Longevity decision — read before proceeding.**
>
> Renaming `name: aves` → `name: galleryze` in `pubspec.yaml` changes every internal import from `package:aves/` to `package:galleryze/`. This affects ~600 import lines across `lib/` and all 15 `plugins/`. Every time you pull an Aves upstream update, new or modified files will contain `package:aves/` imports — you must re-apply the rename manually to every changed file. This is a permanent maintenance tax.
>
> **Recommended alternative (lower maintenance):** Keep `name: aves` in `pubspec.yaml`. Only rename the Android `applicationId`, display name, and Kotlin package. The Galleryze-specific code in `lib/galleryze/` uses relative imports and is unaffected. Aves upstream merges then apply cleanly to all plugin and lib code with zero import conflicts.
>
> The downside: internal imports still say `package:aves/` — confusing for the team but functionally identical.
>
> **If you choose the full rename** (cleaner for the team), do:

**a.** `pubspec.yaml`:
```yaml
name: galleryze   # was: aves
```

**b.** All Dart import statements in `lib/` and `plugins/`:
```bash
find lib -name "*.dart" -exec sed -i "s/package:aves\//package:galleryze\//g" {} +
find plugins -name "*.dart" -exec sed -i "s/package:aves\//package:galleryze\//g" {} +
```

**If you choose the minimal rename** (lower maintenance), skip step (a) and (b) entirely. `name:` stays `aves`, internal imports stay `package:aves/`. Only `applicationId`, `strings.xml`, and `android/` Kotlin package change.

> The internal `aves_*` plugin names in `pubspec.yaml` path dependencies do NOT need renaming either way.

---

### 1.6 — Rename App Display Name

**a.** `android/app/src/main/res/values/strings.xml`:
```xml
<string name="app_name">Galleryze</string>
```

**b.** Check all flavor overrides:
```bash
find android/app/src -name "strings.xml" -exec grep -l "Aves" {} \;
```

**c.** `lib/l10n/` ARB files — search and replace app name occurrences:
```bash
grep -rl '"Aves"' lib/l10n/ | xargs sed -i 's/"Aves"/"Galleryze"/g'
```

---

### 1.7 — Replace App Icon

Icon locations:
```
android/app/src/main/res/mipmap-{hdpi,mdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png
android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml  (adaptive icon)
```

Use `flutter_launcher_icons` package or drop in PNG files manually.

---

### 1.8 — Remove Unwanted Plugins

| Plugin | Feature | Recommendation |
|--------|---------|----------------|
| `aves_video_mpv` | MPV player | Remove — keep `aves_video_exo` (ExoPlayer) |
| `aves_map` | GPS map view | Keep or remove — your choice |
| `aves_report_crashlytics` | Firebase Crashlytics | Remove unless you set up Firebase |
| `aves_services_google` | Google Play services | Keep if targeting Play Store |

To remove a plugin: delete `plugins/aves_X/`, remove from `pubspec.yaml`, remove from `lib/main_common.dart`.

---

### 1.9 — Replace Firebase / Huawei Config Files (Challenge F)

Aves has its own Firebase and Huawei AppGallery accounts baked into two files:

- `android/app/google-services.json` — Firebase config
- `android/app/agconnect-services.json` — Huawei AGC config

**If you're NOT using Firebase Crashlytics** (after removing `aves_report_crashlytics`):
```bash
rm android/app/google-services.json
rm android/app/agconnect-services.json
```
Also remove the `google-services` Gradle plugin from `android/build.gradle` or `android/app/build.gradle.kts`.

**If you plan to use Firebase** (for crash reporting): create a new Firebase project, register `com.galleryze.app`, download the new `google-services.json`, replace the existing file.

> Leaving Aves' original `google-services.json` in place will either fail the build (if the package ID no longer matches) or silently report crashes to Aves' Firebase project — both bad.

---

### 1.10 — First Build Verification

```bash
flutter clean && flutter pub get
flutter build apk --debug --flavor play -t lib/main.dart
flutter run --flavor play -t lib/main.dart
```

**Common first-build issues:**

| Error | Fix |
|-------|-----|
| `package:aves/` not found | Missed some import — `grep -r "package:aves" lib/` |
| Kotlin: unresolved reference | Old package declaration remains — check step 1.4b |
| Manifest merger failed | Authority conflict in AndroidManifest — check step 1.4d |
| `google-services.json` package mismatch | Replace or remove per step 1.9 |
| Missing flavor | Ensure `-t lib/main.dart --flavor play` flags are set |

---

### 1.11 — Phase 1 Checklist

- [ ] Forked and cloned (plain `git clone`)
- [ ] Removed `.flutter` submodule and `flutterw`
- [ ] Deleted unused flavors (`libre`, `izzy`, `libre_rom`)
- [ ] Renamed Kotlin directory: `deckers/thibault/aves` → `com/galleryze/app`
- [ ] Updated `package`/`import` in all `.kt`/`.java` (main app + verified plugins clean)
- [ ] Updated `applicationId` and `namespace` in `build.gradle.kts`
- [ ] Updated `AndroidManifest.xml` (package, authority, provider names)
- [ ] Updated `pubspec.yaml` name: `aves` → `galleryze`
- [ ] Updated all `package:aves/` imports in `lib/` and `plugins/`
- [ ] Updated app label in `strings.xml` to `Galleryze`
- [ ] Updated app name in `l10n` ARB files
- [ ] Replaced `google-services.json` / `agconnect-services.json`
- [ ] Replaced app icon
- [ ] First build passes: `flutter build apk --debug --flavor play`
- [ ] App launches on device, media loads correctly

---

### ✅ Test Checkpoint 1 — Fork & Rename Complete

```bash
flutter run --flavor play
```

Verify on device:
- [ ] App installs and launches without crashing
- [ ] App name shown as **Galleryze** (not "Aves") in the launcher and title bar
- [ ] App icon is the Galleryze icon (not the Aves bird)
- [ ] Photos from the device gallery load in the grid
- [ ] Package ID in Android settings is `com.galleryze.app`

If build fails with `Manifest merger failed`: re-check §1.4d — authority strings in `AndroidManifest.xml` must all use the new package ID.  
If app crashes on launch: check logcat for `ClassNotFoundException` — a Kotlin class was likely missed during the package rename (§1.4b).

---

## Phase 2: UI Reskin (Summary)

> **AI focus for this phase:** Your only job is cosmetic — update colors, grid density, bottom nav labels, and app name strings so the app feels like Galleryze. Do not add any new providers, screens, or ML code. Stop at the end of Phase 2 and wait for the user to test.

> Full detail will be added when Phase 1 is complete.

**Goal:** Tweak Aves' UI to feel like Galleryze — bottom nav structure, home screen grid density, typography.

**Aves already provides:** Material You, light/dark mode, dynamic color — no work needed for those.

**Key files:**
- `lib/theme/` — colors, text styles, spacing
- `lib/view/home/` — home screen layout, grid tile size
- `lib/widgets/` — bottom navigation, app bar actions
- `android/app/src/main/res/values/styles.xml` — splash, window background

**Estimated scope:** 5–15 files, cosmetic only.

---

### ✅ Test Checkpoint 2 — UI Reskin Complete

```bash
flutter run --flavor play
```

Verify on device:
- [ ] App colors match the Galleryze palette (not Aves' default teal/green)
- [ ] Bottom navigation labels/tabs match the intended Galleryze layout
- [ ] Home screen grid density is correct
- [ ] No "Aves" branding visible anywhere (app bar, about screen, strings)
- [ ] Light and dark mode both look correct

If any string still shows "Aves": search `lib/` and `android/` for the literal string `"Aves"` and update. ARB localization files (`lib/l10n/`) are the most common missed location.

---

## Phase 3: MobileCLIP Semantic Search + Smart Cleanup

> **AI focus for this phase:** Add exactly two features — semantic search and smart cleanup — on top of a working Aves gallery. Work through sections §3.1–§3.13 in order. Each section has a clearly bounded task. Stop at each test checkpoint and wait for the user to confirm before proceeding to the next section.

> This phase adds the two Galleryze-specific features on top of Aves' gallery. Read this section fully before starting.

---

### The Aves/Galleryze Boundary — Non-Negotiable Rule

> **Aves owns ALL gallery functionality. Galleryze adds exactly two features: semantic search and smart cleanup.**

| Concern | Owner | Code location |
|---------|-------|---------------|
| Photo grid (home screen) | **Aves** | `CollectionPage` |
| Albums, folders | **Aves** | `AlbumListPage` |
| Photo viewer (full-screen, swipe, zoom) | **Aves** | Aves' entry viewer |
| Favorites | **Aves** | `Favourites` SQLite |
| Delete, share, edit, metadata | **Aves** | `StorageService`, `EntryActions` |
| Permissions | **Aves** | Aves' `PermissionsPage` |
| Thumbnail display | **Aves** | `ThumbnailProvider` |
| Video playback | **Aves** | `aves_video_exo` ExoPlayer |
| Navigation tabs and routing | **Aves** | `AvesNavItem`, Aves router |
| Sort, filter, search by date/location | **Aves** | Aves' collection filters |
| ━━━━━━━━━━━━━━━━━━━━━━━━━ | ━━━━━━━━━━━━━━ | ━━━━━━━━━━━━━━━━━━━━━━━━ |
| ONNX model loading + inference | **Galleryze** | `MobileClipService` |
| ML thumbnail bytes (for ONNX only) | **Galleryze** | `MlThumbnailChannel` |
| Image embedding (indexing) | **Galleryze** | `IndexingProvider` |
| Embedding storage on disk | **Galleryze** | `EmbeddingProvider` |
| Text encoding + semantic search | **Galleryze** | `EmbeddingProvider.semanticSearch()` |
| Search UI + history | **Galleryze** | `GalleryzeSearchPage` |
| DBSCAN duplicate detection | **Galleryze** | `CleanupProvider` |
| Smart cleanup UI (review + delete dupes) | **Galleryze** | `SmartCleanupPage` (uses Aves APIs for display/delete) |

**If you find yourself writing Dart code that fetches photos, browses albums, handles permissions, renders a gallery grid, sorts by date, or plays video — STOP. That is Aves' job.**

**Within Galleryze's own screens** (`GalleryzeSearchPage`, `SmartCleanupPage`), all *display* primitives must still use Aves:
- Thumbnails → `ThumbnailProvider` (never `photo_manager`)
- Open photo → Aves' entry viewer (never a custom viewer)
- Delete → `StorageService` (never `photo_manager`'s delete)

The `MlThumbnailChannel` is the one deliberate exception to the Aves thumbnail rule: it fetches raw JPEG bytes via `ContentResolver.loadThumbnail()` exclusively for ONNX inference. It is never used for display.

---

### What Actually Migrates (Corrected)

Most of Galleryze's code is **thrown away** — Aves replaces it entirely. Only the ML pipeline migrates.

**Thrown away (Aves handles this):**
- `PhotoProvider`, `AlbumProvider`, `PhotoManagerService` — Aves has `CollectionSource`, `AvesEntry`
- `PhotoItem` model — Aves has `AvesEntry`
- `PhotoManagerImageProvider`, `AssetEntityImageProvider` — Aves has `ThumbnailProvider`
- `PermissionsHandler` — Aves has its own permission system
- `FavoriteProvider` — dead code; Aves has `Favourites` SQLite
- `PhotoGrid`, `PhotoTile`, `PhotoViewScreen`, `HomeScreen`, `CategoriesScreen`, `AlbumsScreen`, `FavoritesScreen` — Aves has all of these, better
- `VideoPlayerScreen` — Aves has ExoPlayer-based video, better
- `MainScreen` (3-tab nav) — Aves has its own nav; we extend it
- `SelectionAppBarActions` — Aves has its own selection system
- `media_dialogs.dart` — Aves has `StorageService` for delete
- `AlbumFolder` model, `PhotoGrid`, `PhotoTile`, `ScrollbarIndicator`, `SortDropdown`, `MediaTypeFilter` — all replaced by Aves UI
- `MediaViewerChrome`, `FullImageView`, `ImageEditScreen` — Aves viewer handles all of this
- `VideoUtils`, `ColorFilters`, `MediaUtils`, `MediaTypes` — replaced by Aves equivalents
- `AlbumProvider` — Aves has `AlbumListPage` and `CollectionSource` for albums
- `app.dart` / `GalleryzeApp` — replaced by Aves' `aves_app.dart`
- `main.dart` (Galleryze's) — replaced by Aves' `main_play.dart`

**Migrated from Galleryze → Aves:**

| Component | File | Changes needed |
|-----------|------|----------------|
| `MobileClipService` | `lib/services/mobile_clip_service.dart` | **None — copy as-is** |
| `BpeTokenizer` | `lib/utils/bpe_tokenizer.dart` | None — copy as-is |
| `TensorUtils` | `lib/utils/tensor_utils.dart` | None — copy as-is |
| ONNX assets + vocab | `assets/*.onnx`, `assets/vocab.json`, `assets/merges.txt` | Copy to Aves `assets/` |
| `IndexingProvider` | `lib/providers/indexing_provider.dart` | **Significant adaptation** — see §3.2 |
| `CleanupProvider` (DBSCAN) | `lib/providers/cleanup_provider.dart` | Minor — see §3.2 |
| `PreferenceService` (partial) | `lib/services/preference_service.dart` | Keep ONLY `saveSearchHistory` / `loadSearchHistory` — everything else (sort, favorites) is replaced by Aves — see §3.5 |
| `SearchScreen` | `lib/screens/search_screen.dart` | Rebuild in Aves style — see §3.10 |
| `GlassProgressPopup` | `lib/widgets/ui_kit.dart` (extract this widget) | None — copy as-is to `lib/galleryze/widgets/glass_progress_popup.dart`; zero `photo_manager` refs |
| `StringUtils` (`normalizeId`, `calculateSimilarity`) | `lib/utils/string_utils.dart` | None — copy as-is; needed for search history fuzzy dedup |
| **New: `EmbeddingProvider`** | (new file) | **Must create** — see §3.3 |

---

### 3.1 — Thumbnail Bytes: The New Platform Channel

`MobileClipService.encodeImage()` takes a plain `Uint8List` — zero changes needed. The only thing that changes is how those bytes are fetched.

**Add a new Kotlin class** `android/app/src/main/kotlin/com/galleryze/app/MlThumbnailChannel.kt`:

```kotlin
package com.galleryze.app

import android.content.ContentUris
import android.graphics.Bitmap
import android.os.Build
import android.provider.MediaStore
import android.util.Size
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

// Register in MainActivity.configureFlutterEngine():
//   MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.galleryze.app/ml_thumbnail")
//       .setMethodCallHandler(MlThumbnailChannel(this))

class MlThumbnailChannel(private val context: android.content.Context)
    : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodChannel.MethodCall, result: MethodChannel.Result) {
        if (call.method != "fetchThumbnail") {
            result.notImplemented(); return
        }
        // id is the integer MediaStore row ID (Long stored as String in AvesEntry)
        val id = call.argument<String>("id")?.toLongOrNull()
        if (id == null) { result.error("BAD_ARG", "id required", null); return }

        // Only call for images — skip video entries (MobileCLIP is image-only)
        val mimeType = call.argument<String>("mimeType") ?: ""
        if (!mimeType.startsWith("image/")) {
            result.success(null); return
        }

        try {
            val uri = ContentUris.withAppendedId(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id
            )
            val bitmap: Bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Android 10+: uses OS thumbnail cache — fast
                context.contentResolver.loadThumbnail(uri, Size(256, 256), null)
            } else {
                // Android 7–9 fallback
                @Suppress("DEPRECATION")
                MediaStore.Images.Thumbnails.getThumbnail(
                    context.contentResolver, id,
                    MediaStore.Images.Thumbnails.MINI_KIND, null
                ) ?: throw Exception("Thumbnail unavailable for id=$id")
            }
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, 85, stream)
            bitmap.recycle()
            result.success(stream.toByteArray())
        } catch (e: Exception) {
            result.error("THUMB_ERROR", e.message, null)
        }
    }
}
```

**New Dart wrapper** `lib/services/ml_thumbnail_service.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter/services.dart';

class MlThumbnailService {
  static const _channel = MethodChannel('com.galleryze.app/ml_thumbnail');

  /// Returns compressed JPEG bytes (≤256×256) for image entries.
  /// Returns null for videos, deleted media, or errors.
  static Future<Uint8List?> fetchThumbnail(String id, String mimeType) async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List?>(
        'fetchThumbnail', {'id': id, 'mimeType': mimeType},
      );
      return bytes;
    } catch (_) {
      return null;
    }
  }
}
```

**Registering `MlThumbnailChannel` in `MainActivity.kt`:**

Aves' `MainActivity` registers ~25 channels manually in `configureFlutterEngine()`. Add one more at the end of that method:

```kotlin
// android/app/src/main/kotlin/com/galleryze/app/MainActivity.kt
// Inside configureFlutterEngine(), after all existing MethodChannel lines:

MethodChannel(messenger, "com.galleryze.app/ml_thumbnail")
    .setMethodCallHandler(MlThumbnailChannel(this))
```

`messenger` is already declared at the top of `configureFlutterEngine()` as `val messenger = flutterEngine.dartExecutor`. No other changes to `MainActivity.kt`.

---

### 3.2 — IndexingProvider: Full Adaptation Required (Challenges A, H, O)

**What changes — full scope:**

| Step | Current (Galleryze) | New (Aves) |
|------|---------------------|------------|
| 1. Get media list | `PhotoProvider._photos` — `List<AssetEntity>` | `CollectionSource.visibleEntries` — `Set<AvesEntry>` |
| 2. Filter unindexed | `embIndex.containsKey(asset.id)` | `embeddingProvider.hasEmbedding(entry.id.toString())` |
| 3. Skip videos | `asset.type != AssetType.video` | `!entry.isVideo` (extension getter — needs `props.dart` import) |
| 4. Get thumbnail | `asset.thumbnailDataWithSize(256,256)` with 3-size retry [256,128,64] | `MlThumbnailService.fetchThumbnail(entry.id.toString(), entry.mimeType)` — reproduce the retry logic (see note below) |
| 5. Encode | `mobileClipService.encodeImage(bytes)` | **unchanged** |
| 6. Store | `PhotoProvider.setEmbedding(id, vec)` | `embeddingProvider.setEmbedding(entry.id.toString(), vec)` |
| 7. Flush | `PhotoProvider.flushEmbeddings()` | `embeddingProvider.flushEmbeddings()` |

**Critical: `CollectionSource` is NOT a ChangeNotifier (Challenge H)**

`CollectionSource` uses `ValueNotifier` + EventBus internally. It is provided as a plain `Provider<CollectionSource>` (not `ChangeNotifierProvider`). You cannot `listen: true` to it from a ChangeNotifier.

The correct pattern: **inject `CollectionSource` as a constructor parameter** into `IndexingProvider` at app startup, not via `Provider.of` at index time:

```dart
// In lib/widgets/aves_app.dart — where EmbeddingProvider is registered:
final source = context.read<CollectionSource>();
ChangeNotifierProvider<IndexingProvider>(
  create: (_) => IndexingProvider(
    clipService: MobileClipService(),
    embeddingProvider: _embeddingProvider,
    collectionSource: source,  // inject at construction
  ),
),
```

```dart
// IndexingProvider constructor:
class IndexingProvider extends ChangeNotifier with WidgetsBindingObserver {
  final CollectionSource _source;
  final EmbeddingProvider _embeddingProvider;
  final MobileClipService _clipService;

  IndexingProvider({
    required CollectionSource collectionSource,
    required EmbeddingProvider embeddingProvider,
    required MobileClipService clipService,
  })  : _source = collectionSource,
        _embeddingProvider = embeddingProvider,
        _clipService = clipService {
    // Register lifecycle observer so background indexing can skip UI notifies.
    // Android throttles background Dart work when the UI thread is active;
    // skipping notifyListeners() when backgrounded eliminates this bottleneck.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setInBackground(state != AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> autoIndex() async {
    // visibleEntries excludes trash — correct for indexing
    final unindexed = _source.visibleEntries
        .where((e) => !e.isVideo)   // extension from aves_model props.dart
        .where((e) => !_embeddingProvider.hasEmbedding(e.id.toString()))
        .toList();
    await _indexEntries(unindexed);
  }
}
```

**Thumbnail retry — reproduce the 3-level fallback from the original `IndexingProvider`:**

The actual Galleryze `IndexingProvider` retries thumbnail fetch at 3 sizes before skipping:
```dart
// In _indexEntries(), reproduce this pattern with MlThumbnailService:
Uint8List? thumbBytes;
for (final size in [256, 128, 64]) {
  thumbBytes = await MlThumbnailService.fetchThumbnail(
      entry.id.toString(), entry.mimeType, size: size);
  if (thumbBytes != null) break;
}
if (thumbBytes == null) return; // skip this entry
```
Update `MlThumbnailChannel.kt` to accept an optional `size` argument (default 256), and pass the `Size(size, size)` to `contentResolver.loadThumbnail()`.

---

**`AvesEntry.isVideo` is an extension getter (Challenge O):**
It lives in `plugins/aves_model/lib/src/entry/extensions/props.dart`. Import it:
```dart
import 'package:aves_model/src/entry/extensions/props.dart';
```
The getter is: `bool get isVideo => mimeType.startsWith('video/')` — same logic you can replicate inline if the import is awkward.

**`AvesEntry` key fields for IndexingProvider:**
```dart
entry.id          // int  — Android MediaStore _ID (same source as photo_manager's AssetEntity.id)
entry.mimeType    // String — e.g. "image/jpeg", "video/mp4"
entry.isVideo     // bool (extension getter)
entry.uri         // String — "content://media/external/images/media/123"
```

**Use `entry.id.toString()` as the embedding key** — all `Map<String, Float32List>` lookups must stringify the int.

**`CollectionSource` readiness guard — critical:**

`CollectionSource.visibleEntries` is empty until Aves finishes loading media from MediaStore. Calling `autoIndex()` immediately at startup gives 0 items to index.

**Solution:** listen to `source.stateNotifier` and trigger only when `SourceState.ready`:

```dart
// In IndexingProvider constructor or init():
_source.stateNotifier.addListener(_onSourceStateChanged);

void _onSourceStateChanged() {
  if (_source.stateNotifier.value == SourceState.ready) {
    _source.stateNotifier.removeListener(_onSourceStateChanged);
    autoIndex();  // now visibleEntries is fully populated
  }
}
```

**Alternative — hook into `_onAnalysisCompletion` in `aves_app.dart`:**

Aves fires `_onAnalysisCompletion()` (in `_AvesAppState`) after cataloguing/geocoding is done — this is AFTER `SourceState.ready`. Add a call there:

```dart
// lib/widgets/aves_app.dart — _onAnalysisCompletion():
Future<void> _onAnalysisCompletion() async {
  await _mediaStoreSource.loadCatalogMetadata();
  await _mediaStoreSource.loadAddresses();
  _mediaStoreSource.updateDerivedFilters();

  // ── Galleryze addition ─────────────────────────────────────
  final indexingProvider = _indexingProvider;  // stored in _AvesAppState
  await indexingProvider.autoIndex();
  // ──────────────────────────────────────────────────────────
}
```

Either approach works. The `stateNotifier` listener approach is self-contained within `IndexingProvider`; the `_onAnalysisCompletion` hook requires minimal surgery to `aves_app.dart`.

---

**Also port `CleanupProvider` (DBSCAN):**

The DBSCAN isolate function `_dbscanIsolate` is pure Dart — copy as-is, zero changes.

The `CleanupProvider` class needs a new constructor (takes `EmbeddingProvider` + `CollectionSource` instead of `PhotoProvider`), and two specific method bodies change:

```dart
// NEW constructor:
class CleanupProvider with ChangeNotifier {
  final EmbeddingProvider _embeddingProvider;
  final CollectionSource _source;
  final MobileClipService _clip = MobileClipService();
  // ... all other fields unchanged ...

  StreamSubscription? _entryRemovedSub;

  CleanupProvider(this._embeddingProvider, this._source) {
    // Prune groups when photos are DELETED from the library.
    // CollectionSource is not a ChangeNotifier — use its EventBus.
    // Aves fires an event when entries are removed (after trash/delete).
    // Look for the event class in plugins/aves_model/lib/src/source/events.dart
    // and subscribe to removal events only:
    _entryRemovedSub = _source.eventBus
        .on<EntryRemovedEvent>()   // confirm class name in Aves source
        .listen((_) => _pruneStaleGroups());
  }

  @override
  void dispose() {
    _entryRemovedSub?.cancel();
    super.dispose();
  }

  // NEW _pruneStaleGroups — uses source.visibleEntries instead of _photoProvider.photos:
  void _pruneStaleGroups() {
    if (_groups.isEmpty) return;
    final existingIds = _source.visibleEntries
        .map((e) => e.id.toString())
        .toSet();
    bool changed = false;
    _groups = _groups.map((g) {
      final surviving = g.photoIds.where((id) => existingIds.contains(id)).toList();
      if (surviving.length == g.photoIds.length) return g;
      changed = true;
      if (surviving.length < 2) return null;
      final bestStillExists = surviving.contains(g.bestShotId);
      return SimilarGroup(
        groupId: g.groupId, photoIds: surviving,
        bestShotId: bestStillExists ? g.bestShotId : surviving.first,
        type: g.type,
      );
    }).whereType<SimilarGroup>().toList();
    if (changed) notifyListeners();
  }
}
```

**Full method swap table:**
- `_photoProvider.getAllIndexedPhotoIds()` → `_embeddingProvider.getAllIndexedIds()`
- `_photoProvider.getEmbedding(id)` → `_embeddingProvider.getEmbedding(id)` ← **also applies inside `_buildGroup()`, which calls `_photoProvider.getEmbedding()` twice (for pairwise similarity and blurry anchor scoring) — change both calls**
- `_photoProvider.ensureMetadataLoaded()` → `_embeddingProvider.ensureEmbeddingsLoaded()`
- `_photoProvider.fetchPhotosByIds(ids)` → **delete entirely**. The actual `runCleanup()` has this block after building groups:
  ```dart
  // ← DELETE THIS BLOCK in the Aves version:
  if (allGroupedIds.isNotEmpty) {
    await _photoProvider.fetchPhotosByIds(allGroupedIds);
  }
  ```
  In Aves, `source.visibleEntries` is always fully loaded — entries are never "not in cache". Remove the block entirely, it has no equivalent.
- `_photoProvider.photos.where(...)` in `_pruneStaleGroups` → `_source.visibleEntries` (see code above)

**Also copy `lib/models/similar_group.dart` → `lib/galleryze/models/similar_group.dart`.** `CleanupProvider` depends on `SimilarGroup` and `ClusterType` — these are pure Dart models with zero `photo_manager` references and copy as-is.

> **⚠️ DBSCAN Scale Warning — Read Before Wiring Auto-Trigger**
>
> DBSCAN is **O(n²)** in the number of embeddings. For each photo it computes cosine distance against every other photo. Concrete numbers:
>
> | Library size | Dot products | Estimated time (mobile) |
> |---|---|---|
> | 1 000 photos | ~500K | 1–2 s |
> | 5 000 photos | ~12.5M | 10–20 s |
> | 10 000 photos | ~50M | 30–60 s |
> | 20 000 photos | ~200M | 2–4 min |
>
> The SIMD `Float32x4` path in `_dbscanIsolate` gives a ~4× speedup, keeping 10K photos in the 10–15 s range on a mid-range 2023 device — but this is still far too slow for automatic background runs.
>
> **Rules to follow:**
> 1. **Never trigger `runCleanup()` automatically** — only on explicit user action (the `GalleryzeIndexButton` "Review Duplicates" tap).
> 2. **Show a progress indicator** while `runCleanup()` is in flight (the `CleanupProvider.isRunning` flag drives this). The call is already in a `compute()` isolate so the UI stays responsive, but the user needs to know work is happening.
> 3. **Scope future optimization** — if users with 20K+ photos report unacceptable wait times, the fix is to only run DBSCAN on the *newly indexed* batch (pass just the new IDs + their neighbors as a subgraph) rather than the full embedding set.

---

### 3.3 — New: `EmbeddingProvider` (Challenges B, G)

`PhotoProvider` in Galleryze served double duty as media list + embedding store. In Aves, the media list is Aves' job. Extract only the **embedding half** into a new standalone provider.

**Create `lib/galleryze/providers/embedding_provider.dart`:**

Extract these exact methods from Galleryze's `PhotoProvider` (lines ~400–700 of the original file):

```dart
// lib/galleryze/providers/embedding_provider.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/tensor_utils.dart';
import '../services/mobile_clip_service.dart';

class EmbeddingProvider extends ChangeNotifier {
  // ── State ─────────────────────────────────────────────────────────────────
  final Map<String, Float32List> _embIndex = {};
  bool _embeddingsLoaded = false;
  bool _embDirty = false;

  // ── Public API ────────────────────────────────────────────────────────────
  bool hasEmbedding(String id) => _embIndex.containsKey(id);
  Float32List? getEmbedding(String id) => _embIndex[id];
  List<String> getAllIndexedIds() => _embIndex.keys.toList();
  int get indexedCount => _embIndex.length;

  Timer? _autoSaveTimer;

  void setEmbedding(String id, Float32List vec) {
    _embIndex[id] = vec;
    _embDirty = true;
    // Safety net: auto-save after 10s of inactivity in case the app is killed
    // between explicit checkpoint flushes (matches PhotoProvider behaviour).
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 10), flushEmbeddings);
    // ⚠️ DO NOT call notifyListeners() here.
    // notifyListeners() on every setEmbedding() fires once per image during indexing.
    // CleanupProvider subscribes to EmbeddingProvider — each notification would
    // re-run _pruneStaleGroups() and trigger UI rebuilds on every single stored
    // vector (potentially 10 000+ calls during a full index pass).
    // Only call notifyListeners() inside flushEmbeddings() (every 54 images)
    // and in ensureEmbeddingsLoaded() after the initial load completes.
  }

  // ── Load (call before first search or indexing) ───────────────────────────
  Future<void> ensureEmbeddingsLoaded() async {
    if (_embeddingsLoaded) return;
    await _loadEmbeddingsBinary();
    _embeddingsLoaded = true;
  }

  // ── Flush (call every 54 images during indexing) ─────────────────────────
  Future<void> flushEmbeddings() async {
    if (!_embDirty) return;
    await _saveEmbeddingsBinary();
    _embDirty = false;
  }

  // ── Semantic Search ───────────────────────────────────────────────────────
  // Copy the full semanticSearch() method from PhotoProvider — see §3.4.
  // ⚠️ The weighted encoding and filter logic are INLINE inside semanticSearch(),
  // not in separate helper methods. Copy the whole method body, then change
  // only the final hydration step (PhotoItem → AvesEntry lookup).
  // Return type changes from List<PhotoItem> to List<AvesEntry>.

  // ── Private: binary read/write (copy from PhotoProvider as-is) ───────────
  Future<void> _loadEmbeddingsBinary() async { /* copy from PhotoProvider */ }
  Future<void> _saveEmbeddingsBinary() async { /* copy from PhotoProvider */ }
}
```

**Import paths within `lib/galleryze/` use relative imports — no changes needed:**
```dart
// From lib/galleryze/providers/embedding_provider.dart:
import '../utils/tensor_utils.dart';       // → lib/galleryze/utils/tensor_utils.dart ✓
import '../services/mobile_clip_service.dart'; // → lib/galleryze/services/... ✓
```
Relative imports within the `lib/galleryze/` subtree resolve correctly as long as the directory structure mirrors the original Galleryze layout.

**Injection point: `lib/widgets/aves_app.dart` in `_AvesAppState.build()` (Challenge G)**

This is the file that contains Aves' `MultiProvider` stack. Do NOT put it in `main_common.dart` (that file only calls `runApp`). Add to the `providers: [...]` list:

```dart
// In lib/widgets/aves_app.dart, _AvesAppState.build():
return MultiProvider(
  providers: [
    Provider<AppFlavor>.value(value: widget.flavor),
    ChangeNotifierProvider<Settings>.value(value: settings),
    ListenableProvider<ValueNotifier<AppMode>>.value(value: _appModeNotifier),
    Provider<CollectionSource>.value(value: _mediaStoreSource),
    // ... Aves' existing providers ...

    // ─── Galleryze additions ──────────────────────────────────
    ChangeNotifierProvider<EmbeddingProvider>(
      create: (_) => EmbeddingProvider(),
    ),
    ChangeNotifierProvider<IndexingProvider>(
      create: (ctx) => IndexingProvider(
        collectionSource: ctx.read<CollectionSource>(),
        embeddingProvider: ctx.read<EmbeddingProvider>(),
        clipService: MobileClipService(),
      ),
    ),
    ChangeNotifierProvider<CleanupProvider>(
      create: (ctx) => CleanupProvider(
        ctx.read<EmbeddingProvider>(),
        ctx.read<CollectionSource>(),
      ),
    ),
    // ─────────────────────────────────────────────────────────
  ],
  child: ...,
);
```

> Keep all Galleryze provider files in `lib/galleryze/` subdirectory to minimize conflicts with upstream Aves merges.

---

### ✅ Test Checkpoint 3 — Providers Registered (§3.1–§3.3 complete)

```bash
flutter run --flavor play
```

Verify on device:
- [ ] App launches without crashing — if providers are mis-injected, this is where it will blow up
- [ ] No `ProviderNotFoundException` or `NullPointerException` in logcat at startup
- [ ] Gallery still loads and scrolls normally (Aves gallery features must be unaffected)

No ML features will be visible yet — that's expected.

If app crashes at startup with `ProviderNotFoundException`: the injection order in `aves_app.dart` is wrong — `EmbeddingProvider` must be declared before `IndexingProvider`, which must be declared before `CleanupProvider`.  
If `MlThumbnailChannel` causes a `MissingPluginException`: the Kotlin `MethodChannel` name in `MlThumbnailService.dart` doesn't match the channel name registered in `MainActivity.kt` — check §3.1.

---

### 3.4 — Semantic Search: Extraction from `PhotoProvider` (Challenge C)

`semanticSearch()` lives in `PhotoProvider` (~lines 918–1013 of the actual file). **There are no separate `_encodeWeighted` or `_applySearchFilters` helper methods** — the weighted encoding, scoring loop, and filter logic are all inline within `semanticSearch()`.

**How to migrate it — three steps:**

**Step 1 — Copy the entire `semanticSearch()` body into `EmbeddingProvider`**, changing the signature:
```dart
// OLD (PhotoProvider):
Future<List<PhotoItem>> semanticSearch(String query, {int topK = 100}) async { ... }

// NEW (EmbeddingProvider): accept source as parameter, return AvesEntry
Future<List<AvesEntry>> semanticSearch(String query, CollectionSource source) async { ... }
```

**Step 2 — Change only the opening reset and the final hydration:**
```dart
// OLD — reset PhotoItem search scores (no equivalent needed in Aves):
_photoCache.values.forEach((p) => p.searchScore = null);  // ← DELETE this block

// OLD — iterate embeddings from internal _embIndex (same field name, keep as-is):
_embIndex.forEach((id, emb) { ... });  // ✓ unchanged

// OLD — hydrate PhotoItem from cache:
final item = await _getOrFetchPhoto(entry.key);  // ← REPLACE

// NEW — look up AvesEntry by int ID:
final idSet = resultsToFetch.map((e) => int.tryParse(e.key)).whereNotNull().toSet();
return source.visibleEntries
    .where((e) => idSet.contains(e.id))
    .toList();
```

**Step 3 — The rest is verbatim copy:**
- Weighted ensemble (40% raw + 20% × 3 variants) — copy as-is
- Scoring loop (`_embIndex.forEach`) — copy as-is
- Sort, absolute floor (≥0.16), drop-off filter (top × 0.65), top-5 safety floor (≥0.13) — copy as-is
- `MobileClipService()`, `clip.initialize()`, `clip.encodeText()` — copy as-is
- `TensorUtils.l2Normalize(weightedVec)` — copy as-is

**Note on `topK`:** The default signature is `{int topK = 100}` but the body hardcodes `.take(1000)`. The parameter is vestigial — the effective result limit is always 1000. You can simplify to remove the parameter entirely.

`whereNotNull()` comes from `package:collection` which is already in Aves' `pubspec.yaml`.

---

### 3.5 — PreferenceService: Confirmed Key Collisions (Challenge I)

**This is not a risk — it is confirmed.** Aves uses `search_history` as an actual SharedPreferences key (via `SettingKeys.saveSearchHistoryKey`). Writing to it from Galleryze's `PreferenceService` without a prefix will corrupt Aves' own search history.

**Aves' known SharedPreferences keys that overlap with Galleryze's:**

| Aves key | Galleryze key | Conflict |
|----------|--------------|---------|
| `search_history` | `search_history` | **Direct collision** |
| `collection_sort_factor` | `sort_option` | No (different name, safe) |

**Action — port ONLY the search history key, renamed with `glrz_` prefix:**

```dart
// Minimal PreferenceService for Aves — keep ONLY search history:
class GlrzPreferenceService {
  static const _searchHistoryKey = 'glrz_search_history';  // was: 'search_history' (collision!)

  static Future<void> saveSearchHistory(List<String> history) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_searchHistoryKey, history);
  }

  static Future<List<String>> loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_searchHistoryKey) ?? [];
  }
}
```

**Do NOT port:**
- `saveSortOption` / `loadSortOption` — **Aves handles sort**. Use Aves' `Settings` object for any sort preferences.
- `saveFavorites` / `loadFavorites` — **Aves handles favorites** via `Favourites` SQLite (see §3.12).
- Any other preference that is a gallery feature — Aves owns that.

---

### 3.6 — Embedding ID Compatibility (Challenge D)

**Will users' existing `embeddings.bin` survive the migration?**

**Current Galleryze:** embedding keys = `AssetEntity.id` (Android MediaStore `_ID` integer, stored as `String`, e.g. `"12345"`).

**Aves:** `AvesEntry.id` is `int` — also the Android MediaStore `_ID`. Both `photo_manager` and Aves read from `MediaStore.Images.Media._ID`. They are the same value.

**Result: existing `embeddings.bin` survives the migration. No re-indexing needed for existing users.**

**ID type handling throughout the codebase:**

```dart
// Writing to embedding index:
embeddingProvider.setEmbedding(entry.id.toString(), vector);  // int → String key

// Checking index:
embeddingProvider.hasEmbedding(entry.id.toString());

// Reverse lookup (embedding ID → AvesEntry):
final entry = source.getEntryById(int.parse(embeddingId));    // String → int lookup

// In semanticSearch results:
final matchedIds = scored.map((e) => int.tryParse(e.key)).whereNotNull().toSet();
final results = source.visibleEntries.where((e) => matchedIds.contains(e.id)).toList();
```

Use `entry.id.toString()` everywhere in Galleryze code. Use `source.getEntryById(int.parse(id))` when going back from an embedding ID to an entry. `CollectionSource._entriesById` is `Map<int, AvesEntry>` and `getEntryById(int id)` is a public method.

---

### 3.7 — Correct Dependency Versions (Challenge M)

The `flutter_onnxruntime` version in Galleryze is `1.6.3`, not `1.22.0`. The `1.22` is the underlying `onnxruntime-android` native lib version, not the Flutter wrapper.

**Confirmed: `path_provider` and `image` are NOT in Aves' `pubspec.yaml`.** Both must be added.

**Add to Aves' `pubspec.yaml` `dependencies:` section:**
```yaml
flutter_onnxruntime: 1.6.3    # MobileCLIP ONNX inference
path_provider: ^2.1.0          # MobileClipService: copies ONNX models to support dir
image: ^4.8.0                  # TensorUtils: pure-Dart image decode + preprocessing
```

These three are the only new pub dependencies needed. All other packages (`shared_preferences`, `collection`, `sqflite`, `provider`) are already in Aves.

---

### 3.8 — Build Config: minSdk, JVM, NDK (Challenges K, L)

**minSdk — Aves is definitively 21, ORT requires 24:**

Aves' `build.gradle.kts` uses `flutter.minSdkVersion` which resolves to **21** in Flutter 3.x. ORT requires minSdk **24**. You must explicitly override:

```kotlin
// In android/app/build.gradle.kts defaultConfig block:
minSdk = 24   // explicit override — do NOT use flutter.minSdkVersion
```

**JVM toolchain — Aves uses Java 21, Galleryze used 17:**

Aves sets `compileOptions { jvmToolchain(21) }` (or equivalent). Keep it at 21 — do not downgrade. `flutter_onnxruntime` 1.6.3 is compatible with Java 21.

**NDK version:**
```kotlin
ndkVersion = "27.0.12077973"   // required by flutter_onnxruntime
```

**ABI filters (release only):**
```kotlin
// In release buildType:
ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
```

**Packaging exclusions** (prevents ORT `.so` files from bloating APK):
```kotlin
packaging {
    resources {
        excludes += "lib/**/libonnxruntime_providers_nnapi.so"
        excludes += "lib/**/libonnxruntime_providers_openvino.so"
        excludes += "lib/**/libonnxruntime_providers_shared.so"
    }
    jniLibs {
        pickFirsts += "**/libc++_shared.so"
    }
}
```

---

### 3.9 — ONNX Model Assets

Copy from current Galleryze `assets/` to Aves `assets/`:
```
assets/mobileclip_s0_fp32.onnx   (45.5 MB)
assets/text_encoder_fp32.onnx    (169.8 MB)
assets/vocab.json                (~1 MB)
assets/merges.txt                (~500 KB)
```

**No pubspec change needed.** Aves' `pubspec.yaml` declares assets as a single wildcard:
```yaml
flutter:
  assets:
    - assets/    # entire directory — all files inside are automatically included
```
Just drop the files into `assets/` and they are registered automatically.

> **⚠️ Git LFS required for the text encoder.**
> `text_encoder_fp32.onnx` is **169.8 MB** — above GitHub's 100 MB hard limit. Pushing to GitHub without Git LFS will fail. Set up LFS before adding these files:
> ```bash
> git lfs install
> git lfs track "*.onnx"
> git add .gitattributes
> git add assets/*.onnx
> git commit -m "add MobileCLIP ONNX models via LFS"
> ```
> The 45.5 MB image encoder and 169.8 MB text encoder both need LFS tracking. If you already pushed and hit the limit, follow GitHub's guide to migrate with `git lfs migrate import`.

---

### ✅ Test Checkpoint 4 — ML Pipeline Wired (§3.4–§3.9 complete)

```bash
flutter run --flavor play
```

Verify on device:
- [ ] App launches without crashing — ORT model load happens at startup; any missing asset or minSdk issue will crash here
- [ ] In logcat, look for a line like `OrtEnvironment initialized` or `MobileClipService: models loaded` — absence means `initialize()` was not called in `_AvesAppState.initState()`
- [ ] No `AssetNotFoundException` for `mobileclip_s0_fp32.onnx` or `text_encoder_fp32.onnx`
- [ ] No `UnsatisfiedLinkError` from the ORT native library — means NDK or minSdk is still wrong (§3.8)
- [ ] Gallery still loads normally — adding providers must not break Aves' existing screens

No index button or search results are visible yet — that's expected.

If ORT fails to load with `UnsatisfiedLinkError`: `minSdkVersion` in `build.gradle.kts` is still below 24 — fix §3.8.  
If assets fail: verify `pubspec.yaml` declares `assets/` as a directory wildcard, not individual file paths.

---

### 3.9b — IndexForSearchButton → Aves Equivalent

The current `IndexForSearchButton` widget (~400 lines) uses `photo_manager` heavily — album selection dialog, `AssetPathEntity`, `AssetEntity` iteration. **All of this is thrown away.** In Aves, `source.visibleEntries` already contains every image on the device.

**New `GalleryzeIndexButton` widget — triggers indexing then smart cleanup:**

```dart
// lib/galleryze/widgets/galleryze_index_button.dart
class GalleryzeIndexButton extends StatelessWidget {
  const GalleryzeIndexButton({super.key});

  @override
  Widget build(BuildContext context) {
    final indexer = context.watch<IndexingProvider>();
    final cleanup = context.watch<CleanupProvider>();
    final isBusy = indexer.isProcessing || cleanup.status == CleanupStatus.loading;
    return IconButton(
      icon: isBusy
          ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.image_search_outlined),
      tooltip: isBusy ? 'Working…' : 'Index for AI Search',
      onPressed: isBusy ? null : () => _runIndexAndCleanup(context),
    );
  }

  Future<void> _runIndexAndCleanup(BuildContext context) async {
    final indexer = context.read<IndexingProvider>();
    final cleanup = context.read<CleanupProvider>();

    cleanup.reset();

    // Start indexing but DO NOT await yet — we need to show the popup concurrently.
    // Awaiting autoIndex() before showing the dialog would block the UI thread silently
    // for potentially minutes on a large library. The actual IndexForSearchButton uses
    // the same pattern: start the task, then show the dialog, then await the task.
    final indexingTask = indexer.autoIndex();

    // Show blocking progress popup (port GlassProgressPopup + Consumer2 from
    // IndexForSearchButton.runIndexingWithPopup — replace List<AssetEntity>
    // references with List<AvesEntry>, everything else is unchanged):
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dContext) => Consumer2<IndexingProvider, CleanupProvider>(
          builder: (ctx, idx, cln, _) {
            final isCleanupPhase = !idx.isProcessing;
            return GlassProgressPopup(               // port from ui_kit.dart
              progress: isCleanupPhase ? 1.0 : idx.progress,
              processedItems: isCleanupPhase ? idx.totalImages : idx.processedImages,
              totalItems: idx.totalImages,
              elapsedTime: idx.elapsedTime + cln.cleanupElapsedTime,
              status: isCleanupPhase ? 'Scanning for duplicates…' : 'Building AI search index',
            );
          },
        ),
      );
    }

    await indexingTask;   // wait for indexing to finish

    // Phase 2 — DBSCAN duplicate detection
    if (context.mounted) await cleanup.runCleanup();

    // Dismiss popup
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

    // Notify user if duplicates found
    if (context.mounted && cleanup.groups.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Found ${cleanup.groups.length} duplicate groups'),
        action: SnackBarAction(
          label: 'Review',
          onPressed: () => Navigator.pushNamed(context, SmartCleanupPage.routeName),
        ),
      ));
    }
  }
}
```

> **Why start indexing before showing the dialog?** `showDialog` is non-blocking — it returns immediately and the dialog renders on the next frame. If you `await indexer.autoIndex()` first, the UI freezes silently for the entire indexing duration with no visual feedback. The pattern above is the same one used in the original `IndexForSearchButton.runIndexingWithPopup`: start the task as a `Future`, then show the dialog, then `await` the `Future`.

**Port `GlassProgressPopup`** from `lib/widgets/ui_kit.dart` to `lib/galleryze/widgets/glass_progress_popup.dart` — it has zero `photo_manager` dependencies and copies as-is.

Place `GalleryzeIndexButton` in `GalleryzeSearchPage`'s AppBar actions.

> Auto-indexing on startup (via `_onAnalysisCompletion`) does NOT automatically run cleanup — the DBSCAN scan is CPU-intensive and only runs when explicitly triggered by the user pressing `GalleryzeIndexButton`.

---

### ✅ Test Checkpoint 5 — Index Button Working (§3.9b complete)

```bash
flutter run --flavor play
```

Verify on device:
- [ ] The index button (`GalleryzeIndexButton`) is visible in the app bar of the Search page (it won't be tappable yet since the Search tab isn't added — place a temporary `Scaffold` with the button to test, or add the button to the existing home screen temporarily)
- [ ] Tapping the button shows the progress popup (two-phase: "Indexing…" then "Scanning for duplicates…")
- [ ] Progress increments — logcat shows batches being processed
- [ ] Popup dismisses when complete, snackbar appears if duplicates found

If tapping the button has no visible effect: check that `GalleryzeIndexButton` calls `indexer.autoIndex()` and that `IndexingProvider` is correctly registered in the `MultiProvider` stack.  
If progress stalls at 0: the ONNX models failed to warm up — check logcat for ORT errors at startup.

---

### 3.10 — Adding the Search Tab: Correct Mechanism (Challenge E)

**`AvesNavItem` is NOT abstract — do not subclass it.** It is a concrete `Equatable` data class with `toJson()`/`fromJson()` already built in. You just instantiate it with a `route:` string. The icon/label for that route are resolved inside `nav_bar.dart` via a switch statement.

```dart
// Actual AvesNavItem definition (lib/widgets/navigation/nav_item.dart):
class AvesNavItem extends Equatable {
  final String route;
  final Set<CollectionFilter>? filters;
  final String? path;
  const AvesNavItem({required this.route, this.filters, this.path});
  String toJson() => jsonEncode({'route': route, ...});          // built-in serialization
  static AvesNavItem? fromJson(String? json) { ... }            // built-in deserialization
}
```

**4 concrete steps:**

**Step 1 — Create the page with embedding preload:**
```dart
// lib/galleryze/view/search/galleryze_search_page.dart
class GalleryzeSearchPage extends StatefulWidget {
  static const routeName = '/galleryze_search';
  const GalleryzeSearchPage({super.key});
  @override State<GalleryzeSearchPage> createState() => _GalleryzeSearchPageState();
}

// ⚠️ CRITICAL: use AutomaticKeepAliveClientMixin.
// Without it, Flutter destroys this widget's state every time the user switches
// to a different nav tab — search results and the text field clear on every tab switch.
// The actual SearchScreen uses this mixin for exactly this reason.
class _GalleryzeSearchPageState extends State<GalleryzeSearchPage>
    with AutomaticKeepAliveClientMixin {

  @override
  bool get wantKeepAlive => true;  // keep state alive across tab switches

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  List<AvesEntry> _searchResults = [];
  bool _isSearching = false;
  List<String> _searchHistory = [];

  // Default suggestions shown when search history is empty:
  static const List<String> _defaultSuggestions = [
    'a green dress', 'sunset over mountains',
    'group of friends', 'birthday cake',
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadSearchHistory();
    // CRITICAL: load embeddings from disk before the user can search.
    // If not loaded, _embIndex is empty and all searches return nothing.
    // This is fast if already loaded (no-op), slow on first call (~100–500 ms).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EmbeddingProvider>().ensureEmbeddingsLoaded();
    });
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();
    final query = _searchController.text.trim();
    if (query.length < 3) {
      setState(() { _searchResults = []; _isSearching = false; });
      return;
    }
    // 1-second debounce — matches the actual SearchScreen timing exactly.
    // Too short (< 500ms) triggers a new ONNX inference on every keystroke.
    _debounceTimer = Timer(const Duration(seconds: 1), () => _performSearch(query));
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    // No clearSearchScores() needed — AvesEntry has no searchScore field.
    // Just clear local results list.
    _searchResults = [];
    super.dispose();
  }
```

**Step 2 — Register the route.** In `lib/widgets/aves_app.dart` (or wherever Aves' `MaterialApp` defines `onGenerateRoute`/`routes`), add:
```dart
GalleryzeSearchPage.routeName: (_) => const GalleryzeSearchPage(),
```

**Step 3 — Register icon + label in `lib/widgets/navigation/nav_bar/nav_bar.dart`.** Find the switch/if block that maps `navItem.route` to icon and label, add:
```dart
case GalleryzeSearchPage.routeName:
  icon = Icons.search_outlined;
  label = 'Search';
  break;
```

**Step 3b — Add early ONNX warm-up.** In `GalleryzeApp` (current `app.dart`), `initState` calls `indexingProvider.initialize()` immediately so models are hot before the user types a search. Do the same in `_AvesAppState.initState()`:

```dart
// lib/widgets/aves_app.dart — _AvesAppState.initState(), near the end:
WidgetsBinding.instance.addPostFrameCallback((_) {
  // Pre-load ONNX models so first search feels instant.
  context.read<IndexingProvider>().initialize().catchError((e) {
    debugPrint('[AvesApp] IndexingProvider pre-init failed (non-critical): $e');
  });
});
```

Without this, models load lazily on the first search — adding 2–4 seconds of perceived latency.

**Step 4 — Add to default nav items** in `lib/model/settings/defaults.dart`:
```dart
static final bottomNavigationActions = [
  const AvesNavItem(route: CollectionPage.routeName),
  AvesNavItem(route: CollectionPage.routeName, filters: {MimeFilter.video}),
  AvesNavItem(route: CollectionPage.routeName, filters: {FavouriteFilter.instance}),
  const AvesNavItem(route: AlbumListPage.routeName),
  const AvesNavItem(route: GalleryzeSearchPage.routeName),   // ← add this
];
```

**Display results — do NOT use `EntryGrid` directly.**

`EntryGrid` is Aves' main collection grid widget but it requires a `CollectionLens` (which wraps `CollectionSource` with filters and sort) — it cannot accept an arbitrary `List<AvesEntry>`. Using it for search results would require hacking `CollectionLens`, which breaks the Aves/Galleryze boundary.

**Correct approach — use `ThumbnailProvider` in a standard `GridView.builder`:**

```dart
GridView.builder(
  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2,
  ),
  itemCount: _searchResults.length,
  itemBuilder: (context, i) {
    final entry = _searchResults[i];
    return GestureDetector(
      onTap: () => _openViewer(context, entry, i),
      child: Image(
        image: ThumbnailProvider(             // ← Aves' infrastructure for thumbnail loading
          entry: entry,
          extent: 256,
        ),
        fit: BoxFit.cover,
      ),
    );
  },
)
```

`ThumbnailProvider` lives in `plugins/aves_model/` — no extra import needed after renaming. It handles caching, disk access, and decoding using Aves' native thumbnail pipeline.

**Opening Aves' viewer from a search result tap:**

Find how `CollectionPage`'s tile tap opens the viewer in Aves (look in `lib/view/collection/collection_page.dart` — the `onTap` callback on a thumbnail). Replicate that exact call, passing the entry. You want Aves' native viewer so the user gets all the standard interactions (swipe through results, zoom, share, delete, edit metadata).

The viewer will need a browseable collection. The simplest approach: build a `CollectionLens` filtered to just your search result IDs using Aves' `IdFilter` or equivalent, then pass that to the viewer. This keeps all viewer functionality inside Aves.

> **Search score note:** `AvesEntry` has no `searchScore` field. Keep results in a `List<AvesEntry>` sorted by score (highest first). The order is the signal — no per-entry annotation needed. Replace `clearSearchScores()` (from old Galleryze) with `setState(() => _searchResults = [])` in `dispose()`.

---

### ✅ Test Checkpoint 6 — Semantic Search Working (§3.10 complete)

```bash
flutter run --flavor play
```

Verify on device:
- [ ] A **Search** tab appears in the bottom navigation bar
- [ ] Tapping Search opens `GalleryzeSearchPage` — a text input field is visible
- [ ] With 0 embeddings indexed: typing 3+ chars shows an empty state (not a crash)
- [ ] After running the index button: typing a query (e.g. `"sunset"`, `"cat"`, `"birthday"`) returns a grid of photo results within 1–2 seconds
- [ ] Tapping a result photo opens Aves' native full-screen viewer
- [ ] Swiping through results in the viewer works

If the Search tab doesn't appear: the `AvesNavItem` was not added to `SettingsDefaults` or the route was not registered — re-check §3.10's nav registration steps.  
If search returns no results despite indexed photos: the embedding key format is wrong — verify `entry.id.toString()` is used as the key in both `IndexingProvider` and `EmbeddingProvider.semanticSearch()` (§3.6).  
If viewer crashes on tap: the `CollectionLens` approach for filtered results needs to match Aves' viewer API — look at how `CollectionPage` opens the viewer and replicate exactly.

---

### 3.11 — SmartCleanupPage: Rebuild in Aves Style

`SmartCleanupScreen` is the duplicate/burst-shot UI — DBSCAN groups of visually similar photos with a "best shot" highlighted and redundant ones pre-selected for deletion. It needs full rebuilding because every import is `photo_manager`-dependent. The **logic** (DBSCAN, scoring, grouping) stays in `CleanupProvider`; only the UI layer changes.

**What changes → Aves equivalent:**

| Current (Galleryze) | In Aves |
|---------------------|---------|
| `PhotoProvider.isSelectionMode` | Local `Set<String> _selectedIds` in widget state |
| `PhotoProvider.exitSelectionMode()` | `setState(() => _selectedIds.clear())` |
| `PhotoManagerImageProvider` | `ThumbnailProvider(entry: e, extent: 256)` |
| `PhotoViewScreen` for single tap | Aves' built-in viewer (same as §3.10 search results) |
| `media_dialogs.dart` delete + confirm | Aves' built-in delete action (see below) |
| `SimilarGroup`, `ClusterType` | Copy as-is from `lib/galleryze/models/similar_group.dart` |

> Selection state is entirely local UI: which photos in a group are checked for deletion. It needs neither `PhotoProvider` nor Aves' `SelectionController` — just `Set<String> _selectedIds` in `_SmartCleanupPageState`.

---

**Full implementation blueprint:**

**Step 1 — Convert `group.photoIds` (String list) to `AvesEntry` objects:**

```dart
// Helper — call this everywhere you need AvesEntry from a group:
Set<AvesEntry> _resolveEntries(List<String> ids, CollectionSource source) {
  return ids
      .map((id) => source.getEntryById(int.tryParse(id) ?? -1))
      .whereNotNull()
      .toSet();
}
```

**Step 2 — Default selection state** (all non-best shots pre-selected for deletion):

```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final cleanup = context.read<CleanupProvider>();
    if (cleanup.status == CleanupStatus.idle || cleanup.status == CleanupStatus.error) {
      cleanup.runCleanup();
    }
  });
}

// When building each group card, pre-select all non-best shots:
Set<String> _defaultSelectedForGroup(SimilarGroup group) =>
    group.photoIds.where((id) => id != group.bestShotId).toSet();
```

**Step 3 — Thumbnail display (Aves' `ThumbnailProvider`):**

```dart
// For each photo in a group:
final entry = source.getEntryById(int.tryParse(photoId) ?? -1);
if (entry == null) return const SizedBox.shrink();

Stack(children: [
  Image(
    image: ThumbnailProvider(entry: entry, extent: 200),
    width: 120, height: 120, fit: BoxFit.cover,
  ),
  if (photoId == group.bestShotId)
    const Positioned(top: 4, right: 4,
      child: Icon(Icons.star, color: Colors.amber, size: 20)), // best shot badge
  if (_selectedIds.contains(photoId))
    const Positioned.fill(
      child: ColoredBox(color: Color(0x44FF0000))),           // red overlay = selected
])
```

**Step 4 — Delete using Aves' native delete:**

> **Important:** The exact Dart deletion API depends on Aves' version. After cloning Aves, find how its own gallery deletes entries — search for `delete` in `lib/view/collection/` or `lib/model/actions/`. You want the same call Aves uses when the user taps "Delete" in the overflow menu. It handles Android 11+ trash/MediaStore permissions automatically.
>
> The pattern will look like one of these (verify against actual Aves source):
> ```dart
> // Option A — via EntryActions:
> await EntryActions.delete.execute(context, entries: entriesToDelete);
>
> // Option B — via StorageService (injected):
> final storageService = context.read<AvesServices>().storageService;
> await storageService.delete(entries: entriesToDelete, albumType: AlbumType.regular);
> ```
> **Do NOT write your own delete.** Aves handles everything: Android 11+ trash confirmation, MediaStore update, permission handling, and notifying `CollectionSource` to remove the entries.

After deletion, call `cleanup.removeGroup(group.groupId)` to remove the group from the UI — `CleanupProvider` already has this method.

**Step 5 — Full `SmartCleanupPage` structure:**

```dart
class SmartCleanupPage extends StatefulWidget {
  static const routeName = '/galleryze_cleanup';
  const SmartCleanupPage({super.key});
  @override State<SmartCleanupPage> createState() => _SmartCleanupPageState();
}

class _SmartCleanupPageState extends State<SmartCleanupPage> {
  // Per-group selection: groupId → Set of selected photoIds
  final Map<String, Set<String>> _groupSelections = {};

  @override
  Widget build(BuildContext context) {
    final cleanup = context.watch<CleanupProvider>();
    final source = context.read<CollectionSource>();

    return Scaffold(
      appBar: AppBar(title: const Text('Smart Cleanup')),
      body: switch (cleanup.status) {
        CleanupStatus.loading => const Center(child: CircularProgressIndicator()),
        CleanupStatus.error   => Center(child: Text(cleanup.error ?? 'Error')),
        CleanupStatus.done    => cleanup.groups.isEmpty
            ? const Center(child: Text('No duplicates found'))
            : _buildGroupList(cleanup.groups, source),
        _                     => const SizedBox.shrink(),
      },
    );
  }

  Widget _buildGroupList(List<SimilarGroup> groups, CollectionSource source) {
    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (context, i) => _buildGroupCard(groups[i], source),
    );
  }

  Widget _buildGroupCard(SimilarGroup group, CollectionSource source) {
    // Initialize selection defaults on first render
    _groupSelections.putIfAbsent(group.groupId,
        () => _defaultSelectedForGroup(group));
    final selected = _groupSelections[group.groupId]!;

    return Card(
      child: Column(children: [
        // Label: "Exact Duplicate" or "Near Duplicate" + count
        ListTile(
          title: Text(group.type == ClusterType.exactDuplicate
              ? 'Exact duplicate (${group.photoIds.length} photos)'
              : 'Near duplicate (${group.photoIds.length} photos)'),
          subtitle: Text('${selected.length} selected for deletion'),
        ),
        // Horizontal scroll of thumbnails
        SizedBox(
          height: 130,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: group.photoIds.map((id) {
              final entry = source.getEntryById(int.tryParse(id) ?? -1);
              if (entry == null) return const SizedBox.shrink();
              return GestureDetector(
                onTap: () => setState(() {
                  if (selected.contains(id)) selected.remove(id);
                  else selected.add(id);
                }),
                onLongPress: () => _openViewer(context, entry),
                child: _buildThumbnailTile(entry, id, group.bestShotId, selected),
              );
            }).toList(),
          ),
        ),
        // Delete button
        if (selected.isNotEmpty)
          TextButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: Text('Delete ${selected.length} photos'),
            onPressed: () => _deleteSelected(context, group, selected, source),
          ),
      ]),
    );
  }

  Future<void> _deleteSelected(BuildContext context, SimilarGroup group,
      Set<String> selectedIds, CollectionSource source) async {
    final entriesToDelete = _resolveEntries(selectedIds.toList(), source);
    if (entriesToDelete.isEmpty) return;

    // ── Use Aves' native delete here (see Step 4 above for exact call) ──
    // await EntryActions.delete.execute(context, entries: entriesToDelete);

    // After Aves confirms deletion, remove the group from CleanupProvider
    final cleanup = context.read<CleanupProvider>();
    cleanup.removeGroup(group.groupId);
  }
}
```

**Register the route** — add to Aves' route map (same as `GalleryzeSearchPage` in §3.10):
```dart
SmartCleanupPage.routeName: (_) => const SmartCleanupPage(),
```

> This screen has no nav bar tab. Link to it from a button on `GalleryzeSearchPage` (e.g., an AppBar action showing the duplicate count badge from `CleanupProvider.groups.length`).

> **Do NOT port `SelectionAppBarActions`** — it's `PhotoProvider`-coupled gallery code. The simple `_groupSelections` map above replaces everything it did for this specific screen.

---

**Triggering Smart Cleanup after indexing:**

In old Galleryze, `IndexForSearchButton.runIndexingWithPopup` called `cleanupProvider.runCleanup()` automatically after indexing finished. Preserve this in the new `GalleryzeIndexButton`:

```dart
Future<void> _triggerIndex(BuildContext context) async {
  final indexer = context.read<IndexingProvider>();
  final cleanup = context.read<CleanupProvider>();
  cleanup.reset();                    // clear stale groups from previous run
  await indexer.autoIndex();          // index new images
  await cleanup.runCleanup();         // then run DBSCAN on all embeddings
}
```

Show a progress indicator during both phases. When `cleanup.status == CleanupStatus.done && cleanup.groups.isNotEmpty`, show a badge or snackbar: "Found N duplicate groups — tap to review."

---

### ✅ Test Checkpoint 7 — Smart Cleanup Working (§3.11 complete)

```bash
flutter run --flavor play
```

First, ensure some photos are indexed (run the index button from Checkpoint 5 or 6). Then:

Verify on device:
- [ ] After indexing completes, a snackbar appears: "Found N duplicate groups — tap to review" (if duplicates exist in your test library)
- [ ] Tapping "Review" opens `SmartCleanupPage`
- [ ] Duplicate groups are shown — each group has a grid of similar photos with the best shot highlighted
- [ ] Pre-selected (redundant) photos are visually marked for deletion
- [ ] Tapping **Delete selected** invokes Aves' native delete flow (Android system confirmation dialog appears)
- [ ] After deletion, the deleted photos disappear from the group; groups with only 1 remaining photo are removed from the list
- [ ] The gallery is not corrupted — deleted photos are gone from the main grid too

If DBSCAN runs but returns 0 groups on a library with obvious duplicates: the cosine similarity threshold (0.85) may be too strict for your test photos. Check `_dbscanIsolate` parameters.  
If deletion silently fails: the `StorageService` call is wrong — check Aves' `CollectionPage` for the exact delete invocation signature and mirror it exactly (§3.11).  
If the app hangs during DBSCAN for a large library (10K+ photos): this is expected (see §3.2 DBSCAN scale warning) — ensure the progress indicator is shown and the call is running in a `compute()` isolate.

---

### 3.12 — Favorites Migration: Galleryze → Aves SQLite (Challenge F)

**This is a new challenge not in the old guide.** Aves stores favorites in its own SQLite database via a `Favourites` ChangeNotifier — it does NOT use SharedPreferences for favorites. Galleryze stores favorites in `photo_metadata.json` as a per-photo `isFavorite` flag.

**Consequence:** when users migrate from old Galleryze to new Aves-based Galleryze, their existing favorites will be lost unless we migrate them.

**How Aves' `Favourites` works:**
```dart
// From lib/model/favourites.dart:
class Favourites extends ChangeNotifier {
  Set<int> _favoriteIds;  // Set of AvesEntry.id (int)

  bool isFavourite(AvesEntry entry) => _favoriteIds.contains(entry.id);
  Future<void> add(Set<AvesEntry> entries) async { ... }   // writes to SQLite
  Future<void> remove(Set<AvesEntry> entries) async { ... }
}
```

It is provided in Aves' widget tree as `ChangeNotifierProvider<Favourites>`.

**Migration plan — run once on first Aves launch:**

```dart
// In EmbeddingProvider.ensureEmbeddingsLoaded() or a one-time migration service:
Future<void> _migrateOldFavorites(Favourites favourites, CollectionSource source) async {
  final prefs = await SharedPreferences.getInstance();
  const legacyKey = 'favorites';  // old Galleryze key

  // Only run if old data exists and migration hasn't happened
  if (prefs.getBool('glrz_favorites_migrated') == true) return;
  final legacyJson = prefs.getString(legacyKey);
  if (legacyJson == null) {
    await prefs.setBool('glrz_favorites_migrated', true);
    return;
  }

  // Parse old favorite IDs (stored as JSON array of id strings)
  final oldIds = (jsonDecode(legacyJson) as List).cast<String>();
  final entriesToFavorite = oldIds
      .map((id) => source.getEntryById(int.tryParse(id) ?? -1))
      .whereNotNull()
      .toSet();

  if (entriesToFavorite.isNotEmpty) {
    await favourites.add(entriesToFavorite);
  }

  await prefs.setBool('glrz_favorites_migrated', true);
  // Optionally remove the old key: await prefs.remove(legacyKey);
}
```

Run this after both `CollectionSource` has loaded entries and `EmbeddingProvider` has loaded embeddings.

---

### 3.13 — Phase 3 Checklist

**Dependencies & Build**
- [ ] `flutter_onnxruntime: 1.6.3`, `path_provider: ^2.1.0`, `image: ^4.8.0` added to `pubspec.yaml`
- [ ] `minSdk = 24` explicit override in `build.gradle.kts` (Aves defaults to 21)
- [ ] `ndkVersion = "27.0.12077973"` in `build.gradle.kts`
- [ ] ORT packaging exclusions added to `build.gradle.kts`

**Assets**
- [ ] `mobileclip_s0_fp32.onnx`, `text_encoder_fp32.onnx`, `vocab.json`, `merges.txt` dropped in `assets/` (no pubspec change needed — wildcard covers it)

**Kotlin**
- [ ] `MlThumbnailChannel.kt` created at `android/app/src/main/kotlin/com/galleryze/app/`
- [ ] Registered in `MainActivity.kt` inside `configureFlutterEngine()` after existing channels

**New Dart files (in `lib/galleryze/`)**
- [ ] `services/mobile_clip_service.dart` — copied from Galleryze as-is
- [ ] `services/ml_thumbnail_service.dart` — new, Dart side of thumbnail channel
- [ ] `utils/bpe_tokenizer.dart` — copied from Galleryze as-is
- [ ] `utils/tensor_utils.dart` — copied from Galleryze as-is
- [ ] `utils/string_utils.dart` — copied from Galleryze as-is (search history dedup uses `calculateSimilarity` extension)
- [ ] `widgets/glass_progress_popup.dart` — extracted from Galleryze's `lib/widgets/ui_kit.dart` as-is; used by `GalleryzeIndexButton` for the two-phase progress dialog
- [ ] `models/similar_group.dart` — copied from Galleryze as-is (needed by `CleanupProvider`)
- [ ] `providers/embedding_provider.dart` — new, extracted from old `PhotoProvider`
- [ ] `providers/indexing_provider.dart` — adapted, uses `AvesEntry` + new services
- [ ] `cleanup/cleanup_provider.dart` — adapted from Galleryze's `CleanupProvider` (new constructor, `_pruneStaleGroups` body — see §3.2)
- [ ] `view/search/galleryze_search_page.dart` — rebuilt in Aves style (search bar, history, results grid)
- [ ] `view/cleanup/smart_cleanup_page.dart` — rebuilt in Aves style (see §3.11); uses `ThumbnailProvider`, Aves native delete/viewer
- [ ] **Do NOT migrate `FavoriteProvider`** (`lib/providers/favorite_provider.dart`) — this is unused dead code in the current Galleryze; real favorites live in `PhotoProvider._metaIndex` → Aves `Favourites` SQLite (see §3.11)

**Provider wiring (`lib/widgets/aves_app.dart`)**
- [ ] `EmbeddingProvider` added to `MultiProvider` stack
- [ ] `IndexingProvider` added to `MultiProvider` stack, `CollectionSource` injected at construction
- [ ] `CleanupProvider` added to `MultiProvider` stack, receives `EmbeddingProvider` + `CollectionSource`
- [ ] Auto-index trigger wired: either `stateNotifier` listener or `_onAnalysisCompletion` hook

**Navigation — Search**
- [ ] `GalleryzeSearchPage.routeName` registered in `MaterialApp` routes
- [ ] Icon + label case added to `nav_bar.dart`
- [ ] `AvesNavItem(route: GalleryzeSearchPage.routeName)` added to `SettingsDefaults.bottomNavigationActions`
- [ ] `GalleryzeIndexButton` placed in `GalleryzeSearchPage` AppBar actions

**Navigation — Smart Cleanup**
- [ ] `SmartCleanupPage.routeName` registered in `MaterialApp` routes
- [ ] Link from `GalleryzeSearchPage` (e.g. AppBar badge showing duplicate count)

**Data & Migration**
- [ ] `GlrzPreferenceService` has only `saveSearchHistory`/`loadSearchHistory` with `glrz_search_history` key
- [ ] Sort and favorites preferences NOT ported (Aves handles both)
- [ ] Favorites one-time migration implemented and guarded by `glrz_favorites_migrated` flag
- [ ] `semanticSearch()` extracted into `EmbeddingProvider` — the weighted encoding and filter logic are **inline** in this one method (no separate helpers); only the final hydration step changes (PhotoItem → AvesEntry)

**Smart Cleanup specific**
- [ ] `_dbscanIsolate` function copied as-is to `lib/galleryze/cleanup/cleanup_provider.dart`
- [ ] `CleanupProvider` constructor uses `EmbeddingProvider` + `CollectionSource` (not `PhotoProvider`)
- [ ] `_pruneStaleGroups` uses `source.visibleEntries` for stale-entry check
- [ ] `CleanupProvider.runCleanup()` called after `IndexingProvider.autoIndex()` in `GalleryzeIndexButton`
- [ ] `SmartCleanupPage` converts `group.photoIds` (String) → `AvesEntry` via `source.getEntryById(int.parse(id))`
- [ ] Delete in `SmartCleanupPage` uses Aves' native delete action (look up in Aves' collection page source)
- [ ] After delete, `cleanup.removeGroup(groupId)` called to update UI
- [ ] `SimilarGroup` model copied to `lib/galleryze/models/similar_group.dart`

**Verification**
- [ ] `flutter build apk --debug --flavor play` passes with ORT added
- [ ] App launches, media loads, `source.stateNotifier` reaches `SourceState.ready`
- [ ] Indexing runs, `embeddings.bin` written to support dir
- [ ] Semantic search returns results with correct similarity scores
- [ ] Search thumbnails display via Aves `ThumbnailProvider` (not photo_manager)
- [ ] Tapping a search result opens Aves' native viewer (not a custom viewer)
- [ ] `GalleryzeIndexButton` runs index then cleanup sequentially
- [ ] `SmartCleanupPage` opens, DBSCAN groups show correct thumbnails via Aves `ThumbnailProvider`
- [ ] Smart cleanup delete removes files via Aves' native delete (handles Android 11+ trash)
- [ ] After deletion, group disappears from `SmartCleanupPage` via `removeGroup()`
- [ ] Existing `embeddings.bin` from old Galleryze loads correctly (ID compatibility check)
- [ ] Favorites migrated from `photo_metadata.json` on first launch

---

## Aves Architecture Quick Reference

Key facts to keep in mind throughout implementation:

### `AvesEntry` (from `plugins/aves_model/`)

| Field | Type | Notes |
|-------|------|-------|
| `id` | `int` | Android MediaStore `_ID` — same source as `photo_manager`'s `AssetEntity.id` |
| `mimeType` | `String` | e.g. `"image/jpeg"`, `"video/mp4"` |
| `sourceMimeType` | `final String` | Raw MediaStore value, immutable |
| `uri` | `String` | Content URI, e.g. `"content://media/external/images/media/123"` |
| `isVideo` | `bool` | **Extension getter** — import `aves_model/src/entry/extensions/props.dart` |
| `isImage` | `bool` | **Extension getter** — same import |
| `trashed` | `bool` | True for trash bin items |

### `CollectionSource` (from `lib/model/source/collection_source.dart`)

| API | Notes |
|-----|-------|
| `source.visibleEntries` | `Set<AvesEntry>` — excludes trash, excludes hidden filters. **Empty until `SourceState.ready`.** |
| `source.allEntries` | `Set<AvesEntry>` — everything including trash |
| `source.getEntryById(int id)` | `AvesEntry?` — O(1) lookup by MediaStore ID |
| `source.stateNotifier` | `ValueNotifier<SourceState>` — watch for `SourceState.ready` before indexing |
| `source.isReady` | `bool` — shorthand for `state == SourceState.ready` |
| **NOT a ChangeNotifier** | Use plain `Provider<CollectionSource>`, never `ChangeNotifierProvider` |

**`SourceState` enum** (`plugins/aves_model/lib/src/source/enums.dart`):
```dart
enum SourceState { loading, cataloguing, locatingCountries, locatingPlaces, ready }
```
Media is fully loaded and queryable only when `SourceState.ready`. Media loading is triggered from the home page (not app setup) — it won't be ready immediately at startup.

### Aves' Provider tree (`lib/widgets/aves_app.dart`)

```
MultiProvider (in _AvesAppState.build)
├── Provider<AppFlavor>
├── ChangeNotifierProvider<Settings>       ← SharedPrefs-backed settings
├── ListenableProvider<ValueNotifier<AppMode>>
├── Provider<CollectionSource>             ← MediaStoreSource (all media)
├── DurationsProvider
├── HighlightInfoProvider
├── ViewerEntryProvider
│
└── ← YOUR additions go here ──────────────────────────────
    ├── ChangeNotifierProvider<EmbeddingProvider>
    ├── ChangeNotifierProvider<IndexingProvider>
    └── ChangeNotifierProvider<CleanupProvider>
```

### Aves' Favourites system

```dart
// Access:
final favourites = context.read<Favourites>();  // ChangeNotifier in Aves' tree

// Check:
favourites.isFavourite(entry)  // bool

// Modify:
await favourites.add({entry});
await favourites.remove({entry});
```

Backed by SQLite (`localMediaDb`). Do NOT use SharedPreferences for favorites in the Aves version.

### File locations for Galleryze additions

```
lib/
└── galleryze/                   ← all Galleryze-specific code lives here
    ├── providers/
    │   ├── embedding_provider.dart     (new — extracted from old PhotoProvider)
    │   └── indexing_provider.dart      (adapted from old IndexingProvider)
    ├── services/
    │   ├── mobile_clip_service.dart    (copied as-is)
    │   └── ml_thumbnail_service.dart   (new — Dart side of thumbnail channel)
    ├── utils/
    │   ├── bpe_tokenizer.dart          (copied as-is)
    │   ├── tensor_utils.dart           (copied as-is)
    │   └── string_utils.dart           (copied as-is — needed for search history fuzzy dedup)
    ├── models/
    │   └── similar_group.dart          (copied as-is — needed by CleanupProvider)
    ├── view/
    │   └── search/
    │       └── galleryze_search_page.dart  (rebuilt in Aves style)
    └── cleanup/
        └── cleanup_provider.dart       (adapted DBSCAN, minimal changes)
android/app/src/main/kotlin/com/galleryze/app/
└── MlThumbnailChannel.kt               (new Kotlin — thumbnail bytes for ORT)
assets/
├── mobileclip_s0_fp32.onnx
├── text_encoder_fp32.onnx
├── vocab.json
└── merges.txt
```

---

## Keeping Up with Aves Updates

> **Honest assessment:** If you are significantly customizing Galleryze's UI (different layout, different navigation, different visual design), **do not do regular upstream merges**. Every Aves release touches `lib/view/`, `lib/theme/`, and `lib/widgets/` — exactly the files you will have diverged most. A full merge will create conflicts in dozens of files you've intentionally changed, and the resolution cost will exceed the value of the fixes.

### What IS worth pulling from upstream

Only two things in Aves are worth tracking once you've diverged the UI:

**1. Android platform compatibility** (`plugins/aves_model/`, `plugins/aves_video_exo/`)  
These plugins handle MediaStore, Android permissions, video playback, and new format support (RAW, HEIC, etc.). They get updated when Android itself changes. Falling behind here means broken media loading on new Android versions.

**2. Security / crash fixes** in the core media layer  
Watch the [Aves release notes](https://github.com/deckerst/aves/releases) for fixes to `MediaStoreSource`, `StorageService`, or permission handling. These are worth a targeted cherry-pick.

### How to get only what you need (cherry-pick, not merge)

```bash
git fetch upstream --tags

# See what changed in a specific release vs your current base
git log v1.x.x..v1.y.y --oneline -- plugins/

# Cherry-pick only the plugin commits you want
git cherry-pick <commit-sha>
```

**Do NOT run `git merge upstream/develop` or `git merge v1.x.x`** if you have custom UI. That will conflict on every screen and widget file you've touched.

### The one exception: `android/app/build.gradle.kts`

This file changes on every Aves release (NDK bumps, targetSdk, packaging rules) and has no UI code. It's worth watching. When Aves bumps it, manually apply just those changes — don't merge the whole file automatically.

Your two permanent additions to this file:
- `minSdkVersion 24` (ORT requirement — keep this even if Aves raises their floor)
- The `packagingOptions` block stripping redundant ORT provider libs

---

## Attribution (Required by BSD-3-Clause)

```
Galleryze is based on Aves by Thibault Deckers
https://github.com/deckerst/aves
Licensed under BSD-3-Clause
```

---

## Quick Reference: Strings to Replace

| Old | New |
|-----|-----|
| `deckers.thibault.aves` | `com.galleryze.app` |
| `deckers/thibault/aves` | `com/galleryze/app` |
| `package:aves/` | `package:galleryze/` |
| `name: aves` | `name: galleryze` |
| `"Aves"` (display name) | `"Galleryze"` |

---

## Effort Summary (Revised)

| Phase | Task | Days |
|-------|------|------|
| 1 | Fork, rename, remove submodule, replace firebase config, first build | 1–2 |
| 2 | UI reskin (colors, grid density, nav) — Aves UI only | 2–4 |
| 3 | `EmbeddingProvider` (new — extracted from PhotoProvider) | 1–2 |
| 3 | `IndexingProvider` adaptation (new source, new types, new storage) | 1–2 |
| 3 | `MlThumbnailChannel.kt` + `MlThumbnailService.dart` | 0.5 |
| 3 | `GalleryzeIndexButton` (replaces `IndexForSearchButton`) | 0.5 |
| 3 | Nav tab registration (route + AvesNavItem + SettingsDefaults) | 0.5–1 |
| 3 | `GalleryzeSearchPage` rebuilt in Aves style | 1–2 |
| 3 | `SmartCleanupPage` rebuilt in Aves style (uses Aves native viewer/delete) | 1–2 |
| 3 | `CleanupProvider` port (new constructor, `_pruneStaleGroups` body) | 0.5–1 |
| 3 | Favorites one-time migration from `photo_metadata.json` → Aves SQLite | 0.5 |
| 3 | Integration, testing, edge cases | 2–3 |
| **Total** | | **11–20 days** |

---

## What You Do NOT Need to Build

Aves already handles all of this — do not recreate it:

| Feature | Aves component |
|---------|----------------|
| Photo grid with smooth scrolling | `CollectionPage` + `EntryGrid` |
| Album/folder browser | `AlbumListPage` |
| Full-screen viewer with pinch-zoom | `EntryViewerPage` + `aves_magnifier` |
| Video playback | `aves_video_exo` (ExoPlayer) |
| Hero open/close animations | Built into `EntryViewerPage` |
| Selection mode + bulk share/delete | Built into `CollectionPage` |
| Favorites toggle | `Favourites` ChangeNotifier + SQLite |
| Permissions handling | Aves' native permission flow |
| Media change detection | `MediaStoreSource` EventBus |
| Light/dark/Material You theming | `Settings` + `DynamicColorBuilder` |
| EXIF metadata, GPS map | Aves' `InfoPage` |
