const ids = ['adBlocker', 'darkMode', 'trackParser', 'webhookEnabled', 'webhookUrl', 'customCSS'];

function renderNowPlaying(track) {
  const card = document.getElementById('nowCard');
  if (!track || !track.title) {
    card.innerHTML = '<div class="muted">Open soundcloud.com and play a track</div>';
    return;
  }
  const status = track.isPlaying ? '▶️ Playing' : '⏸️ Paused';
  card.innerHTML = `
    <div class="muted">${status} • ${track.elapsed || '0:00'} / ${track.duration || '0:00'}</div>
    <div class="now-title">${escapeHtml(track.parsedTrack || track.title)}</div>
    <div class="now-artist">${escapeHtml(track.parsedArtist || track.author)}</div>
  `;
}

function escapeHtml(s) {
  return String(s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

chrome.storage.local.get([...ids, 'currentTrack'], (data) => {
  document.getElementById('adBlocker').checked = data.adBlocker !== false;
  document.getElementById('darkMode').checked = data.darkMode !== false;
  document.getElementById('trackParser').checked = data.trackParser !== false;
  document.getElementById('webhookEnabled').checked = !!data.webhookEnabled;
  document.getElementById('webhookUrl').value = data.webhookUrl || '';
  document.getElementById('customCSS').value = data.customCSS || '';
  renderNowPlaying(data.currentTrack);
});

for (const id of ids) {
  const el = document.getElementById(id);
  const evt = el.type === 'checkbox' ? 'change' : 'input';
  el.addEventListener(evt, () => {
    const val = el.type === 'checkbox' ? el.checked : el.value;
    chrome.storage.local.set({ [id]: val });
    if (id === 'adBlocker') {
      chrome.runtime.sendMessage({ type: 'SET_ADBLOCK', enabled: val });
    }
  });
}
