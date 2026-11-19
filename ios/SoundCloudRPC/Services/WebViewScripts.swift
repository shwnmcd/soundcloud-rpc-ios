import Foundation

enum WebViewScripts {
    /// Captures SoundCloud's detached `new Audio()` HTMLMediaElement at document-start so seeking works reliably both in-app and on Lock Screen
    static let audioCaptureScript: String = """
    (function() {
      if (window.__scAudioCaptureActive) return;
      window.__scAudioCaptureActive = true;
      const origPlay = HTMLMediaElement.prototype.play;
      HTMLMediaElement.prototype.play = function() {
        window.__scActiveAudio = this;
        return origPlay.apply(this, arguments);
      };
    })();
    """

    /// Port of soundcloud-rpc's audioMonitorService.js adapted for WKWebView + Lock Screen MediaSession sync
    static let audioMonitorScript: String = """
    (function() {
      if (window.__soundCloudMonitorActive) return;
      window.__soundCloudMonitorActive = true;

      let lastSig = '';
      let lastHref = '';
      let elapsedObserver = null;

      function notifyRouteIfChanged() {
        const href = window.location.href;
        if (href !== lastHref) {
          lastHref = href;
          try {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.routeChange) {
              window.webkit.messageHandlers.routeChange.postMessage({
                url: href,
                canGoBack: window.history.length > 1
              });
            }
          } catch (e) {}
        }
      }

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

      function syncMediaSessionHandlers() {
        if (!('mediaSession' in navigator)) return;
        try {
          navigator.mediaSession.setActionHandler('seekbackward', null);
          navigator.mediaSession.setActionHandler('seekforward', null);
          navigator.mediaSession.setActionHandler('previoustrack', () => {
            const btn = document.querySelector('.skipControl__previous');
            if (btn) btn.click();
          });
          navigator.mediaSession.setActionHandler('nexttrack', () => {
            const btn = document.querySelector('.skipControl__next');
            if (btn) btn.click();
          });
          navigator.mediaSession.setActionHandler('play', () => {
            const btn = document.querySelector('.playControls__play, .playControl');
            if (btn && !btn.classList.contains('playing')) btn.click();
          });
          navigator.mediaSession.setActionHandler('pause', () => {
            const btn = document.querySelector('.playControls__play, .playControl');
            if (btn && btn.classList.contains('playing')) btn.click();
          });
          navigator.mediaSession.setActionHandler('seekto', (details) => {
            if (!details || typeof details.seekTime !== 'number') return;
            const durationEl = document.querySelector('.playbackTimeline__duration span:last-child');
            const bar = document.querySelector('.playbackTimeline__progressWrapper');
            const audio = window.__scActiveAudio || document.querySelector('audio');
            let totalSec = (audio && isFinite(audio.duration) && audio.duration > 0) ? audio.duration : 0;
            if (!totalSec && durationEl) {
              const parts = durationEl.textContent.trim().replace(/^-/, '').split(':').map(Number);
              for (const p of parts) totalSec = totalSec * 60 + (isNaN(p) ? 0 : p);
            }
            if (bar && totalSec > 0) {
              const frac = Math.max(0, Math.min(1, details.seekTime / totalSec));
              const rect = bar.getBoundingClientRect();
              if (rect.width > 10) {
                const x = rect.left + rect.width * frac;
                const y = rect.top + rect.height / 2;
                const common = { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y, screenX: x, screenY: y, button: 0, buttons: 1 };
                try { bar.dispatchEvent(new PointerEvent('pointerdown', Object.assign({ pointerId: 1, pointerType: 'mouse', isPrimary: true }, common))); } catch (e) {}
                bar.dispatchEvent(new MouseEvent('mousedown', common));
                document.dispatchEvent(new MouseEvent('mousemove', common));
                bar.dispatchEvent(new MouseEvent('mousemove', common));
                document.dispatchEvent(new MouseEvent('mouseup', Object.assign({}, common, { buttons: 0 })));
                bar.dispatchEvent(new MouseEvent('mouseup', Object.assign({}, common, { buttons: 0 })));
                bar.dispatchEvent(new MouseEvent('click', Object.assign({}, common, { buttons: 0 })));
              }
            }
            if (audio && isFinite(audio.duration) && audio.duration > 0) {
              const target = Math.max(0, Math.min(audio.duration, details.seekTime));
              setTimeout(() => {
                if (Math.abs(audio.currentTime - target) > 2.0) {
                  try { audio.currentTime = target; } catch (e) {}
                }
              }, 80);
            }
          });
        } catch (e) {}
      }

      setInterval(() => {
        attachObservers();
        syncMediaSessionHandlers();
        notifyRouteIfChanged();
        notifyPlaybackStateChange(false);
      }, 500);

      window.addEventListener('popstate', () => {
        notifyRouteIfChanged();
      });

      if (document.readyState === 'complete' || document.readyState === 'interactive') {
        attachObservers();
        syncMediaSessionHandlers();
        notifyRouteIfChanged();
        notifyPlaybackStateChange(true);
      } else {
        document.addEventListener('DOMContentLoaded', () => {
          attachObservers();
          syncMediaSessionHandlers();
          notifyRouteIfChanged();
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

    /// Generates JS to apply Dark Mode, Official SoundCloud iOS-Inspired Layout (Compact 56px Library Rows, 164px Home Carousels, Scrollable Home Quick-Cards), AdBlocker Cosmetics & Custom Theme
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
        /* === Official SoundCloud iOS-Inspired Sleek App Layout === */
        html, body {
            max-width: 100vw !important;
            overflow-x: hidden !important;
            -webkit-overflow-scrolling: touch !important;
            padding-top: 0 !important;
            padding-bottom: 150px !important;
            background-color: var(--background-base, #111111) !important;
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", sans-serif !important;
        }

        /* Hide SoundCloud's desktop website chrome & web-only clutter */
        header.header,
        .header,
        .announcements,
        .collection__nav,
        .collectionNav,
        .g-tabs-large,
        .collectionSection__top,
        .collectionSection__filters,
        .userLikes__header,
        .searchTitle,
        .searchOptions,
        .search .l-sidebar-left,
        .tileGallery__sliderButton,
        .playableTile__actions,
        .l-product-banners,
        .l-about-left,
        .listenDetails__author,
        .listenEngagement__commentForm,
        .commentForm,
        .commentFormDisabled,
        .commentsList,
        .suggestedTags,
        .playlistTags,
        .emptyTags,
        .listenDetails__tags,
        .listenDetails__description,
        .listenDetails__partialInfo,
        .soundBadgeList__more,
        .imageChooser,
        .imageChooser__chooseButton,
        .fullHero__title .soundTitle__playButton,
        .fullHero__info .soundTitle__uploadTime,
        .fullHero__info .soundTitle__tagContainer,
        .fullHero__info .sc-ministats-group,
        .l-listen-wrapper .l-sidebar-right,
        .l-front .l-sidebar-right,
        .stream .l-sidebar-right,
        .search .l-sidebar-right,
        .collection .l-sidebar-right,
        [class*="suggestedTag"],
        [class*="SuggestedTag"],
        [class*="EmptyTag"],
        [class*="cookie"],
        #onetrust-consent-sdk {
            display: none !important;
        }

        /* Keep playControls invisible at left:0 (NOT -9999px!) so timeline getBoundingClientRect() has valid positive coordinates for seeking */
        .playControls {
            position: fixed !important;
            left: 0 !important;
            right: 0 !important;
            bottom: 0 !important;
            width: 100vw !important;
            opacity: 0 !important;
            pointer-events: none !important;
            z-index: -10 !important;
        }

        /* Full-width clean canvas */
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
            padding: 6px 14px 155px 14px !important;
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

        .l-front .l-sidebar-right,
        .stream .l-sidebar-right {
            display: none !important;
        }
        .l-sidebar-right {
            position: static !important;
            float: none !important;
            width: 100% !important;
            margin: 20px 0 0 0 !important;
            padding: 14px 0 0 0 !important;
            border-top: 1px solid rgba(255,255,255,0.08) !important;
        }

        /* === INJECTED SOUNDCLOUD iOS HOME QUICK-CARDS (Scrolls naturally with Home!) === */
        #sc-ios-home-quick {
            display: flex;
            flex-direction: column;
            gap: 10px;
            margin: 4px 0 24px 0;
        }
        #sc-ios-home-quick .sc-likes-banner {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 16px 16px;
            border-radius: 14px;
            background: linear-gradient(125deg, #5a1c00 0%, #2a1106 52%, #19191b 100%);
            border: 1px solid rgba(255, 85, 0, 0.25);
            color: #ffffff;
            text-decoration: none;
            cursor: pointer;
        }
        #sc-ios-home-quick .sc-likes-left {
            display: flex;
            align-items: center;
            gap: 14px;
        }
        #sc-ios-home-quick .sc-likes-icon {
            width: 42px;
            height: 42px;
            border-radius: 12px;
            background: rgba(255, 85, 0, 0.22);
            border: 1.5px solid #ff5500;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 20px;
            color: #ff5500;
        }
        #sc-ios-home-quick .sc-likes-title {
            font-size: 17px;
            font-weight: 700;
            letter-spacing: -0.2px;
        }
        #sc-ios-home-quick .sc-likes-sub {
            font-size: 12px;
            color: rgba(255,255,255,0.68);
            margin-top: 2px;
        }
        #sc-ios-home-quick .sc-shuffle-pill {
            width: 38px;
            height: 38px;
            border-radius: 50%;
            background: rgba(255,255,255,0.12);
            border: none;
            color: #ffffff;
            font-size: 16px;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        #sc-ios-home-quick .sc-quick-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 10px;
        }
        #sc-ios-home-quick .sc-quick-card {
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 11px 12px;
            border-radius: 12px;
            background: #1b1b1e;
            border: 1px solid rgba(255,255,255,0.06);
            color: #ffffff;
            cursor: pointer;
        }
        html.theme-light #sc-ios-home-quick .sc-quick-card {
            background: #f2f2f7;
            color: #111111;
            border-color: rgba(0,0,0,0.08);
        }
        #sc-ios-home-quick .sc-quick-badge {
            width: 36px;
            height: 36px;
            border-radius: 8px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 16px;
            flex-shrink: 0;
        }
        #sc-ios-home-quick .sc-quick-name {
            font-size: 13.5px;
            font-weight: 600;
            line-height: 1.2;
        }
        #sc-ios-home-quick .sc-quick-meta {
            font-size: 11px;
            opacity: 0.62;
            margin-top: 2px;
        }

        /* === OFFICIAL SOUNDCLOUD iOS HOME HORIZONTAL SQUARE CAROUSELS === */
        .mixedSelectionModule,
        .collectionSection {
            margin-bottom: 26px !important;
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
        .tileGallery__slider,
        .tileGallery__sliderPeek,
        .tileGallery__sliderPanel {
            overflow-x: auto !important;
            overflow-y: hidden !important;
            -webkit-overflow-scrolling: touch !important;
            touch-action: pan-x pan-y !important;
            scrollbar-width: none !important;
            padding-bottom: 4px !important;
        }
        .tileGallery__slider::-webkit-scrollbar,
        .tileGallery__sliderPeek::-webkit-scrollbar,
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
            flex: 0 0 162px !important;
            width: 162px !important;
            min-width: 162px !important;
            max-width: 162px !important;
            padding: 0 !important;
            margin: 0 !important;
        }
        .tileGallery__slide .playableTile,
        .tileGallery__slide .playableTile__artworkLink,
        .tileGallery__slide .image {
            width: 162px !important;
            height: auto !important;
        }
        .tileGallery__slide .playableTile__artwork {
            position: relative !important;
            width: 162px !important;
            height: 162px !important;
            padding: 0 !important;
            border-radius: 10px !important;
            overflow: hidden !important;
            box-shadow: 0 6px 18px rgba(0,0,0,0.38) !important;
        }
        .tileGallery__slide .playableTile__artwork .image,
        .tileGallery__slide .playableTile__artwork .image__full {
            position: absolute !important;
            inset: 0 !important;
            width: 100% !important;
            height: 100% !important;
            padding: 0 !important;
            background-size: cover !important;
            background-position: center !important;
            border-radius: 10px !important;
        }
        .tileGallery__slide .playableTile__description {
            margin-top: 8px !important;
        }
        .tileGallery__slide .playableTile__heading {
            font-size: 13.5px !important;
            font-weight: 600 !important;
            line-height: 1.3 !important;
            white-space: nowrap !important;
            overflow: hidden !important;
            text-overflow: ellipsis !important;
        }
        .tileGallery__slide .playableTile__usernameHeading {
            font-size: 12px !important;
            opacity: 0.65 !important;
            margin-top: 2px !important;
            display: -webkit-box !important;
            -webkit-line-clamp: 2 !important;
            -webkit-box-orient: vertical !important;
            overflow: hidden !important;
        }

        /* === OFFICIAL SOUNDCLOUD iOS COMPACT 54×54 BORDERLESS LIST ROWS (Exact SC iOS Spacing!) === */
        .badgeList,
        .userLikes .lazyLoadingList__list,
        .collectionSection .lazyLoadingList__list,
        .userNetwork .lazyLoadingList__list {
            display: flex !important;
            flex-direction: column !important;
            gap: 4px !important;
            width: 100% !important;
            margin: 0 !important;
            padding: 0 !important;
        }
        .badgeList__item {
            width: 100% !important;
            min-width: 0 !important;
            max-width: none !important;
            height: auto !important;
            float: none !important;
            margin: 0 !important;
            padding: 6px 2px !important;
            border: none !important;
            box-sizing: border-box !important;
        }
        .badgeList__item .playableTile {
            width: 100% !important;
            height: auto !important;
            display: flex !important;
            flex-direction: row !important;
            align-items: center !important;
            gap: 12px !important;
        }
        .badgeList__item .playableTile__artwork {
            position: relative !important;
            flex: 0 0 54px !important;
            width: 54px !important;
            height: 54px !important;
            min-width: 54px !important;
            max-width: 54px !important;
            padding: 0 !important;
            margin: 0 !important;
            border-radius: 6px !important;
            overflow: hidden !important;
        }
        .badgeList__item .playableTile__artworkLink,
        .badgeList__item .playableTile__artwork .image,
        .badgeList__item .playableTile__artwork .image__full {
            position: absolute !important;
            inset: 0 !important;
            width: 54px !important;
            height: 54px !important;
            padding: 0 !important;
            margin: 0 !important;
            background-size: cover !important;
            background-position: center !important;
        }
        .badgeList__item .playableTile__playButton {
            position: absolute !important;
            inset: 0 !important;
            display: flex !important;
            align-items: center !important;
            justify-content: center !important;
        }
        .badgeList__item .playableTile__playButton .sc-button-play {
            width: 28px !important;
            height: 28px !important;
            border-radius: 50% !important;
            transform: scale(0.8) !important;
        }
        .badgeList__item .playableTile__description {
            flex: 1 !important;
            min-width: 0 !important;
            margin: 0 !important;
            padding: 0 !important;
            position: static !important;
            height: auto !important;
            display: flex !important;
            flex-direction: column !important;
            justify-content: center !important;
            gap: 2px !important;
        }
        .badgeList__item .playableTile__heading {
            font-size: 15px !important;
            font-weight: 600 !important;
            line-height: 1.25 !important;
            white-space: nowrap !important;
            overflow: hidden !important;
            text-overflow: ellipsis !important;
        }
        .badgeList__item .playableTile__usernameHeading {
            font-size: 13.5px !important;
            opacity: 0.62 !important;
            white-space: nowrap !important;
            overflow: hidden !important;
            text-overflow: ellipsis !important;
        }
        .loading,
        .lazyLoadingList__loading,
        .paging-eof {
            width: 100% !important;
            margin: 16px auto !important;
        }

        /* Keep vertical track lists & search results single-column */
        .searchList .lazyLoadingList__list,
        .stream .lazyLoadingList__list,
        .soundList.lazyLoadingList__list,
        .trackList__list {
            display: flex !important;
            flex-direction: column !important;
            gap: 6px !important;
        }

        /* === OFFICIAL SOUNDCLOUD iOS PLAYLIST / TRACK DETAIL HERO (Exact Centered Art, Zero Shifted Box, Zero Giant Circle!) === */
        .l-listen-hero {
            padding: 0 !important;
            margin: 0 0 8px 0 !important;
        }
        .fullListenHero,
        .fullHero {
            position: relative !important;
            height: auto !important;
            min-height: 0 !important;
            padding: 12px 12px 10px 12px !important;
            margin: 0 0 4px 0 !important;
            border-radius: 16px !important;
            overflow: hidden !important;
            background: linear-gradient(180deg, rgba(145, 42, 0, 0.28) 0%, #111111 100%) !important;
        }
        .fullHero__background {
            opacity: 0.22 !important;
            filter: blur(36px) !important;
        }
        .fullHero__foreground {
            position: relative !important;
            display: flex !important;
            flex-direction: column !important;
            align-items: center !important;
            text-align: center !important;
            gap: 8px !important;
            padding: 0 !important;
            margin: 0 !important;
            height: auto !important;
        }
        /* Neutralize ALL desktop absolute offsets inside fullHero */
        .fullHero__artwork,
        .fullHero__artwork *,
        .fullHero__title,
        .fullHero__info,
        .fullHero__playerArea,
        .fullHero__waveform,
        .fullHero__tracksCount,
        .genericTrackCount {
            position: static !important;
            top: auto !important;
            left: auto !important;
            right: auto !important;
            bottom: auto !important;
            transform: none !important;
            float: none !important;
        }
        /* Perfectly centered 176×176 artwork — fixes the half-shifted brown box completely! */
        .fullHero__artwork {
            order: 1 !important;
            width: 176px !important;
            height: 176px !important;
            margin: 0 auto !important;
            padding: 0 !important;
            border-radius: 10px !important;
            overflow: hidden !important;
            box-shadow: 0 12px 28px rgba(0, 0, 0, 0.55) !important;
            flex-shrink: 0 !important;
            display: flex !important;
            align-items: center !important;
            justify-content: center !important;
        }
        .fullHero__artwork .listenArtworkWrapper,
        .fullHero__artwork .listenArtworkWrapper__artwork,
        .fullHero__artwork .image,
        .fullHero__artwork .image__full,
        .fullHero__artwork span.sc-artwork {
            width: 176px !important;
            height: 176px !important;
            min-width: 176px !important;
            max-width: 176px !important;
            min-height: 176px !important;
            max-height: 176px !important;
            margin: 0 !important;
            padding: 0 !important;
            display: block !important;
            background-size: cover !important;
            background-position: center !important;
            border-radius: 10px !important;
        }
        .fullHero__title {
            order: 2 !important;
            width: 100% !important;
            margin: 4px 0 0 0 !important;
            display: flex !important;
            flex-direction: column !important;
            align-items: center !important;
        }
        .fullHero__title .soundTitle__titleContainer,
        .fullHero__title .soundTitle__usernameTitleContainer {
            display: flex !important;
            flex-direction: column !important;
            align-items: center !important;
            text-align: center !important;
            gap: 3px !important;
            margin: 0 !important;
        }
        .fullHero__title .soundTitle__title,
        .fullHero__title .soundTitle__title span {
            font-size: 20px !important;
            font-weight: 700 !important;
            text-align: center !important;
            background: transparent !important;
            padding: 0 !important;
            line-height: 1.25 !important;
        }
        .fullHero__title .soundTitle__username,
        .fullHero__title .soundTitle__username a {
            font-size: 13.5px !important;
            font-weight: 500 !important;
            opacity: 0.72 !important;
            background: transparent !important;
            padding: 0 !important;
        }
        /* Replace SoundCloud's giant 120px black circle "138 TRACKS" with a sleek 1-line subtitle! */
        .fullHero__info {
            order: 3 !important;
            display: flex !important;
            flex-direction: row !important;
            align-items: center !important;
            justify-content: center !important;
            gap: 6px !important;
            margin: 0 !important;
            padding: 0 !important;
        }
        .fullHero__tracksCount,
        .genericTrackCount {
            display: inline-flex !important;
            flex-direction: row !important;
            align-items: center !important;
            justify-content: center !important;
            gap: 5px !important;
            width: auto !important;
            height: auto !important;
            min-width: 0 !important;
            min-height: 0 !important;
            padding: 0 !important;
            margin: 0 !important;
            border-radius: 0 !important;
            background: transparent !important;
            box-shadow: none !important;
            color: rgba(255, 255, 255, 0.62) !important;
        }
        .genericTrackCount__number,
        .genericTrackCount__label,
        .genericTrackCount__duration {
            font-size: 12.5px !important;
            font-weight: 500 !important;
            line-height: 1.2 !important;
            text-transform: lowercase !important;
            display: inline !important;
            margin: 0 !important;
            color: rgba(255, 255, 255, 0.62) !important;
        }
        .genericTrackCount__duration::before {
            content: "· " !important;
        }
        .fullHero__playerArea {
            order: 4 !important;
            width: 100% !important;
        }
        /* Hide bulky waveform on multi-track playlists (official SC iOS shows tracks immediately!) */
        .fullListenHero:has(.genericTrackCount) .fullHero__playerArea {
            display: none !important;
        }
        /* Compact single-row engagement buttons with zero excess whitespace */
        .listenEngagement {
            margin: 0 0 8px 0 !important;
            padding: 0 !important;
            border: none !important;
        }
        .listenEngagement__footer {
            display: flex !important;
            justify-content: center !important;
            padding: 4px 0 8px 0 !important;
            margin: 0 !important;
            border: none !important;
        }
        .listenEngagement__stats {
            display: none !important;
        }

        /* === KILL THE 180px DESKTOP LEFT MARGIN ON PLAYLISTS & TRACKS === */
        .l-about-rows,
        .l-about-main,
        .l-about-right,
        .l-listen-wrapper .l-main,
        .listenDetails,
        .listenDetails__trackList,
        .trackList {
            display: block !important;
            width: 100% !important;
            min-width: 0 !important;
            max-width: 100% !important;
            margin-left: 0 !important;
            margin-right: 0 !important;
            padding-left: 0 !important;
            padding-right: 0 !important;
            float: none !important;
            border: none !important;
        }

        /* === OFFICIAL SOUNDCLOUD iOS 54×54 BORDERLESS PLAYLIST TRACKLIST ROWS === */
        .trackList__list {
            display: flex !important;
            flex-direction: column !important;
            gap: 4px !important;
            width: 100% !important;
            margin: 0 !important;
            padding: 0 !important;
        }
        .trackList__item {
            width: 100% !important;
            margin: 0 !important;
            padding: 6px 2px !important;
            border: none !important;
            box-sizing: border-box !important;
        }
        .trackItem {
            display: flex !important;
            flex-direction: row !important;
            align-items: center !important;
            gap: 12px !important;
            width: 100% !important;
            height: auto !important;
            padding: 0 !important;
            margin: 0 !important;
        }
        .trackItem__image {
            position: relative !important;
            flex: 0 0 54px !important;
            width: 54px !important;
            height: 54px !important;
            min-width: 54px !important;
            max-width: 54px !important;
            border-radius: 6px !important;
            overflow: hidden !important;
            margin: 0 !important;
        }
        .trackItem__image .image,
        .trackItem__image .image__full {
            width: 54px !important;
            height: 54px !important;
            padding: 0 !important;
            background-size: cover !important;
            background-position: center !important;
            border-radius: 6px !important;
        }
        .trackItem__number,
        .trackItem__separator {
            display: none !important;
        }
        .trackItem__content {
            flex: 1 !important;
            min-width: 0 !important;
            display: flex !important;
            flex-direction: column-reverse !important;
            justify-content: center !important;
            align-items: flex-start !important;
            gap: 2px !important;
            margin: 0 !important;
            padding: 0 !important;
            overflow: hidden !important;
            line-height: 1.25 !important;
        }
        .trackItem__trackTitle {
            font-size: 15px !important;
            font-weight: 600 !important;
            color: var(--text-base, #ffffff) !important;
            max-width: 100% !important;
            white-space: nowrap !important;
            overflow: hidden !important;
            text-overflow: ellipsis !important;
        }
        .trackItem__username {
            font-size: 13.5px !important;
            opacity: 0.62 !important;
            max-width: 100% !important;
            white-space: nowrap !important;
            overflow: hidden !important;
            text-overflow: ellipsis !important;
        }
        .trackItem__additional {
            flex-shrink: 0 !important;
            margin-left: 8px !important;
            font-size: 12px !important;
            opacity: 0.6 !important;
        }
        .trackItem__actions {
            position: static !important;
            opacity: 1 !important;
            background: transparent !important;
        }

        /* === MESHED FEED & SEARCH TRACK CARDS === */
        .soundList__item {
            border: none !important;
            padding: 0 !important;
            margin: 0 !important;
        }
        .soundContext {
            margin: 0 0 6px 4px !important;
            font-size: 12px !important;
            opacity: 0.72 !important;
        }
        .sound__body {
            display: grid !important;
            grid-template-columns: 60px minmax(0, 1fr) !important;
            column-gap: 12px !important;
            row-gap: 10px !important;
            align-items: center !important;
            background: rgba(255, 255, 255, 0.045) !important;
            border: 1px solid rgba(255, 255, 255, 0.06) !important;
            border-radius: 14px !important;
            padding: 12px !important;
            box-sizing: border-box !important;
        }
        html.theme-light .sound__body {
            background: rgba(0, 0, 0, 0.035) !important;
            border-color: rgba(0, 0, 0, 0.07) !important;
        }
        .sound__coverArt {
            grid-column: 1 !important;
            grid-row: 1 !important;
            float: none !important;
            margin: 0 !important;
            width: 60px !important;
            height: 60px !important;
            border-radius: 10px !important;
            overflow: hidden !important;
            box-shadow: 0 4px 12px rgba(0,0,0,0.3) !important;
        }
        .sound__coverArt .image,
        .sound__coverArt .image__full {
            width: 60px !important;
            height: 60px !important;
            padding: 0 !important;
            background-size: cover !important;
        }
        .sound__content {
            display: contents !important;
        }
        .sound__header {
            grid-column: 2 !important;
            grid-row: 1 !important;
            min-width: 0 !important;
            margin: 0 !important;
            padding: 0 !important;
        }
        .soundTitle__titleContainer {
            display: flex !important;
            align-items: center !important;
            gap: 10px !important;
            min-width: 0 !important;
        }
        .soundTitle__playButton {
            flex-shrink: 0 !important;
            margin: 0 !important;
        }
        .soundTitle__usernameTitleContainer {
            min-width: 0 !important;
            flex: 1 !important;
        }
        .soundTitle__username {
            font-size: 12.5px !important;
            opacity: 0.72 !important;
        }
        .soundTitle__title {
            font-size: 15px !important;
            font-weight: 700 !important;
            line-height: 1.25 !important;
            display: -webkit-box !important;
            -webkit-line-clamp: 2 !important;
            -webkit-box-orient: vertical !important;
            overflow: hidden !important;
            white-space: normal !important;
        }
        .soundTitle__additionalContainer {
            margin-left: 6px !important;
            flex-shrink: 0 !important;
        }
        .sound__waveform {
            grid-column: 1 / -1 !important;
            grid-row: 2 !important;
            margin: 0 !important;
            min-height: 44px !important;
        }
        .waveformCommentsNode,
        .commentBadgeList {
            display: none !important;
        }
        .sound__footer {
            grid-column: 1 / -1 !important;
            grid-row: 3 !important;
            margin: 0 !important;
            padding-top: 4px !important;
            display: flex !important;
            align-items: center !important;
            justify-content: space-between !important;
            flex-wrap: wrap !important;
            gap: 8px !important;
        }
        .soundActions .sc-button-group {
            display: flex !important;
            flex-wrap: nowrap !important;
            gap: 6px !important;
        }
        .sc-button {
            border-radius: 999px !important;
        }
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
              document.documentElement.style.setProperty('--background-base', '#111111');
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

            // Inject SoundCloud iOS-style Home Quick-Access Banner ("Your likes" + 2x2 shortcuts) on /discover
            function ensureHomeQuickCards() {
              const existing = document.getElementById('sc-ios-home-quick');
              const isDiscover = window.location.pathname === '/discover' || window.location.pathname === '/';
              if (!(\(mobileAppLayout ? "true" : "false")) || !isDiscover) {
                if (existing) existing.remove();
                return;
              }
              if (existing) return;
              const container = document.querySelector('.l-container.l-content .l-main') || document.querySelector('.l-container.l-content');
              if (!container) return;

              const wrap = document.createElement('div');
              wrap.id = 'sc-ios-home-quick';
              wrap.innerHTML = `
                <div class="sc-likes-banner" data-nav="likes">
                  <div class="sc-likes-left">
                    <div class="sc-likes-icon">&#9829;</div>
                    <div>
                      <div class="sc-likes-title">Your likes</div>
                      <div class="sc-likes-sub">Liked tracks &amp; favorites</div>
                    </div>
                  </div>
                  <button type="button" class="sc-shuffle-pill" data-nav="likes_shuffle" aria-label="Shuffle Likes">&#8646;</button>
                </div>
                <div class="sc-quick-grid">
                  <div class="sc-quick-card" data-nav="playlists">
                    <div class="sc-quick-badge" style="background:rgba(255,85,0,0.18);color:#ff5500;">&#9835;</div>
                    <div><div class="sc-quick-name">Playlists</div><div class="sc-quick-meta">Your sets</div></div>
                  </div>
                  <div class="sc-quick-card" data-nav="albums">
                    <div class="sc-quick-badge" style="background:rgba(99,102,241,0.2);color:#818cf8;">&#9673;</div>
                    <div><div class="sc-quick-name">Albums</div><div class="sc-quick-meta">Saved LPs</div></div>
                  </div>
                  <div class="sc-quick-card" data-nav="stations">
                    <div class="sc-quick-badge" style="background:rgba(16,185,129,0.2);color:#34d399;">&#9737;</div>
                    <div><div class="sc-quick-name">Stations</div><div class="sc-quick-meta">Radio mixes</div></div>
                  </div>
                  <div class="sc-quick-card" data-nav="history">
                    <div class="sc-quick-badge" style="background:rgba(245,158,11,0.2);color:#fbbf24;">&#8634;</div>
                    <div><div class="sc-quick-name">History</div><div class="sc-quick-meta">Recently played</div></div>
                  </div>
                </div>
              `;

              wrap.addEventListener('click', (e) => {
                const target = e.target.closest('[data-nav]');
                if (!target) return;
                e.stopPropagation();
                const dest = target.getAttribute('data-nav');
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeNav) {
                  window.webkit.messageHandlers.nativeNav.postMessage({ destination: dest });
                }
              });

              container.insertBefore(wrap, container.firstChild);
            }

            ensureHomeQuickCards();
            if (!window.__scHomeQuickTimer) {
              window.__scHomeQuickTimer = setInterval(ensureHomeQuickCards, 1200);
            }
          } catch (e) {}
        })();
        """
    }

    /// Seamless Single-Page-App navigation inside soundcloud.com so music NEVER stops or restarts when switching tabs!
    static func navigateSPAJS(path: String) -> String {
        let escaped = jsTemplateEscape(path)
        return """
        (function(){
          const target = `\(escaped)`;
          if (!window.location.hostname.includes('soundcloud.com')) {
            window.location.href = 'https://soundcloud.com' + target;
            return;
          }
          if (window.location.pathname + window.location.search === target) {
            window.scrollTo({ top: 0, behavior: 'smooth' });
            return;
          }
          // Prefer clicking an existing SoundCloud SPA router anchor if present
          const existing = document.querySelector('a[href="' + target + '"], a[href="https://soundcloud.com' + target + '"]');
          if (existing) {
            existing.click();
            return;
          }
          // Otherwise synthesize a click on a relative <a> inside #app so SoundCloud's delegated SPA router intercepts it without reloading the page!
          const a = document.createElement('a');
          a.href = target;
          a.style.display = 'none';
          const root = document.querySelector('#app') || document.body;
          root.appendChild(a);
          a.click();
          setTimeout(() => { try { a.remove(); } catch (e) {} }, 60);
        })();
        """
    }

    static let spaGoBackJS = """
    (function(){
      if (window.history.length > 1) {
        window.history.back();
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

    static let playFirstTrackJS = """
    (function(){
      const firstPlay = document.querySelector('.badgeList__item .sc-button-play, .soundList__item .sc-button-play, .trackList__item .sc-button-play');
      if (firstPlay) firstPlay.click();
    })();
    """

    static let shuffleAndPlayJS = """
    (function(){
      const shuffleBtn = document.querySelector('.shuffleControl');
      if (shuffleBtn && !shuffleBtn.classList.contains('m-shuffling')) {
        shuffleBtn.click();
      }
      const items = document.querySelectorAll('.badgeList__item .sc-button-play, .soundList__item .sc-button-play');
      if (items.length > 0) {
        const pick = items[Math.floor(Math.random() * Math.min(items.length, 20))];
        pick.click();
      }
    })();
    """

    static func filterVisibleListJS(query: String) -> String {
        let escaped = jsTemplateEscape(query.lowercased())
        return """
        (function(){
          const q = `\(escaped)`.trim();
          const items = document.querySelectorAll('.badgeList__item, .soundList__item');
          items.forEach((el) => {
            if (!q) {
              el.style.display = '';
              return;
            }
            const txt = (el.textContent || '').toLowerCase();
            el.style.display = txt.includes(q) ? '' : 'none';
          });
        })();
        """
    }

    static func seekToJS(fraction: Double) -> String {
        let clamped = min(1.0, max(0.0, fraction))
        return """
        (function(){
          const frac = \(clamped);

          // 1) Scrub SoundCloud's timeline bar using full pointer + mouse drag sequence (with real left:0 viewport coordinates)
          const bar = document.querySelector('.playbackTimeline__progressWrapper');
          if (bar) {
            const rect = bar.getBoundingClientRect();
            if (rect.width > 10) {
              const x = rect.left + rect.width * frac;
              const y = rect.top + rect.height / 2;
              const common = {
                bubbles: true,
                cancelable: true,
                view: window,
                clientX: x,
                clientY: y,
                screenX: x,
                screenY: y,
                button: 0,
                buttons: 1
              };
              try {
                bar.dispatchEvent(new PointerEvent('pointerdown', Object.assign({ pointerId: 1, pointerType: 'mouse', isPrimary: true }, common)));
              } catch (e) {}
              bar.dispatchEvent(new MouseEvent('mousedown', common));
              try {
                document.dispatchEvent(new PointerEvent('pointermove', Object.assign({ pointerId: 1, pointerType: 'mouse', isPrimary: true }, common)));
              } catch (e) {}
              document.dispatchEvent(new MouseEvent('mousemove', common));
              bar.dispatchEvent(new MouseEvent('mousemove', common));
              try {
                document.dispatchEvent(new PointerEvent('pointerup', Object.assign({ pointerId: 1, pointerType: 'mouse', isPrimary: true }, common)));
              } catch (e) {}
              document.dispatchEvent(new MouseEvent('mouseup', Object.assign({}, common, { buttons: 0 })));
              bar.dispatchEvent(new MouseEvent('mouseup', Object.assign({}, common, { buttons: 0 })));
              bar.dispatchEvent(new MouseEvent('click', Object.assign({}, common, { buttons: 0 })));
            }
          }

          // 2) Fallback: seek SoundCloud's captured active HTMLAudioElement directly (works even for detached new Audio()!)
          const audio = window.__scActiveAudio || document.querySelector('audio');
          if (audio && isFinite(audio.duration) && audio.duration > 0) {
            const target = audio.duration * frac;
            setTimeout(() => {
              if (Math.abs(audio.currentTime - target) > 2.0) {
                try { audio.currentTime = target; } catch (e) {}
              }
            }, 80);
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
