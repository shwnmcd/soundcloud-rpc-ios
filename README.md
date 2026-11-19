# SoundCloud RPC — iPhone, iPad & Browser Edition

A recreation of [`richardhbtz/soundcloud-rpc`](https://github.com/richardhbtz/soundcloud-rpc) (MIT) rebuilt in three synchronized targets so you can use SoundCloud with an **AdBlocker, Dark Mode, Custom CSS Themes, JS Plugins, Last.fm Scrobbling, Webhooks, Smart Track Parser, and Discord Rich Presence Preview** across **iPhone, iPad, and Desktop Browsers**:

| Target | Folder | What it does |
| --- | --- | --- |
| **Native iPhone & iPad App** | `ios/` | SwiftUI + `WKWebView` app wrapping `soundcloud.com` with Apple-native **`WKContentRuleList` AdBlocker**, background audio, Lock Screen / AirPods controls, Dark Mode, Custom CSS Themes, JS Plugins, Last.fm Scrobbling, Webhooks, and Discord RPC Preview + optional PC Relay. |
| **Browser Extension (MV3)** | `extension/` | Load directly into Chrome / Edge / Brave on Windows for real network-level **`declarativeNetRequest` AdBlocking**, Dark Mode, Custom CSS, Track Parser & Webhooks right on `https://soundcloud.com`. |
| **Browser Web Companion / PWA** | `web/` | Zero-build HTML/JS PWA with embedded SoundCloud Widget player, live Discord Rich Presence preview, Track Parser tester, Last.fm Scrobbler, Webhook tester, Custom CSS Theme studio, and AdBlock rules exporter. |

---

## 1. Install on iPhone & iPad via AltStore (No Mac Needed!)

This repo includes a ready-to-run **GitHub Actions workflow** (`.github/workflows/build-ios.yml`) that compiles `SoundCloudRPC.ipa` on GitHub's free macOS cloud runner.

1. Create a new repository on [GitHub](https://github.com/new) (public or private) and upload this folder (`soundcloud-rpc-ios`).
2. Open your repository on GitHub → click the **Actions** tab → click **Build iOS & iPadOS IPA** → click **Run workflow**.
3. Wait ~3–4 minutes for the macOS build to finish.
4. Click the completed run → under **Artifacts**, download **`SoundCloudRPC-iOS-IPA`** and unzip it to get **`SoundCloudRPC.ipa`**.
5. Transfer `SoundCloudRPC.ipa` to your iPhone/iPad (iCloud Drive, Files, Google Drive, or USB) → open **AltStore** → **My Apps** → tap **`+`** → select **`SoundCloudRPC.ipa`**.

### iPhone & iPad Features Included
- **Built-in AdBlocker:** Uses Apple's native `WKContentRuleListStore` + cosmetic hiding + runtime ad-endpoint guard (toggleable in Settings).
- **Background Audio & Lock Screen Controls:** Keeps playing with the screen locked and integrates with Control Center / Lock Screen / AirPods (`AVAudioSession` + `MPNowPlayingInfoCenter`).
- **Desktop / Mobile Web Mode Toggle:** Desktop mode loads the full SoundCloud web player (waveforms, bottom playback bar, full track monitoring); switch to Mobile mode anytime in Settings.
- **Last.fm Scrobbling:** Enter your Last.fm API Key & Secret in Settings and tap **Authenticate with Last.fm** — the OAuth callback is intercepted automatically inside the app.
- **Webhooks & Discord Embeds:** Fires at your chosen playback percentage (0–100%) using either the original `soundcloud-rpc` JSON payload or native Discord Webhook embeds.
- **Custom Themes (`.css`) & Plugins (`.js`):** Create, edit, or import `.css` / `.js` files right from the iOS **Files** app (also accessible under *On My iPhone/iPad → SoundCloud RPC*).

---

## 2. Run in Your Desktop Browser Right Now (Chrome / Edge / Brave)

### A. Real AdBlocker & Dark Mode directly on `soundcloud.com` (Extension)
1. Open Chrome, Edge, or Brave and go to `chrome://extensions` (or `edge://extensions`).
2. Turn on **Developer mode** (top right).
3. Click **Load unpacked** and select the **`extension`** folder inside this project.
4. Open [https://soundcloud.com](https://soundcloud.com) — AdBlocker, Dark Mode, Track Parser, Custom CSS, and Webhooks are active immediately! Click the extension icon in your toolbar to toggle settings or configure Webhooks.

### B. Web Companion / PWA (`web/`)
Run our zero-dependency PowerShell server right from Windows:
```powershell
powershell -ExecutionPolicy Bypass -File .\serve-web.ps1
```
Then open **[http://localhost:8080](http://localhost:8080)** in your browser!
*(You can also deploy `web/` to GitHub Pages or Netlify and tap **Share → Add to Home Screen** on iPhone/iPad to install it as a PWA.)*
