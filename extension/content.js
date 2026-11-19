// Content script injected into https://soundcloud.com/*
(function () {
  if (window.__scRpcExtActive) return;
  window.__scRpcExtActive = true;

  const AD_COSMETIC_CSS = `
    .visualAd, .adOverlay, .audioAd, .promotedSound, .header__upsellWrapper,
    .l-product-banners, .sidebarModule__ad, .m-banner, .banner__ad,
    .goUpsellBanner, .upsellBanner, .mobileAppBanner, .appInstallBanner,
    .webBanner, [data-testid="ad-banner"], li.soundList__item:has(.sc-promoted-icon) {
      display: none !important;
    }
  `;

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

  function applySettings(cfg) {
    const isDark = cfg.darkMode !== false;
    document.documentElement.classList.toggle('theme-dark', isDark);
    document.documentElement.classList.toggle('theme-light', !isDark);
    if (document.body) {
      document.body.classList.toggle('theme-dark', isDark);
      document.body.classList.toggle('theme-light', !isDark);
    }
    document.documentElement.style.setProperty('--background-base', isDark ? '#121212' : '#ffffff');
    document.documentElement.style.setProperty('--background-surface', isDark ? '#212121' : '#f2f2f2');
    document.documentElement.style.setProperty('--text-base', isDark ? '#ffffff' : '#333333');

    upsertStyle('sc-rpc-ext-adblock', cfg.adBlocker !== false ? AD_COSMETIC_CSS : '');
    upsertStyle('sc-rpc-ext-custom-theme', cfg.customCSS || '');
  }

  function getTrackInfo() {
    const playBtn = document.querySelector('.playControls__play');
    const authorEl = document.querySelector('.playbackSoundBadge__lightLink');
    const artworkEl = document.querySelector('.playbackSoundBadge__avatar .image__lightOutline span');
    const titleEl = document.querySelector('.playbackSoundBadge__titleLink');
    const elapsedEl = document.querySelector('.playbackTimeline__timePassed span:last-child');
    const durationEl = document.querySelector('.playbackTimeline__duration span:last-child');

    const bg = artworkEl ? artworkEl.style.backgroundImage : '';
    return {
      title: (artworkEl && artworkEl.getAttribute('aria-label')) || (titleEl && (titleEl.getAttribute('title') || titleEl.textContent.trim())) || '',
      author: authorEl ? authorEl.textContent.trim() : '',
      artwork: bg ? bg.replace(/^url\(['"]?|['"]?\)$/g, '').replace('50x50.', '500x500.') : '',
      elapsed: elapsedEl ? elapsedEl.textContent.trim() : '0:00',
      duration: durationEl ? durationEl.textContent.trim() : '0:00',
      isPlaying: playBtn ? playBtn.classList.contains('playing') : false,
      url: titleEl && titleEl.href ? titleEl.href.split('?')[0] : '',
    };
  }

  let lastSig = '';
  function pollTrack() {
    const info = getTrackInfo();
    const sig = JSON.stringify(info);
    if (sig !== lastSig) {
      lastSig = sig;
      chrome.runtime.sendMessage({ type: 'TRACK_UPDATE', payload: info }).catch(() => {});
    }
  }

  chrome.storage.local.get(['darkMode', 'adBlocker', 'customCSS'], applySettings);
  chrome.storage.onChanged.addListener(() => {
    chrome.storage.local.get(['darkMode', 'adBlocker', 'customCSS'], applySettings);
  });

  setInterval(pollTrack, 1000);
  pollTrack();
})();
