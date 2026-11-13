<script>
  import { onMount, onDestroy } from 'svelte';
  import { loadLeaflet } from '$lib/leaflet.js';
  import { api } from '$lib/api.js';

  const DEFAULT_CENTER = [31.6904, -106.4245]; // Ciudad Juárez, Chihuahua
  const DEFAULT_ZOOM = 12;
  const COLORS = ['#0d9488', '#2563eb', '#dc2626', '#d97706', '#7c3aed', '#db2777'];

  let geofences = $state([]);
  let events = $state([]);
  let error = $state('');
  let notice = $state('');
  let saving = $state(false);
  let drawing = $state(false);
  let vertices = $state([]); // [[lat, lng], ...]
  let form = $state({ name: '', description: '', color: COLORS[0] });
  let insideNow = $state({}); // geofence_id -> bool
  let watching = $state(false);
  let lastCheck = $state(null);
  let subject = $state('');

  let L;
  let mapEl;
  let map;
  let fenceLayer;
  let drawLayer;
  let userMarker;
  let watchId = null;
  let lastCheckAt = 0;

  function toLatLngs(polygon) {
    return (polygon || []).map((v) => [Number(v[0]), Number(v[1])]);
  }

  function renderFences() {
    if (!fenceLayer) return;
    fenceLayer.clearLayers();
    for (const g of geofences) {
      const pts = toLatLngs(g.polygon);
      if (pts.length < 3) continue;
      const poly = L.polygon(pts, {
        color: g.color || '#0d9488',
        weight: 2,
        fillColor: g.color || '#0d9488',
        fillOpacity: g.active ? 0.18 : 0.05,
        dashArray: g.active ? null : '6 6'
      }).addTo(fenceLayer);
      const inside = insideNow[g.id] ? ' · <strong style="color:#059669">dentro</strong>' : '';
      poly.bindPopup(
        `<div class="gf-popup"><strong>${escapeHtml(g.name)}</strong>` +
        (g.description ? `<span>${escapeHtml(g.description)}</span>` : '') +
        `<span class="muted">${g.active ? 'Activa' : 'Inactiva'}${inside}</span></div>`,
        { maxWidth: 260 }
      );
      poly._gfId = g.id;
    }
  }

  function renderDraw() {
    if (!drawLayer) return;
    drawLayer.clearLayers();
    if (vertices.length) {
      const pts = vertices.map((v) => [v[0], v[1]]);
      L.polyline(pts, { color: '#f59e0b', weight: 2, dashArray: '6 6' }).addTo(drawLayer);
      for (const [lat, lng] of pts) {
        L.circleMarker([lat, lng], { radius: 4, color: '#f59e0b', fillOpacity: 1 }).addTo(drawLayer);
      }
      if (vertices.length >= 3) {
        L.polygon(pts, { color: '#f59e0b', weight: 2, fillOpacity: 0.12 }).addTo(drawLayer);
      }
    }
  }

  function escapeHtml(s) {
    return String(s ?? '')
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  async function load() {
    try {
      const [{ data: gf }, { data: ev }] = await Promise.all([
        api('/geofences'),
        api('/geofence-events')
      ]);
      geofences = gf;
      events = ev || [];
      renderFences();
    } catch (e) { error = e.message; }
  }

  function startDraw() {
    drawing = true;
    vertices = [];
    notice = 'Haz clic en el mapa para agregar vértices. Con 3+ puedes cerrar el polígono.';
  }

  function cancelDraw() {
    drawing = false;
    vertices = [];
    renderDraw();
  }

  async function saveGeofence(e) {
    e.preventDefault();
    if (vertices.length < 3) {
      error = 'Dibuja el polígono con al menos 3 vértices.';
      return;
    }
    error = '';
    notice = '';
    saving = true;
    try {
      await api('/geofences', {
        method: 'POST',
        body: { ...form, polygon: vertices }
      });
      form = { name: '', description: '', color: COLORS[0] };
      cancelDraw();
      notice = 'Geocerca guardada correctamente.';
      await load();
    } catch (err) { error = err.message; }
    finally { saving = false; }
  }

  async function remove(g) {
    if (!confirm(`¿Eliminar la geocerca "${g.name}" y todos sus eventos?`)) return;
    try {
      await api(`/geofences/${g.id}`, { method: 'DELETE' });
      geofences = geofences.filter((x) => x.id !== g.id);
      delete insideNow[g.id];
      renderFences();
      notice = 'Geocerca eliminada.';
      error = '';
      await load();
    } catch (e) { error = e.message; }
  }

  async function toggleActive(g) {
    try {
      const { data } = await api(`/geofences/${g.id}`, {
        method: 'PATCH',
        body: { active: !g.active }
      });
      geofences = geofences.map((x) => (x.id === g.id ? data : x));
      renderFences();
    } catch (e) { error = e.message; }
  }

  function focus(g) {
    const pts = toLatLngs(g.polygon);
    if (pts.length) map.fitBounds(L.latLngBounds(pts).pad(0.2));
    const layer = fenceLayer.getLayers().find((l) => l._gfId === g.id);
    if (layer) layer.openPopup();
  }

  // ---------- Vigilancia GPS ----------
  function startWatching() {
    if (!navigator.geolocation) {
      error = 'Tu navegador no soporta geolocalización.';
      return;
    }
    const u = JSON.parse(localStorage.getItem('user') || '{}');
    subject = u.full_name || u.email || 'desconocido';
    watching = true;
    notice = `Vigilando como "${subject}". Las entradas y salidas se registrarán automáticamente.`;
    watchId = navigator.geolocation.watchPosition(onPosition, onGeoError, {
      enableHighAccuracy: true,
      maximumAge: 10000,
      timeout: 20000
    });
  }

  function stopWatching() {
    if (watchId !== null) navigator.geolocation.clearWatch(watchId);
    watchId = null;
    watching = false;
    notice = 'Vigilancia detenida.';
  }

  async function onPosition(pos) {
    const { latitude, longitude, accuracy } = pos.coords;
    if (accuracy && accuracy > 80) return; // señal muy imprecisa
    const now = Date.now();
    if (now - lastCheckAt < 8000) return; // máx. 1 check cada 8s
    lastCheckAt = now;
    lastCheck = { latitude, longitude, at: new Date() };

    if (!userMarker) {
      userMarker = L.circleMarker([latitude, longitude], {
        radius: 8, color: '#fff', weight: 2, fillColor: '#2563eb', fillOpacity: 0.9
      }).addTo(map);
    } else {
      userMarker.setLatLng([latitude, longitude]);
    }

    try {
      const { data } = await api('/geofences/check', {
        method: 'POST',
        body: { subject, latitude, longitude }
      });
      const next = {};
      let changed = false;
      for (const r of data) {
        if (insideNow[r.geofence_id] !== r.inside) changed = true;
        next[r.geofence_id] = r.inside;
      }
      insideNow = next;
      renderFences();
      if (changed) {
        notice = 'Cambio de geocerca detectado — evento registrado.';
        const { data: ev } = await api('/geofence-events');
        events = ev || [];
      }
    } catch (e) { error = e.message; }
  }

  function onGeoError(err) {
    if (err.code === err.PERMISSION_DENIED) {
      error = 'Permiso de ubicación denegado. Actívalo en el navegador para usar la vigilancia.';
      stopWatching();
    }
  }

  onMount(async () => {
    try {
      L = await loadLeaflet();
      map = L.map(mapEl, { zoomControl: true }).setView(DEFAULT_CENTER, DEFAULT_ZOOM);
      L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
        maxZoom: 19,
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
      }).addTo(map);
      fenceLayer = L.layerGroup().addTo(map);
      drawLayer = L.layerGroup().addTo(map);
      map.on('click', (e) => {
        if (!drawing) return;
        vertices = [...vertices, [e.latlng.lat, e.latlng.lng]];
        renderDraw();
      });

      await load();
      setTimeout(() => map.invalidateSize(), 100);
    } catch (e) { error = e.message; }
  });

  onDestroy(() => {
    if (watchId !== null) navigator.geolocation.clearWatch(watchId);
    if (map) map.remove();
  });
</script>

<div class="page-head">
  <h1>Geocercas</h1>
  <p>Dibuja zonas en el mapa y registra automáticamente cuándo alguien entra o sale de ellas</p>
</div>

{#if notice}<p class="ok">{notice}</p>{/if}
{#if error}<p class="err">{error}</p>{/if}

<div class="grid">
  <section class="card">
    <h2>Nueva geocerca</h2>
    {#if drawing}
      <p class="muted hint">Dibujando: {vertices.length} vértice(s). Haz clic en el mapa para agregar.</p>
      <div class="btn-row">
        <button type="button" class="btn btn-accent" disabled={vertices.length < 3} onclick={() => { /* el form envía */ document.getElementById('gf-form').requestSubmit(); }}>
          Cerrar y guardar
        </button>
        <button type="button" class="btn btn-ghost" onclick={cancelDraw}>Cancelar</button>
      </div>
    {:else}
      <p class="muted hint">Pulsa “Dibujar polígono” y haz clic en el mapa para marcar los vértices.</p>
      <button type="button" class="btn btn-accent btn-block" onclick={startDraw}>Dibujar polígono</button>
    {/if}

    <form id="gf-form" onsubmit={saveGeofence} class:off={drawing && vertices.length < 3}>
      <label class="field">Nombre
        <input bind:value={form.name} required placeholder="Ej. Laboratorio de cómputo" />
      </label>
      <label class="field">Descripción (opcional)
        <input bind:value={form.description} placeholder="Ej. Edificio D, planta baja" />
      </label>
      <label class="field">Color
        <div class="colors">
          {#each COLORS as c}
            <button type="button" class="swatch" class:sel={form.color === c} style="background:{c}" onclick={() => (form.color = c)} aria-label="Color {c}"></button>
          {/each}
        </div>
      </label>
      <button type="submit" class="btn btn-accent btn-block" disabled={saving || !drawing}>
        {saving ? 'Guardando…' : 'Guardar geocerca'}
      </button>
    </form>

    <div class="list">
      <h2>Geocercas ({geofences.length})</h2>
      {#each geofences as g (g.id)}
        <div class="gf">
          <button type="button" class="gf-info" onclick={() => focus(g)}>
            <span class="dot" style="background:{g.color}"></span>
            <span class="gf-text">
              <strong>{g.name}{#if insideNow[g.id]} <em class="inside-tag">dentro</em>{/if}</strong>
              <span class="muted">{g.description || `${(g.polygon || []).length} vértices`} · {g.active ? 'Activa' : 'Inactiva'}</span>
            </span>
          </button>
          <span class="gf-actions">
            <button type="button" class="link" onclick={() => toggleActive(g)}>{g.active ? 'Desactivar' : 'Activar'}</button>
            <button type="button" class="link danger" onclick={() => remove(g)}>Eliminar</button>
          </span>
        </div>
      {:else}
        <p class="muted">No hay geocercas registradas.</p>
      {/each}
    </div>
  </section>

  <section class="card map-card">
    <div class="map-wrap">
      <div bind:this={mapEl} class="map"></div>
    </div>
    <div class="map-bar">
      <p class="muted map-note">Usa la rueda del ratón o los controles del mapa para acercar y alejar.</p>
      <button type="button" class="btn {watching ? 'btn-stop' : 'btn-accent'}" onclick={watching ? stopWatching : startWatching}>
        {watching ? 'Detener vigilancia' : 'Vigilar mi ubicación'}
      </button>
    </div>
    {#if watching}
      <p class="watching muted">
        Vigilando como <strong>{subject}</strong>
        {#if lastCheck} · última posición {lastCheck.at.toLocaleTimeString()}{/if}
      </p>
    {/if}
  </section>
</div>

<section class="card events-card">
  <h2>Registro de entradas y salidas ({events.length})</h2>
  <div class="table-wrap">
    <table>
      <thead>
        <tr><th>Fecha</th><th>Geocerca</th><th>Persona</th><th>Evento</th><th>Ubicación</th></tr>
      </thead>
      <tbody>
        {#each events as ev (ev.id)}
          <tr>
            <td>{new Date(ev.occurred_at).toLocaleString()}</td>
            <td><span class="dot" style="background:{ev.geofences?.color || '#0d9488'}"></span> {ev.geofences?.name || '—'}</td>
            <td>{ev.subject}</td>
            <td><span class="tag {ev.event_type === 'enter' ? 'tag-enter' : 'tag-exit'}">{ev.event_type === 'enter' ? 'Entrada' : 'Salida'}</span></td>
            <td class="muted">{Number(ev.latitude).toFixed(5)}, {Number(ev.longitude).toFixed(5)}</td>
          </tr>
        {:else}
          <tr><td colspan="5" class="muted">Aún no hay eventos registrados.</td></tr>
        {/each}
      </tbody>
    </table>
  </div>
</section>

<style>
  .grid {
    display: grid; grid-template-columns: 380px 1fr; gap: 1.25rem;
    align-items: start;
  }
  .field { display: block; margin: 0.8rem 0 0.2rem; }
  h2 { margin: 0 0 0.5rem; font-size: 1.05rem; color: var(--navy-900); }
  .hint { font-size: 0.8rem; margin: 0 0 0.4rem; }
  .btn-block { width: 100%; margin-top: 0.9rem; justify-content: center; }
  .btn-row { display: flex; gap: 0.6rem; margin: 0.6rem 0; }
  form.off { opacity: 0.55; pointer-events: none; }

  .colors { display: flex; gap: 0.5rem; padding-top: 0.3rem; }
  .swatch {
    width: 26px; height: 26px; border-radius: 50%; border: 2px solid transparent;
    cursor: pointer; padding: 0;
  }
  .swatch.sel { border-color: var(--navy-900); box-shadow: 0 0 0 2px #fff inset; }

  .list { margin-top: 1.4rem; border-top: 1px solid var(--border); padding-top: 1rem; }
  .gf {
    display: flex; align-items: center; justify-content: space-between; gap: 0.6rem;
    padding: 0.6rem 0.4rem; border-bottom: 1px solid var(--border);
  }
  .gf-info {
    background: none; border: 0; padding: 0; text-align: left; cursor: pointer;
    display: flex; align-items: center; gap: 0.6rem; flex: 1; min-width: 0;
    font: inherit; color: var(--text);
  }
  .gf-text { display: flex; flex-direction: column; gap: 0.1rem; min-width: 0; }
  .gf-text strong { color: var(--navy-900); font-size: 0.88rem; }
  .gf-text span { font-size: 0.78rem; }
  .gf-info:hover strong { color: var(--turquoise); }
  .gf-actions { display: flex; gap: 0.7rem; flex-shrink: 0; }
  .dot {
    width: 12px; height: 12px; border-radius: 50%; flex-shrink: 0;
    display: inline-block; vertical-align: middle;
  }
  .inside-tag {
    font-style: normal; font-size: 0.7rem; font-weight: 700; color: #059669;
    background: #d1fae5; padding: 0.1rem 0.45rem; border-radius: 999px;
  }
  .link {
    background: none; border: 0; color: var(--turquoise);
    cursor: pointer; padding: 0; font: inherit; font-size: 0.8rem; font-weight: 600;
  }
  .link:hover { text-decoration: underline; }
  .link.danger { color: var(--danger); }

  .map-card { padding: 0.9rem; }
  .map-wrap { border-radius: 10px; overflow: hidden; border: 1px solid var(--border); }
  .map { height: 560px; width: 100%; background: var(--panel-2); }
  .map-bar { display: flex; align-items: center; justify-content: space-between; gap: 1rem; margin-top: 0.7rem; flex-wrap: wrap; }
  .map-note { font-size: 0.78rem; margin: 0; }
  .btn-stop { background: var(--danger); color: #fff; border-color: var(--danger); }
  .watching { font-size: 0.8rem; margin: 0.5rem 0 0; }

  .events-card { margin-top: 1.25rem; }
  .table-wrap { overflow-x: auto; }
  table { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
  th, td { text-align: left; padding: 0.55rem 0.6rem; border-bottom: 1px solid var(--border); }
  th { color: var(--navy-900); font-size: 0.78rem; text-transform: uppercase; letter-spacing: .04em; }
  .tag { font-size: 0.75rem; font-weight: 700; padding: 0.15rem 0.55rem; border-radius: 999px; }
  .tag-enter { background: #d1fae5; color: #065f46; }
  .tag-exit { background: #fee2e2; color: #991b1b; }

  :global(.gf-popup) { display: flex; flex-direction: column; gap: 0.15rem; min-width: 160px; }
  :global(.gf-popup strong) { color: var(--navy-900); font-size: 0.9rem; }
  :global(.gf-popup span) { color: var(--muted); font-size: 0.8rem; }
  :global(.leaflet-popup-content-wrapper) { border-radius: 10px; box-shadow: var(--shadow); }
  :global(.leaflet-popup-content) { margin: 0.7rem 0.9rem; line-height: 1.35; }
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
