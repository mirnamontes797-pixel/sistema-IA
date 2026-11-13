<script>
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { api, getToken, API_BASE } from '$lib/api.js';

  let courses = $state([]);
  let documents = $state({});
  let error = $state('');
  let notice = $state('');
  let uploadStates = $state({});
  let analyzingStates = $state({});
  let currentUser = $state(null);
  let form = $state({ name: '', description: '', cuatrimestre_weeks: 16, total_hours: 64 });

  function canManageDocument(course) {
    return currentUser?.role === 'admin' || course.instructor_id === currentUser?.id;
  }

  async function loadDocuments(course) {
    if (!canManageDocument(course)) {
      documents[course.id] = null;
      return;
    }
    try {
      const { data } = await api(`/courses/${course.id}/documents`);
      documents[course.id] = data;
    } catch (e) { error = e.message; }
  }

  function formatSize(bytes) {
    if (!bytes) return '—';
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }

  function formatDate(value) {
    return new Date(value).toLocaleString('es-MX', { dateStyle: 'medium', timeStyle: 'short' });
  }

  async function uploadDocument(event, course) {
    const file = event.currentTarget.files?.[0];
    event.currentTarget.value = '';
    if (!file) return;
    const allowed = ['pdf', 'docx', 'xlsx'];
    const extension = file.name.split('.').pop()?.toLowerCase();
    if (!allowed.includes(extension)) {
      error = 'Solo se permiten archivos PDF, Word (.docx) o Excel (.xlsx).';
      notice = '';
      return;
    }
    if (file.size > 25 * 1024 * 1024) {
      error = 'El archivo no puede superar 25 MB.';
      notice = '';
      return;
    }
    uploadStates[course.id] = true;
    error = '';
    notice = '';
    try {
      const formData = new FormData();
      formData.append('file', file);
      const result = await api(`/courses/${course.id}/documents`, { method: 'POST', body: formData, formData: true });
      documents[course.id] = result.data;
      notice = result.message || 'Documento cargado correctamente.';
    } catch (e) {
      error = e.message || 'No se pudo cargar el documento.';
    } finally {
      uploadStates[course.id] = false;
    }
  }

  async function replaceDocument(course) {
    document.querySelector(`input[data-course-file="${course.id}"]`)?.click();
  }

  async function openDocument(course, download) {
    try {
      const response = await fetch(`${API_BASE}/courses/${course.id}/documents/${documents[course.id].id}/file?download=${download}`, {
        headers: { Authorization: `Bearer ${getToken()}` }
      });
      if (!response.ok) throw new Error('No se pudo abrir el documento');
      const blob = await response.blob();
      const url = URL.createObjectURL(blob);
      if (download) {
        const link = document.createElement('a');
        link.href = url;
        link.download = documents[course.id].name;
        link.click();
      } else {
        window.open(url, '_blank');
      }
      setTimeout(() => URL.revokeObjectURL(url), 60000);
    } catch (e) { error = e.message; }
  }

  function viewDocument(course) { return openDocument(course, false); }
  function downloadDocument(course) { return openDocument(course, true); }

  async function analyzeDocument(course) {
    analyzingStates[course.id] = true;
    error = '';
    notice = '';
    try {
      const result = await api(`/courses/${course.id}/documents/analyze`, { method: 'POST' });
      sessionStorage.setItem(`analysis:${course.id}`, JSON.stringify(result.data));
      goto(`/cursos/${course.id}/analisis`);
    } catch (e) {
      error = e.message || 'No se pudo analizar la carta descriptiva.';
    } finally {
      analyzingStates[course.id] = false;
    }
  }

  async function removeDocument(course) {
    if (!confirm(`¿Eliminar la carta descriptiva de "${course.name}"?`)) return;
    try {
      const result = await api(`/courses/${course.id}/documents/${documents[course.id].id}`, { method: 'DELETE' });
      documents[course.id] = null;
      notice = result.message || 'Documento eliminado correctamente.';
      error = '';
    } catch (e) { error = e.message; }
  }

  async function load() {
    try {
      const { data } = await api('/courses');
      courses = data;
      await Promise.all(data.map((course) => loadDocuments(course)));
    } catch (e) { error = e.message; }
  }
  onMount(() => {
    const raw = localStorage.getItem('user');
    currentUser = raw ? JSON.parse(raw) : null;
    load();
  });

  async function create(e) {
    e.preventDefault();
    error = '';
    try {
      await api('/courses', { method: 'POST', body: form });
      form = { name: '', description: '', cuatrimestre_weeks: 16, total_hours: 64 };
      load();
    } catch (err) { error = err.message; }
  }
</script>

<div class="page-head">
  <h1>Cursos</h1>
  <p>Gestiona los cursos del cuatrimestre y sus cartas descriptivas</p>
</div>

{#if notice}<p class="ok">{notice}</p>{/if}
{#if error}<p class="err">{error}</p>{/if}

<div class="grid">
  <section class="card">
    <h2>Nuevo curso</h2>
    <form onsubmit={create}>
      <label class="field">Nombre
        <input bind:value={form.name} required placeholder="Ej. Train the Trainers" />
      </label>
      <label class="field">Descripción
        <input bind:value={form.description} placeholder="Opcional" />
      </label>
      <div class="row">
        <label class="field">Semanas del cuatrimestre
          <input type="number" min="1" max="30" bind:value={form.cuatrimestre_weeks} />
        </label>
        <label class="field">Horas totales
          <input type="number" min="1" step="0.5" bind:value={form.total_hours} />
        </label>
      </div>
      <button type="submit" class="btn btn-accent btn-block">Crear curso</button>
    </form>
  </section>

  <section class="course-list">
    {#each courses as c (c.id)}
      <div class="card course">
        <div class="course-head">
          <span class="course-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="22" height="22"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20M4 19.5A2.5 2.5 0 0 0 6.5 22H20V2H6.5A2.5 2.5 0 0 0 4 4.5v15Z"/></svg>
          </span>
          <div class="course-info">
            <h3>{c.name}</h3>
            <p class="muted">{c.cuatrimestre_weeks} semanas · {c.total_hours} h{c.description ? ' · ' + c.description : ''}</p>
          </div>
          {#if documents[c.id]}<span class="badge badge-turq">Con carta descriptiva</span>{/if}
        </div>
        <div class="actions">
          {#if canManageDocument(c)}
            <label class="btn btn-ghost btn-sm" class:disabled={uploadStates[c.id]}>
              {uploadStates[c.id] ? 'Subiendo…' : documents[c.id] ? 'Reemplazar carta' : 'Subir carta descriptiva'}
              <input type="file" accept=".pdf,.docx,.xlsx" data-course-file={c.id} hidden disabled={uploadStates[c.id]} onchange={(e) => uploadDocument(e, c)} />
            </label>
          {/if}
          <a href="/cursos/{c.id}/configuracion" class="btn btn-ghost btn-sm">Configurar</a>
          <a href="/cursos/{c.id}/plan" class="btn btn-accent btn-sm">Planear</a>
          <a href="/cursos/{c.id}/cronograma" class="btn btn-ghost btn-sm">Cronograma</a>
        </div>
        {#if documents[c.id]}
          <div class="document">
            <div class="doc-info">
              <strong>{documents[c.id].name}</strong>
              <p class="muted">{documents[c.id].format} · {formatSize(documents[c.id].sizeBytes)} · {formatDate(documents[c.id].uploadedAt)}</p>
            </div>
            <div class="doc-actions">
              <button type="button" class="link" onclick={() => viewDocument(c)}>Ver</button>
              <button type="button" class="link" onclick={() => downloadDocument(c)}>Descargar</button>
              <button
                type="button"
                class="btn btn-accent btn-sm"
                disabled={analyzingStates[c.id]}
                onclick={() => analyzeDocument(c)}
              >{analyzingStates[c.id] ? 'Analizando…' : 'Analizar carta descriptiva'}</button>
              <button type="button" class="link" onclick={() => replaceDocument(c)}>Reemplazar</button>
              <button type="button" class="link danger" onclick={() => removeDocument(c)}>Eliminar</button>
            </div>
          </div>
        {/if}
      </div>
    {:else}
      <div class="card empty-state">
        <p class="muted">No hay cursos todavía. Crea el primero desde el formulario.</p>
      </div>
    {/each}
  </section>
</div>

<style>
  .grid {
    display: grid; grid-template-columns: 330px 1fr; gap: 1.25rem;
    align-items: start;
  }
  .field { display: block; margin: 0.8rem 0 0.2rem; }
  h2 { margin: 0 0 0.5rem; font-size: 1.05rem; color: var(--navy-900); }
  .btn-block { width: 100%; margin-top: 1.1rem; justify-content: center; }
  .btn-sm { padding: 0.4rem 0.8rem; font-size: 0.8rem; }
  .btn.disabled { opacity: 0.6; pointer-events: none; }

  .course-list { display: flex; flex-direction: column; gap: 0.9rem; }
  .course { padding: 1.1rem 1.25rem; }
  .course-head { display: flex; align-items: center; gap: 0.9rem; }
  .course-icon {
    width: 44px; height: 44px; border-radius: 12px; flex-shrink: 0;
    background: linear-gradient(135deg, var(--navy-800), var(--navy-700));
    color: #fff; display: flex; align-items: center; justify-content: center;
  }
  .course-info { flex: 1; min-width: 0; }
  .course-info h3 { margin: 0; font-size: 1rem; color: var(--navy-900); }
  .course-info p { margin: 0.15rem 0 0; font-size: 0.82rem; }
  .actions { display: flex; gap: 0.5rem; align-items: center; flex-wrap: wrap; margin-top: 0.9rem; }

  .document {
    margin-top: 1rem; padding-top: 0.9rem;
    border-top: 1px dashed var(--border);
    display: flex; justify-content: space-between; align-items: center;
    gap: 1rem; flex-wrap: wrap;
  }
  .doc-info strong { font-size: 0.9rem; }
  .doc-info p { margin: 0.15rem 0 0; font-size: 0.78rem; }
  .doc-actions { display: flex; gap: 0.9rem; flex-wrap: wrap; }
  .link {
    background: none; border: 0; color: var(--turquoise);
    cursor: pointer; padding: 0; font: inherit; font-size: 0.85rem; font-weight: 600;
  }
  .link:hover { text-decoration: underline; }
  .link.danger { color: var(--danger); }

  .empty-state { text-align: center; padding: 2rem; }

  @media (max-width: 900px) {
    .grid { grid-template-columns: 1fr; }
  }
</style>
