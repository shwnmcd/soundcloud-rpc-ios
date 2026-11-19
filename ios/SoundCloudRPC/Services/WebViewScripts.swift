import Foundation

enum WebViewScripts {
    /// Port of soundcloud-rpc's audioMonitorService.js adapted for WKWebView + Like/Shuffle/Repeat state
    static let audioMonitorScript: String = """
    (function() {
      if (window.__soundCloudMonitorActive) return;
      window.__soundCloudMonitorActive = true;

      let lastSig = '';
      let elapsedObserver = null;

      function extractBgUrl(el) {
        if (!el) return '';
        const bg = el.style && el.style.backgroundImage ? el.style.backgroundImage : getComputedStyle(el).backgroundImage;
        if (!bg || bg === 'none') return '';
        return bg.replace(/^url\\(['"]?|['"]?\\)$/g, '');
      }

      function getTrackInfo() {
        const playButton = document.querySelector('.playControls__play');
        const authorEl = document.querySelector('.playbackSoundBadge__lightLink');
        const artworkEl = document.querySelector('.playbackSoundBadge__avatar .image__lightOutline span');
        const titleLinkEl = document.querySelector('.playbackSoundBadge__titleLink');
        const elapsedEl = document.querySelector('.playbackTimeline__timePassed span:last-child');
        const durationEl = document.querySelector('.playbackTimeline__duration span:last-child');
        const likeBtn = document.querySelector('.playbackSoundBadge__like');
        const shuffleBtn = document.querySelector('.shuffleControl');
        const repeatBtn = document.querySelector('.repeatControl');

        let repeatMode = 'none';
        if (repeatBtn) {
          if (repeatBtn.classList.contains('m-one')) repeatMode = 'one';
          else if (repeatBtn.classList.contains('m-all')) repeatMode = 'all';
        }

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
            url: titleLinkEl && titleLinkEl.href ? titleLinkEl.href.split('?')[0] : window.location.href.split('?')[0],
            isLiked: likeBtn ? likeBtn.classList.contains('sc-button-selected') : false,
            isShuffling: shuffleBtn ? shuffleBtn.classList.contains('m-shuffling') : false,
            repeatMode: repeatMode
          };
        }

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
            url: window.location.href.split('?')[0],
            isLiked: false,
            isShuffling: false,
            repeatMode: 'none'
          };
        }

        return {
          title: '',
          author: '',
          artwork: '',
          elapsed: '0:00',
          duration: '0:00',
          isPlaying: false,
          url: '',
          isLiked: false,
          isShuffling: false,
          repeatMode: 'none'
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
        const sig = JSON.stringify(trackInfo);
        if (force || sig !== lastSig) {
          lastSig = sig;
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

      setInterval(() => {
        attachObservers();
        notifyPlaybackStateChange(false);
      }, 800);

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

    /// Deep 4-layer Audio Ad Blocker injected at document-start
    static let adBlockerRuntimeGuardScript: String = """
    (function() {
      if (window.__scRpcAdGuardV2) return;
      window.__scRpcAdGuardV2 = true;

      const AD_URL_REGEX = /(api-v2\\.soundcloud\\.com\\/.*\\b(ads|audio[_-]?ads|ad[_-]?errors|vast|promoted|sponsored)\\b|api\\.soundcloud\\.com\\/ads|promoted\\.soundcloud\\.com|eventlogger\\.soundcloud\\.com|events\\.soundcloud\\.com|log\\.soundcloud\\.com|wis\\.sndcdn\\.com|doubleclick\\.net|googlesyndication\\.com|googleadservices\\.com|imasdk\\.googleapis\\.com|adswizz\\.com|sxmmedia\\.com|siriusxm\\.com|tritondigital\\.com|dax-ads\\.io|dax\\.global\\.com|instreamatic\\.com|targetspot\\.com|2mdn\\.net|innovid\\.com|flashtalking\\.com|magnite\\.com|rubiconproject\\.com|pubmatic\\.com|openx\\.net|adnxs\\.com|amazon-adsystem\\.com|criteo\\.|adsrvr\\.org|moatads\\.com|doubleverify\\.com|adsafeprotected\\.com|iasds01\\.com|scorecardresearch\\.com|quantserve\\.com|outbrain\\.com|taboola\\.com|audio[_-]?ad)/i;

      function notifyAdBlocked(reason) {
        try {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.adBlocked) {
            window.webkit.messageHandlers.adBlocked.postMessage({ reason: reason });
          }
        } catch (e) {}
      }

      function emptyResponseBodyFor(url) {
        if (/vast|xml/i.test(url)) {
          return { body: '<VAST version="3.0"></VAST>', type: 'application/xml' };
        }
        return { body: '{"collection":[],"ads":[],"audio_ads":[],"visual_ads":[]}', type: 'application/json' };
      }

      // Layer 2A: Intercept window.fetch
      const origFetch = window.fetch;
      if (origFetch) {
        window.fetch = function(input, init) {
          const url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
          if (url && AD_URL_REGEX.test(url)) {
            notifyAdBlocked('fetch');
            const mock = emptyResponseBodyFor(url);
            return Promise.resolve(new Response(mock.body, {
              status: 200,
              headers: { 'Content-Type': mock.type }
            }));
          }
          return origFetch.apply(this, arguments);
        };
      }

      // Layer 2B: Intercept XMLHttpRequest
      const origOpen = XMLHttpRequest.prototype.open;
      const origSend = XMLHttpRequest.prototype.send;

      XMLHttpRequest.prototype.open = function(method, url) {
        this.__scRpcUrl = typeof url === 'string' ? url : String(url || '');
        return origOpen.apply(this, arguments);
      };

      XMLHttpRequest.prototype.send = function(body) {
        const url = this.__scRpcUrl || '';
        if (url && AD_URL_REGEX.test(url)) {
          notifyAdBlocked('xhr');
          const mock = emptyResponseBodyFor(url);
          const xhr = this;
          try {
            Object.defineProperty(xhr, 'readyState', { configurable: true, value: 4 });
            Object.defineProperty(xhr, 'status', { configurable: true, value: 200 });
            Object.defineProperty(xhr, 'statusText', { configurable: true, value: 'OK' });
            Object.defineProperty(xhr, 'responseText', { configurable: true, value: mock.body });
            Object.defineProperty(xhr, 'response', { configurable: true, value: mock.body });
          } catch (e) {}
          setTimeout(() => {
            try {
              if (typeof xhr.onreadystatechange === 'function') xhr.onreadystatechange();
              if (typeof xhr.onload === 'function') xhr.onload();
              xhr.dispatchEvent(new Event('readystatechange'));
              xhr.dispatchEvent(new Event('load'));
              xhr.dispatchEvent(new Event('loadend'));
            } catch (e) {}
          }, 0);
          return;
        }
        return origSend.apply(this, arguments);
      };

      // Layer 3: Active Audio-Ad Failsafe Monitor
      let savedVolume = 1.0;
      let mutingAd = false;

      function isAudioAdPlaying() {
        if (document.querySelector('.audioAd, .visualAd, .adOverlay, .adCountdown, .playControls__ad, .m-isAd, [class*="audioAd"], [data-testid="audio-ad"]')) {
          return true;
        }
        const badge = document.querySelector('.playbackSoundBadge');
        if (badge) {
          const text = (badge.textContent || '').toLowerCase();
          if (text.includes('advertisement') || text.includes('why this ad') || text.includes('sponsored')) {
            return true;
          }
        }
        const skipBtn = document.querySelector('.skipControl__next');
        const playBtn = document.querySelector('.playControls__play');
        const titleLink = document.querySelector('.playbackSoundBadge__titleLink');
        if (playBtn && playBtn.classList.contains('playing') && skipBtn && skipBtn.disabled && !titleLink) {
          return true;
        }
        return false;
      }

      setInterval(() => {
        try {
          const adActive = isAudioAdPlaying();
          const audios = document.querySelectorAll('audio, video');

          if (adActive) {
            if (!mutingAd) {
              mutingAd = true;
              notifyAdBlocked('audio-skip');
            }
            audios.forEach((media) => {
              if (!media.muted) {
                savedVolume = media.volume || 1.0;
                media.muted = true;
              }
              if (isFinite(media.duration) && media.duration > 0 && media.currentTime < media.duration - 0.2) {
                media.currentTime = media.duration;
              }
              try { media.playbackRate = 16.0; } catch (e) {}
            });
            const skipAdBtn = document.querySelector('.adOverlay__close, .audioAd__skip, [class*="skipAd"]');
            if (skipAdBtn) skipAdBtn.click();
          } else if (mutingAd) {
            mutingAd = false;
            audios.forEach((media) => {
              media.muted = false;
              media.volume = savedVolume;
              try { media.playbackRate = 1.0; } catch (e) {}
            });
          }
        } catch (e) {}
      }, 250);
    })();
    """

    /// Generates JS to apply Dark Mode, Sleek Spotify-inspired Mobile/iPad App CSS, AdBlocker cosmetics, and Custom CSS
    static func themeAndCosmeticScript(
        isDark: Bool,
        mobileAppLayout: Bool,
        customCSS: String?,
        adBlockerEnabled: Bool
    ) -> String {
        let escapedCustomCSS = jsTemplateEscape(customCSS ?? "")

        let adCosmeticCSS = adBlockerEnabled ? """
        .visualAd, .adOverlay, .audioAd, .promotedSound, .header__upsellWrapper,
        .l-product-banners, .sidebarModule__ad, .m-banner, .banner__ad,
        .goUpsellBanner, .upsellBanner, .mobileAppBanner, .appInstallBanner,
        .webBanner, .announcement, .adCountdown, .playControls__ad,
        .header__proUpsell, .l-footer, .mobileApps, .creatorSubscriptionsUpsell,
        .l-footer-mini, .footer, .sidebarHeader__actualTitle[href*="go"],
        [data-testid="ad-banner"], [class*="upsell"], [class*="AdSlot"],
        li.soundList__item:has(.sc-promoted-icon) {
            display: none !important;
        }
        """ : ""

        let mobileLayoutCSS = mobileAppLayout ? """
        /* === Sleek Spotify-Inspired iPhone & iPad Native App Styling === */
        html, body {
            max-width: 100vw !important;
            overflow-x: hidden !important;
            -webkit-overflow-scrolling: touch !important;
            padding-top: 0 !important;
            padding-bottom: 140px !important;
            background-color: var(--background-base, #121212) !important;
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", sans-serif !important;
        }

        /* Hide SoundCloud's desktop website chrome (replaced by native SwiftUI header, chips & tab bar) */
        header.header,
        .header,
        .announcements,
        .collection__nav,
        .collectionNav,
        .g-tabs-large,
        .searchTitle,
        .searchOptions,
        .search .l-sidebar-left,
        .tileGallery__sliderButton,
        .playableTile__actions,
        .l-product-banners {
            display: none !important;
        }

        /* Keep playControls mounted off-screen so Play/Pause/Next/Like/Seek stay 100% functional */
        .playControls {
            position: fixed !important;
            left: -9999px !important;
            bottom: 0 !important;
            width: 100vw !important;
            opacity: 0 !important;
            pointer-events: none !important;
            z-index: -1 !important;
        }

        /* Collapse fixed 1240px desktop containers to clean full-width app canvas */
        #app,
        .l-container,
        .l-container.l-content,
        .l-fluid-fixed,
        .l-three-column,
        .l-two-column,
        .l-main,
        .l-front,
        .l-listen-wrapper,
        .l-listen-hero,
        .l-listen-engagement,
        .listenDetails,
        .search,
        .search__results,
        .collection,
        .collectionSection,
        .stream,
        .userNetwork,
        .profileHeader {
            width: 100% !important;
            min-width: 0 !important;
            max-width: 100vw !important;
            margin-left: 0 !important;
            margin-right: 0 !important;
            box-sizing: border-box !important;
            background: transparent !important;
        }

        .l-container.l-content {
            padding: 8px 14px 150px 14px !important;
        }

        .l-fluid-fixed .l-main,
        .l-three-column .l-main,
        .l-two-column .l-main,
        .search .l-main {
            float: none !important;
            width: 100% !important;
            margin: 0 !important;
            padding: 0 !important;
            border: none !important;
        }

        /* Hide cluttered sidebar promos on Home/Search; stack gracefully on track detail pages */
        .l-front .l-sidebar-right,
        .stream .l-sidebar-right {
            display: none !important;
        }
        .l-sidebar-right {
            position: static !important;
            float: none !important;
            width: 100% !important;
            margin: 22px 0 0 0 !important;
            padding: 16px 0 0 0 !important;
            border-top: 1px solid rgba(255,255,255,0.08) !important;
        }

        /* === BIG, SLEEK SPOTIFY-STYLE HORIZONTAL CAROUSEL CARDS ON HOME === */
        .mixedSelectionModule,
        .collectionSection {
            margin-bottom: 24px !important;
            border: none !important;
            padding: 0 !important;
        }
        .mixedSelectionModule__titleText,
        .collectionSection__heading {
            font-size: 21px !important;
            font-weight: 700 !important;
            letter-spacing: -0.3px !important;
            margin-bottom: 12px !important;
        }
        .tileGallery__sliderPanel {
            overflow-x: auto !important;
            overflow-y: hidden !important;
            -webkit-overflow-scrolling: touch !important;
            scrollbar-width: none !important;
            padding-bottom: 4px !important;
        }
        .tileGallery__sliderPanel::-webkit-scrollbar {
            display: none !important;
        }
        .tileGallery__sliderPanelSlide {
            display: flex !important;
            flex-wrap: nowrap !important;
            gap: 14px !important;
            width: max-content !important;
            transform: none !important;
        }
        .tileGallery__slide {
            flex: 0 0 154px !important;
            width: 154px !important;
            min-width: 154px !important;
            max-width: 154px !important;
            padding: 0 !important;
            margin: 0 !important;
        }
        .tileGallery__slide .playableTile,
        .tileGallery__slide .playableTile__artwork,
        .tileGallery__slide .playableTile__artworkLink,
        .tileGallery__slide .image {
            width: 154px !important;
            height: auto !important;
        }
        .tileGallery__slide .playableTile__artwork {
            width: 154px !important;
            height: 154px !important;
            border-radius: 10px !important;
            overflow: hidden !important;
            box-shadow: 0 6px 18px rgba(0,0,0,0.35) !important;
        }
        .playableTile__artwork .image__full {
            width: 100% !important;
            height: 100% !important;
            border-radius: 10px !important;
        }
        .playableTile__description {
            margin-top: 8px !important;
        }
        .playableTile__heading {
            font-size: 13.5px !important;
            font-weight: 600 !important;
            line-height: 1.3 !important;
            white-space: nowrap !important;
            overflow: hidden !important;
            text-overflow: ellipsis !important;
        }
        .playableTile__usernameHeading {
            font-size: 12px !important;
            opacity: 0.68 !important;
            margin-top: 2px !important;
        }

        /* === CLEAN 2-COLUMN (iPhone) / 4-COLUMN (iPad) LIBRARY GRID === */
        .badgeList,
        .lazyLoadingList__list {
            display: grid !important;
            grid-template-columns: repeat(2, minmax(0, 1fr)) !important;
            gap: 14px !important;
            width: 100% !important;
        }
        @media (min-width: 700px) {
            .badgeList,
            .lazyLoadingList__list {
                grid-template-columns: repeat(4, minmax(0, 1fr)) !important;
            }
            .tileGallery__slide,
            .tileGallery__slide .playableTile,
            .tileGallery__slide .playableTile__artwork {
                flex: 0 0 180px !important;
                width: 180px !important;
                min-width: 180px !important;
            }
            .tileGallery__slide .playableTile__artwork {
                height: 180px !important;
            }
        }
        /* Keep vertical track lists & search results single-column */
        .searchList .lazyLoadingList__list,
        .stream .lazyLoadingList__list,
        .soundList.lazyLoadingList__list,
        .trackList__list {
            display: flex !important;
            flex-direction: column !important;
            gap: 10px !important;
        }
        .badgeList__item {
            width: 100% !important;
            margin: 0 !important;
            padding: 0 !important;
        }
        .badgeList__item .playableTile__artwork,
        .badgeList__item .image {
            width: 100% !important;
            aspect-ratio: 1 / 1 !important;
            height: auto !important;
            border-radius: 10px !important;
            overflow: hidden !important;
        }
        /* Tone down SoundCloud's huge blocky white square pause overlay on thumbnails */
        .playableTile__playButton .sc-button-play {
            border-radius: 50% !important;
            transform: scale(0.78) !important;
            box-shadow: 0 4px 12px rgba(0,0,0,0.4) !important;
        }

        /* === SLEEK TRACK / PLAYLIST DETAIL HERO === */
        .fullListenHero,
        .fullHero {
            height: auto !important;
            min-height: 220px !important;
            padding: 18px 16px !important;
            border-radius: 16px !important;
            overflow: hidden !important;
            margin-bottom: 14px !important;
        }
        .fullHero__foreground {
            position: relative !important;
            display: flex !important;
            flex-direction: column !important;
            gap: 14px !important;
            padding: 0 !important;
        }
        .fullHero__artwork {
            position: relative !important;
            width: 185px !important;
            height: 185px !important;
            margin: 0 auto !important;
            border-radius: 12px !important;
            overflow: hidden !important;
            box-shadow: 0 10px 28px rgba(0,0,0,0.45) !important;
        }
        .fullHero__title,
        .fullHero__playerArea {
            position: relative !important;
            width: 100% !important;
            left: 0 !important;
            right: 0 !important;
            bottom: 0 !important;
            margin: 0 !important;
        }

        /* === CLEAN TRACK ROWS & FEED CARDS === */
        .soundList__item {
            border-bottom: 1px solid rgba(255,255,255,0.06) !important;
            padding: 10px 0 !important;
            margin: 0 !important;
        }
        .sound__body {
            display: flex !important;
            flex-direction: column !important;
            gap: 8px !important;
        }
        .sound__coverArt {
            width: 68px !important;
            height: 68px !important;
            border-radius: 8px !important;
            overflow: hidden !important;
        }
        .soundTitle__title {
            font-size: 15px !important;
            font-weight: 600 !important;
            line-height: 1.3 !important;
            white-space: normal !important;
        }
        .soundActions .sc-button-group {
            flex-wrap: wrap !important;
            gap: 6px !important;
        }
        .sc-button {
            border-radius: 999px !important;
        }

        /* Clean empty search prompt */
        .searchList__empty {
            padding: 40px 16px !important;
            text-align: center !important;
            opacity: 0.7 !important;
        }

        input, textarea, select {
            font-size: 16px !important;
        }
        """ : ""

        let escapedAdCSS = jsTemplateEscape(adCosmeticCSS)
        let escapedMobileCSS = jsTemplateEscape(mobileLayoutCSS)

        return """
        (function() {
          try {
            if (\(mobileAppLayout ? "true" : "false")) {
              let vp = document.querySelector('meta[name="viewport"]');
              if (!vp) {
                vp = document.createElement('meta');
                vp.name = 'viewport';
                (document.head || document.documentElement).appendChild(vp);
              }
              vp.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover';
            }

            const isDark = \(isDark ? "true" : "false");
            document.documentElement.classList.toggle('theme-light', !isDark);
            document.documentElement.classList.toggle('theme-dark', isDark);
            if (document.body) {
              document.body.classList.toggle('theme-light', !isDark);
              document.body.classList.toggle('theme-dark', isDark);
            }

            if (isDark) {
              document.documentElement.style.setProperty('--background-base', '#121212');
              document.documentElement.style.setProperty('--background-surface', '#1c1c1e');
              document.documentElement.style.setProperty('--text-base', '#ffffff');
            } else {
              document.documentElement.style.setProperty('--background-base', '#ffffff');
              document.documentElement.style.setProperty('--background-surface', '#f2f2f7');
              document.documentElement.style.setProperty('--text-base', '#1c1c1e');
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
            upsertStyle('sc-rpc-mobile-layout', `\(escapedMobileCSS)`);
            upsertStyle('sc-rpc-custom-theme', `\(escapedCustomCSS)`);
          } catch (e) {}
        })();
        """
    }

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

    static let toggleLikeJS = """
    (function(){
      const btn = document.querySelector('.playbackSoundBadge__like');
      if (btn) btn.click();
    })();
    """

    static let toggleShuffleJS = """
    (function(){
      const btn = document.querySelector('.shuffleControl');
      if (btn) btn.click();
    })();
    """

    static let cycleRepeatJS = """
    (function(){
      const btn = document.querySelector('.repeatControl');
      if (btn) btn.click();
    })();
    """

    static func seekToJS(fraction: Double) -> String {
        let clamped = min(1.0, max(0.0, fraction))
        return """
        (function(){
          const bar = document.querySelector('.playbackTimeline__progressWrapper');
          if (bar) {
            const rect = bar.getBoundingClientRect();
            const x = rect.left + rect.width * \(clamped);
            const y = rect.top + rect.height / 2;
            ['mousedown', 'mouseup', 'click'].forEach((type) => {
              bar.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, clientX: x, clientY: y }));
            });
            return;
          }
          const audio = document.querySelector('audio');
          if (audio && isFinite(audio.duration) && audio.duration > 0) {
            audio.currentTime = audio.duration * \(clamped);
          }
        })();
        """
    }

    private static func jsTemplateEscape(_ str: String) -> String {
        str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "${", with: "\\${")
    }
}
