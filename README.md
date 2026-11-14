# NEEDLE: a Spotify vinyl player for iPhone

NEEDLE shows what Spotify is playing on a realistic spinning record. The vinyl's color is
generated from the album cover, and the controls drive the real Spotify app. It is native
Swift and SwiftUI (no WebView). The Spotify app keeps doing all the audio.

> ## Read this first: what is and isn't verified
>
> This project was written without access to a Mac, Xcode or an iPhone. **It has never been
> compiled, run, or tested on a device.** What *was* checked: the color-extraction algorithm
> (ported and run on the spec's example covers), the tonearm geometry (by calculation), and
> the Spotify SDK calls against Spotify's published docs. Expect that the first build may
> need a small fix. If it fails, the GitHub workflow uploads `build.log` so the exact
> compiler message is one click away.
>
> **There is no `.ipa` in this folder.** An IPA can only be produced by Xcode on macOS, and
> an installable one needs your Apple ID's signature. Below are two ways to get one.
> Nothing here claims a signed, ready-to-install IPA exists.

---

## Quick path: get an IPA without owning a Mac (GitHub Actions)

You need a free GitHub account, a Spotify account and a Windows/Mac/Linux computer for step 4.

1. **Register a Spotify app** (see [Spotify setup](#spotify-setup)). Copy its **Client ID**.
2. **Create a GitHub repository** (private is fine) and upload the *contents* of this folder
   so that `project.yml` sits at the repository root.
3. In the repo go to **Settings → Secrets and variables → Actions**:
   - *Secrets* tab → **New repository secret** → name `SPOTIFY_CLIENT_ID`, value = your Client ID.
   - *Variables* tab → **New repository variable** → name `NEEDLE_BUNDLE_ID`,
     value = something unique to you, e.g. `com.yourname.needle`. Use the same value in the Spotify dashboard.
4. Open **Actions → Build unsigned IPA → Run workflow**. After about 10–15 minutes, download the
   artifact **Needle-unsigned-ipa** (a zip containing `Needle-unsigned.ipa`).
   (GitHub bills macOS runner minutes at a higher rate on private repos; check your free allowance.)
5. [Sideload it](#sideload-onto-your-iphone-14).

If the build fails, open the run, download the **build-log** artifact and fix or report the
first `error:` line.

## Alternative: build on a Mac with Xcode

```bash
brew install xcodegen
cp Config/Local.xcconfig.example Config/Local.xcconfig   # then edit: your Client ID + bundle id
xcodegen generate
open Needle.xcodeproj
```

In Xcode choose the **Needle** target → *Signing & Capabilities* → pick your **Team**
(a free Apple ID works), select your iPhone, press **Run**. Xcode will fetch the Spotify SDK
through Swift Package Manager (`https://github.com/spotify/ios-sdk`, 5.0.1 or later).

To make an unsigned IPA from the command line (same as the workflow):

```bash
xcodebuild -project Needle.xcodeproj -scheme Needle -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
mkdir -p Payload && cp -R build/Build/Products/Release-iphoneos/Needle.app Payload/
zip -qry Needle-unsigned.ipa Payload
```

For a **signed** IPA with a paid Apple Developer account, use *Product → Archive → Distribute App*.

---

## Spotify setup

1. Go to <https://developer.spotify.com/dashboard> and **Create app**.
2. Tick **iOS** (App Remote / SDK) and **Web API** when asked which APIs you will use.
3. **Redirect URIs:** add exactly `needle-spotify://spotify-login-callback`
4. **iOS Bundle IDs:** add your bundle id (the value of `NEEDLE_BUNDLE_ID`). If you sideload with a
   tool that rewrites the bundle id, add the rewritten one too; see the next section.
5. Copy the **Client ID**. There is **no client secret** in this app and none is needed.
6. Apps start in **Development Mode**: add the Spotify account(s) you will use under **User Management**.
   Spotify's rules for development-mode apps change over time, so check the dashboard.

Scopes requested: `app-remote-control` only.

## Sideload onto your iPhone 14

1. On the iPhone: **Settings → Privacy & Security → Developer Mode → On** (it restarts the phone).
2. Install with one of: **Sideloadly** (Windows/macOS), **AltStore** or **SideStore**. Give it
   `Needle-unsigned.ipa` and your Apple ID. These tools re-sign the app for your device.
3. **Settings → General → VPN & Device Management** → trust your Apple ID profile.
4. Free Apple IDs expire after **7 days** (AltStore/SideStore can refresh automatically), and
   allow only a few sideloaded apps at once.

**Bundle-id gotcha:** with a free Apple ID, sideloading tools may change the bundle id (for example by
appending your team id). Spotify checks the bundle id during sign-in, so if "Connect Spotify" fails,
look up the bundle id the tool actually used and add it under *iOS Bundle IDs* in the Spotify dashboard.
(Sideloadly lets you set it before installing.)

## Using NEEDLE

1. Open NEEDLE → **Connect Spotify**. It switches to the Spotify app to approve, then comes back.
2. **Start playing something in Spotify first.** Spotify's SDK needs the Spotify app to be awake in
   the background; if NEEDLE says it can't reach Spotify, press play in Spotify and tap **Reconnect**.
3. NEEDLE shows the track, spins the record, and its controls send real commands to Spotify.
4. The sign-in lasts about an hour. After that, tap **Sign in again** (a quick hop to Spotify).
   Silent refresh needs a small backend, which this app deliberately doesn't include.

Premium: Spotify only allows picking a specific song/album on demand (the Search sheet) and some
controls for Premium accounts. NEEDLE shows Spotify's refusal message instead of pretending it worked.

---

## What's in the project

```
project.yml                XcodeGen spec (generates Needle.xcodeproj; targets iOS 16+, arm64)
Config/                    xcconfig files: Client ID and bundle id live here, never in code
.github/workflows/         build-ipa.yml (unsigned IPA), tests.yml (manual test run)
Tools/make_icon.py         generates the original app icon
Needle/
  App/                     NeedleApp, AppContainer (dependency wiring)
  Models/                  playback, connection, vinyl, settings, color models; ColorExtractor + PaletteBuilder
  Services/                SpotifyService (OAuth + App Remote), SpotifyWebAPI, ArtworkService,
                           ColorPaletteService (+cache), KeychainStore, PersistenceService, NetworkMonitor
  ViewModels/              PlaybackViewModel, SettingsViewModel, SearchViewModel
  Vinyl/                   VinylPainter (grooves, finishes, sheen), VinylDiscView + SpinDriver,
                           TonearmView, TurntableView (plinth, platter, spindle)
  Views/                   Player, Onboarding, Settings, Search, Connection panel, header, controls
NeedleTests/               unit tests (color extraction, palette cache, playback state, settings, spin)
NeedleUITests/             UI tests (onboarding, empty state, player, error recovery)
```

How the main requirements are met:

- **Album-adaptive color:** `ColorExtractor` downsamples to 64×64, ignores transparent pixels, down-weights
  near-white/near-black/neutral pixels, clusters in a perceptual color space, ranks by prominence ×
  saturation × suitability, and is fully deterministic. Palettes are cached on disk by album+image id.
- **Five vinyl styles:** Solid, Two-tone, Multicolor, Classic black, Translucent. All are drawn as vectors
  in `VinylPainter`; switching style or color crossfades and never touches Spotify playback.
- **Rotation:** the record is rasterized once and a single transform spins it (one turn per 1.8 s, linear,
  with spin-up/spin-down). The loop only runs while spinning. Reduce Motion replaces it with a static "Playing" badge.
- **Truthful state:** the UI renders only Spotify-reported state. Shuffle/repeat show a spinner until Spotify
  confirms; rejected commands show Spotify's reason; nothing fakes progress or connection.
- **No endless spinners:** connecting and signing in have watchdog timeouts that end in a recoverable state.
- **Security:** no secret in the bundle; token in the Keychain; Client ID injected at build time.
- **Test double:** `ScriptedSpotifyService` is `#if DEBUG` only, so a Release IPA cannot show scripted data.

## Known limits and deliberate deviations from the brief

- **Single artist:** Spotify's App Remote reports one primary artist per track, so that's what is shown.
- **Hourly sign-in** (see above) because there is no token-refresh backend.
- **Generic Spotify glyph** in the header pill. If you publish the app, replace it with Spotify's official
  logo asset and follow their brand guidelines. NEEDLE is not affiliated with Spotify.
- **Always dark:** the identity is a dark turntable, so the app forces dark mode.
- **Spotify terms review (brief §3.10):** the record is a UI animation that reflects play/pause state. It
  does not analyze or react to audio and uses no audio extraction. Still read the current
  Spotify Developer Terms before any public release.
- **Spotify's SDK:** pulled via Swift Package Manager at build time and covered by Spotify's own license
  and developer terms; it is not redistributed in this repo.

## Acceptance checklist (needs a real iPhone and Spotify account)

| # | Test | Status |
|---|------|--------|
| 1 | First launch shows onboarding | UI test written, **not run** |
| 2 | Spotify authorization round trip | **needs your device** |
| 3 | Already-playing song is picked up | **needs your device** |
| 4 | Record renders (grooves, label, spindle, spin) | **needs your device** (visual) |
| 5 | Colors differ sensibly per album | algorithm checked offline; **visual check on device** |
| 6 | Track change updates art, text, palette | view-model unit test written, **not run**; confirm on device |
| 7 | Play/pause/skip/seek/shuffle/repeat | unit tests written, **not run**; confirm on device |
| 8 | Pause/resume without jumps | spin-driver unit test written, **not run** |
| 9 | Bad artwork → placeholder | unit test written, **not run** |
| 10 | Connection loss → reconnect | UI test written, **not run**; confirm on device |
| 11 | Settings persist | unit tests written, **not run** |
| 12 | Real-device performance/battery | **needs your device** |
| 13 | IPA export | workflow provided, **not run** |

Run the automated tests from GitHub (**Actions → Unit and UI tests (manual)**) or in Xcode (⌘U).

## Troubleshooting

- **"NEEDLE needs a Spotify Client ID":** the build had no `SPOTIFY_CLIENT_ID`. Set the secret / `Local.xcconfig` and rebuild.
- **Sign-in screen errors or loops:** check the redirect URI string and the bundle id in the Spotify dashboard.
- **"Couldn't reach the Spotify app":** start playback in Spotify, then tap Reconnect.
- **Control does nothing / red message:** Spotify refused it (ads, free tier, restricted context). The message says so.
- **No artwork:** a clearly different placeholder label appears; the rest of the player keeps working.
