<script>
  import { onMount, onDestroy } from 'svelte';
  import { loadLeaflet } from '$lib/leaflet.js';
  import { api } from '$lib/api.js';

  const DEFAULT_CENTER = [31.6904, -106.4245]; // Ciudad Juárez, Chihuahua
  const DEFAULT_ZOOM = 12;

  let institutions = $state([]);
  let error = $state('');
  let notice = $state('');
  let saving = $state(false);
  let picked = $state(null); // { lat, lng } al hacer clic en el mapa
  let form = $state({ name: '', address: '', latitude: '', longitude: '' });

  let L;
  let mapEl;
  let map;
  let layer;
  let previewMarker;
  let pinIcon;

  function createPinIcon() {
    return L.divIcon({
      className: 'inst-pin',
      html: '<svg viewBox="0 0 24 24" width="26" height="26" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z"/><circle cx="12" cy="10" r="3"/></svg>',
      iconSize: [34, 42],
      iconAnchor: [17, 40],
      popupAnchor: [0, -38]
    });
  }

  function toLatLng(row) {
    return [Number(row.latitude), Number(row.longitude)];
  }

  function popupHtml(row) {
    return `<div class="inst-popup"><strong>${escapeHtml(row.name)}</strong><span>${escapeHtml(row.address)}</span></div>`;
  }

  function escapeHtml(s) {
    return String(s ?? '')
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function renderMarkers() {
    if (!layer) return;
    layer.clearLayers();
    for (const inst of institutions) {
      const marker = L.marker(toLatLng(inst), { icon: pinIcon })
        .bindPopup(popupHtml(inst), { maxWidth: 260 })
        .addTo(layer);
      marker._instId = inst.id;
    }
    if (institutions.length && !userLocated) {
      map.fitBounds(L.latLngBounds(institutions.map(toLatLng)).pad(0.15));
    }
  }

  function setPicked(latlng) {
    picked = { lat: latlng.lat, lng: latlng.lng };
    form.latitude = latlng.lat.toFixed(6);
    form.longitude = latlng.lng.toFixed(6);
    if (previewMarker) layer.removeLayer(previewMarker);
    previewMarker = L.marker([latlng.lat, latlng.lng], { icon: pinIcon })
      .bindPopup('<em>Ubicación seleccionada</em>')
      .addTo(layer)
      .openPopup();
  }

  async function load() {
    try {
      const { data } = await api('/institutions');
      institutions = data;
      renderMarkers();
    } catch (e) { error = e.message; }
  }

  async function create(e) {
    e.preventDefault();
    error = '';
    notice = '';
    saving = true;
    try {
      await api('/institutions', {
        method: 'POST',
        body: {
          name: form.name,
          address: form.address,
          latitude: Number(form.latitude),
          longitude: Number(form.longitude)
        }
      });
      form = { name: '', address: '', latitude: '', longitude: '' };
      picked = null;
      if (previewMarker) { layer.removeLayer(previewMarker); previewMarker = null; }
      notice = 'Institución agregada correctamente.';
      await load();
    } catch (err) { error = err.message; }
    finally { saving = false; }
  }

  async function remove(inst) {
    if (!confirm(`¿Eliminar "${inst.name}" del mapa?`)) return;
    try {
      await api(`/institutions/${inst.id}`, { method: 'DELETE' });
      institutions = institutions.filter((i) => i.id !== inst.id);
      renderMarkers();
      notice = 'Institución eliminada.';
      error = '';
    } catch (e) { error = e.message; }
  }

  function focus(inst) {
    map.setView(toLatLng(inst), Math.max(map.getZoom(), 15));
    const marker = layer.getLayers().find((m) => m._instId === inst.id);
    if (marker) marker.openPopup();
  }

  let userLocated = $state(false);

  function locateUser() {
    if (!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        userLocated = true;
        map.setView([pos.coords.latitude, pos.coords.longitude], 14);
        notice = 'Mapa centrado en tu ubicación.';
      },
      () => { /* permiso denegado o sin señal: se mantiene Ciudad Juárez */ },
      { enableHighAccuracy: false, timeout: 10000, maximumAge: 300000 }
    );
  }

  onMount(async () => {
    try {
      L = await loadLeaflet();
      pinIcon = createPinIcon();
      map = L.map(mapEl, { zoomControl: true }).setView(DEFAULT_CENTER, DEFAULT_ZOOM);
      L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
        maxZoom: 19,
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
      }).addTo(map);
      layer = L.layerGroup().addTo(map);
      map.on('click', (e) => setPicked(e.latlng));

      locateUser();
      await load();
      setTimeout(() => map.invalidateSize(), 100);
    } catch (e) { error = e.message; }
  });

  onDestroy(() => { if (map) map.remove(); });
</script>

<div class="page-head">
  <h1>Mapa de Instituciones</h1>
  <p>Visualiza y administra las instituciones educativas en el mapa</p>
</div>

{#if notice}<p class="ok">{notice}</p>{/if}
{#if error}<p class="err">{error}</p>{/if}

<div class="grid">
  <section class="card">
    <h2>Nueva institución</h2>
    <p class="muted hint">Haz clic en el mapa para elegir la ubicación, o captura las coordenadas manualmente.</p>
    <form onsubmit={create}>
      <label class="field">Nombre
        <input bind:value={form.name} required placeholder="Ej. Universidad Autónoma de Ciudad Juárez" />
      </label>
      <label class="field">Dirección
        <input bind:value={form.address} required placeholder="Ej. Av. Universidad s/n, Cd. Juárez, Chih." />
      </label>
      <div class="row">
        <label class="field">Latitud
          <input type="number" step="any" min="-90" max="90" bind:value={form.latitude} required placeholder="31.690400" />
        </label>
        <label class="field">Longitud
          <input type="number" step="any" min="-180" max="180" bind:value={form.longitude} required placeholder="-106.424500" />
        </label>
      </div>
      {#if picked}
        <p class="picked">Ubicación elegida: {picked.lat.toFixed(5)}, {picked.lng.toFixed(5)}</p>
      {/if}
      <button type="submit" class="btn btn-accent btn-block" disabled={saving}>
        {saving ? 'Guardando…' : 'Agregar al mapa'}
      </button>
    </form>

    <div class="list">
      <h2>Instituciones ({institutions.length})</h2>
      {#each institutions as inst (inst.id)}
        <div class="inst">
          <button type="button" class="inst-info" onclick={() => focus(inst)}>
            <strong>{inst.name}</strong>
            <span class="muted">{inst.address}</span>
          </button>
          <button type="button" class="link danger" onclick={() => remove(inst)}>Eliminar</button>
        </div>
      {:else}
        <p class="muted">No hay instituciones registradas.</p>
      {/each}
    </div>
  </section>

  <section class="card map-card">
    <div class="map-wrap">
      <div bind:this={mapEl} class="map"></div>
    </div>
    <p class="muted map-note">Usa la rueda del ratón o los controles del mapa para acercar y alejar.</p>
  </section>
</div>

<style>
  .grid {
    display: grid; grid-template-columns: 380px 1fr; gap: 1.25rem;
    align-items: start;
  }
  .field { display: block; margin: 0.8rem 0 0.2rem; }
  h2 { margin: 0 0 0.5rem; font-size: 1.05rem; color: var(--navy-900); }
  .hint { font-size: 0.8rem; margin: 0 0 0.4rem; }
  .row { display: grid; grid-template-columns: 1fr 1fr; gap: 0.75rem; }
  .btn-block { width: 100%; margin-top: 1.1rem; justify-content: center; }
  .picked { font-size: 0.8rem; color: var(--turquoise); font-weight: 600; margin: 0.6rem 0 0; }

  .list { margin-top: 1.5rem; border-top: 1px solid var(--border); padding-top: 1rem; }
  .inst {
    display: flex; align-items: center; justify-content: space-between; gap: 0.6rem;
    padding: 0.6rem 0.4rem; border-bottom: 1px solid var(--border);
  }
  .inst-info {
    background: none; border: 0; padding: 0; text-align: left; cursor: pointer;
    display: flex; flex-direction: column; gap: 0.1rem; flex: 1; min-width: 0;
    font: inherit; color: var(--text);
  }
  .inst-info strong { color: var(--navy-900); font-size: 0.88rem; }
  .inst-info span { font-size: 0.78rem; }
  .inst-info:hover strong { color: var(--turquoise); }
  .link {
    background: none; border: 0; color: var(--turquoise);
    cursor: pointer; padding: 0; font: inherit; font-size: 0.8rem; font-weight: 600; flex-shrink: 0;
  }
  .link:hover { text-decoration: underline; }
  .link.danger { color: var(--danger); }

  .map-card { padding: 0.9rem; }
  .map-wrap { border-radius: 10px; overflow: hidden; border: 1px solid var(--border); }
  .map { height: 560px; width: 100%; background: var(--panel-2); }
  .map-note { font-size: 0.78rem; margin: 0.6rem 0 0; }

  :global(.inst-pin) {
    background: transparent; border: 0;
    display: flex; align-items: flex-start; justify-content: center;
  }
  :global(.inst-pin svg) {
    filter: drop-shadow(0 2px 3px rgba(11, 37, 69, .35));
  }
  :global(.leaflet-popup-content-wrapper) {
    border-radius: 10px; box-shadow: var(--shadow);
  }
  :global(.leaflet-popup-content) { margin: 0.7rem 0.9rem; line-height: 1.35; }
  :global(.inst-popup) { display: flex; flex-direction: column; gap: 0.15rem; min-width: 160px; }
  :global(.inst-popup strong) { color: var(--navy-900); font-size: 0.9rem; }
  :global(.inst-popup span) { color: var(--muted); font-size: 0.8rem; }
  :global(.leaflet-control-zoom a) {
    color: var(--navy-800) !important;
    border-color: var(--border) !important;
  }
  :global(.leaflet-control-attribution) { font-size: 0.65rem; }

  @media (max-width: 900px) {
    .grid { grid-template-columns: 1fr; }
    .map { height: 420px; }
  }
</style>
