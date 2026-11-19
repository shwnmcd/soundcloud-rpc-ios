import Foundation

enum WebViewScripts {
    /// Port of soundcloud-rpc's audioMonitorService.js adapted for WKWebView + desktop/mobile SoundCloud DOM
    static let audioMonitorScript: String = """
    (function() {
      if (window.__soundCloudMonitorActive) return;
      window.__soundCloudMonitorActive = true;

      let isCurrentlyPlaying = false;
      let currentTrackTitle = '';
      let currentTrackAuthor = '';
      let currentTrackUrl = '';
      let currentTrackElapsed = '';
      let currentTrackDuration = '';
      let elapsedObserver = null;

      function extractBgUrl(el) {
        if (!el) return '';
        const bg = el.style && el.style.backgroundImage ? el.style.backgroundImage : getComputedStyle(el).backgroundImage;
        if (!bg || bg === 'none') return '';
        return bg.replace(/^url\\(['"]?|['"]?\\)$/g, '');
      }

      function getTrackInfo() {
        // Primary: Desktop SoundCloud web player selectors (exact match to soundcloud-rpc)
        const playButton = document.querySelector('.playControls__play');
        const authorEl = document.querySelector('.playbackSoundBadge__lightLink');
        const artworkEl = document.querySelector('.playbackSoundBadge__avatar .image__lightOutline span');
        const titleLinkEl = document.querySelector('.playbackSoundBadge__titleLink');
        const elapsedEl = document.querySelector('.playbackTimeline__timePassed span:last-child');
        const durationEl = document.querySelector('.playbackTimeline__duration span:last-child');

        if (playButton || titleLinkEl) {
          const isPlaying = playButton ? playButton.classList.contains('playing') : false;
          const titleAttr = artworkEl ? (artworkEl.getAttribute('aria-label') || '') : '';
          const titleFallback = titleLinkEl ? (titleLinkEl.getAttribute('title') || titleLinkEl.textContent || '').trim() : '';
          return {
            title: titleAttr || titleFallback,
            author: authorEl ? authorEl.textContent.trim() : '',
            artwork: extractBgUrl(artworkEl),
            elapsed: elapsedEl ? elapsedEl.textContent.trim() : '0:00',
            duration: durationEl ? durationEl.textContent.trim() : '0:00',
            isPlaying: isPlaying,
            url: titleLinkEl && titleLinkEl.href ? titleLinkEl.href.split('?')[0] : window.location.href.split('?')[0]
          };
        }

        // Fallback: MediaSession API / Mobile web DOM / active <audio> tag
        const ms = navigator.mediaSession && navigator.mediaSession.metadata;
        const audio = document.querySelector('audio');
        const formatSec = (s) => {
          if (!isFinite(s) || s < 0) return '0:00';
          const m = Math.floor(s / 60);
          const sec = Math.floor(s % 60);
          return m + ':' + String(sec).padStart(2, '0');
        };
        if (ms && ms.title) {
          const art = (ms.artwork && ms.artwork.length) ? ms.artwork[ms.artwork.length - 1].src : '';
          return {
            title: ms.title || '',
            author: ms.artist || '',
            artwork: art,
            elapsed: audio ? formatSec(audio.currentTime) : '0:00',
            duration: audio ? formatSec(audio.duration) : '0:00',
            isPlaying: audio ? !audio.paused : (navigator.mediaSession.playbackState === 'playing'),
            url: window.location.href.split('?')[0]
          };
        }

        return {
          title: '',
          author: '',
          artwork: '',
          elapsed: '0:00',
          duration: '0:00',
          isPlaying: false,
          url: ''
        };
      }

      function sendUpdate(info) {
        try {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.trackUpdate) {
            window.webkit.messageHandlers.trackUpdate.postMessage(info);
          }
        } catch (e) {}
      }

      function notifyPlaybackStateChange(force) {
        const trackInfo = getTrackInfo();
        const stateChanged = trackInfo.isPlaying !== isCurrentlyPlaying;
        const trackChanged =
          trackInfo.title !== currentTrackTitle ||
          trackInfo.author !== currentTrackAuthor ||
          trackInfo.url !== currentTrackUrl;
        const elapsedChanged = trackInfo.elapsed !== currentTrackElapsed;

        if (force || stateChanged || trackChanged || elapsedChanged || !window.__initialStateSent) {
          isCurrentlyPlaying = trackInfo.isPlaying;
          currentTrackTitle = trackInfo.title;
          currentTrackAuthor = trackInfo.author;
          currentTrackUrl = trackInfo.url;
          currentTrackElapsed = trackInfo.elapsed;
          currentTrackDuration = trackInfo.duration;
          window.__initialStateSent = true;
          sendUpdate(trackInfo);
        }
      }

      function attachObservers() {
        const playButton = document.querySelector('.playControls__play');
        if (playButton && !playButton.__scObserved) {
          playButton.__scObserved = true;
          new MutationObserver(() => notifyPlaybackStateChange(false)).observe(playButton, {
            attributes: true,
            attributeFilter: ['class']
          });
        }

        const elapsedEl = document.querySelector('.playbackTimeline__timePassed span:last-child');
        if (elapsedEl && !elapsedObserver) {
          elapsedObserver = new MutationObserver(() => notifyPlaybackStateChange(false));
          elapsedObserver.observe(elapsedEl.parentElement || elapsedEl, {
            childList: true,
            characterData: true,
            subtree: true
          });
        }
      }

      // Poll gently every 1s to keep elapsed time, Lock Screen & Last.fm synced even on SPA navigation
      setInterval(() => {
        attachObservers();
        notifyPlaybackStateChange(false);
      }, 1000);

      if (document.readyState === 'complete' || document.readyState === 'interactive') {
        attachObservers();
        notifyPlaybackStateChange(true);
      } else {
        document.addEventListener('DOMContentLoaded', () => {
          attachObservers();
          notifyPlaybackStateChange(true);
        });
      }
    })();
    """

    /// Generates JS to apply Dark Mode + Custom CSS Theme + optional AdBlocker cosmetic rules
    static func themeAndCosmeticScript(isDark: Bool, customCSS: String?, adBlockerEnabled: Bool) -> String {
        let escapedCustomCSS = jsTemplateEscape(customCSS ?? "")
        let adCosmeticCSS = adBlockerEnabled ? """
        .visualAd, .adOverlay, .audioAd, .promotedSound, .header__upsellWrapper,
        .l-product-banners, .sidebarModule__ad, .m-banner, .banner__ad,
        .goUpsellBanner, .upsellBanner, .mobileAppBanner, .appInstallBanner,
        .webBanner, .announcement, [data-testid="ad-banner"],
        li.soundList__item:has(.sc-promoted-icon) {
            display: none !important;
        }
        """ : ""
        let escapedAdCSS = jsTemplateEscape(adCosmeticCSS)

        return """
        (function() {
          try {
            const isDark = \(isDark ? "true" : "false");
            document.documentElement.classList.toggle('theme-light', !isDark);
            document.documentElement.classList.toggle('theme-dark', isDark);
            if (document.body) {
              document.body.classList.toggle('theme-light', !isDark);
              document.body.classList.toggle('theme-dark', isDark);
            }

            if (isDark) {
              document.documentElement.style.setProperty('--background-base', '#121212');
              document.documentElement.style.setProperty('--background-surface', '#212121');
              document.documentElement.style.setProperty('--text-base', '#ffffff');
            } else {
              document.documentElement.style.setProperty('--background-base', '#ffffff');
              document.documentElement.style.setProperty('--background-surface', '#f2f2f2');
              document.documentElement.style.setProperty('--text-base', '#333333');
            }

            function upsertStyle(id, css) {
              let el = document.getElementById(id);
              if (!css || !css.trim()) {
                if (el) el.remove();
                return;
              }
              if (!el) {
                el = document.createElement('style');
                el.id = id;
                (document.head || document.documentElement).appendChild(el);
              }
              el.textContent = css;
            }

            upsertStyle('sc-rpc-adblock-cosmetic', `\(escapedAdCSS)`);
            upsertStyle('sc-rpc-custom-theme', `\(escapedCustomCSS)`);
          } catch (e) {}
        })();
        """
    }

    /// Lightweight fetch/XHR guard for SoundCloud ad JSON endpoints when AdBlocker is enabled
    static let adBlockerRuntimeGuardScript: String = """
    (function() {
      if (window.__scRpcAdGuard) return;
      window.__scRpcAdGuard = true;
      const adRegex = /(api-v2\\.soundcloud\\.com\\/ads|promoted\\.soundcloud\\.com|eventlogger\\.soundcloud\\.com|doubleclick\\.net|googlesyndication\\.com|adswizz\\.com|imasdk\\.googleapis\\.com)/i;

      const origFetch = window.fetch;
      if (origFetch) {
        window.fetch = function(input, init) {
          const url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
          if (adRegex.test(url)) {
            return Promise.resolve(new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }));
          }
          return origFetch.apply(this, arguments);
        };
      }
    })();
    """

    static let togglePlayPauseJS = """
    (function(){
      const btn = document.querySelector('.playControls__play, .playControl');
      if (btn) { btn.click(); return; }
      const audio = document.querySelector('audio');
      if (audio) { audio.paused ? audio.play() : audio.pause(); }
    })();
    """

    static let nextTrackJS = """
    (function(){
      const btn = document.querySelector('.skipControl__next');
      if (btn) btn.click();
    })();
    """

    static let previousTrackJS = """
    (function(){
      const btn = document.querySelector('.skipControl__previous');
      if (btn) btn.click();
    })();
    """

    private static func jsTemplateEscape(_ str: String) -> String {
        str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "${", with: "\\${")
    }
}
