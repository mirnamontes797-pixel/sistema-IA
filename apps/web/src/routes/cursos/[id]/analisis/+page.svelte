<script>
  import { page } from '$app/state';
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';

  const courseId = $derived(page.params.id);
  const storageKey = $derived(`analysis:${courseId}`);

  let courseName = $state('');
  let data = $state(null);
  let warnings = $state([]);
  let missing = $state([]);
  let engine = $state('');
  let error = $state('');
  let notice = $state('');
  let loading = $state(false);
  let saving = $state(false);
  let savedSummary = $state(null);

  const UNIT_LIST_FIELDS = ['objectives', 'topics', 'subtopics', 'outcomes', 'evaluationCriteria'];

  function toLines(arr) { return (arr || []).join('\n'); }
  function fromLines(text) {
    return (text || '').split('\n').map((s) => s.trim()).filter(Boolean);
  }

  async function runAnalysis() {
    loading = true;
    error = '';
    notice = '';
    try {
      const result = await api(`/courses/${courseId}/documents/analyze`, { method: 'POST' });
      applyResult(result.data, result.warnings || []);
      sessionStorage.setItem(storageKey, JSON.stringify(result.data));
    } catch (e) {
      error = e.message || 'No se pudo analizar la carta descriptiva.';
    } finally {
      loading = false;
    }
  }

  function applyResult(d, w = []) {
    data = {
      subjectName: d.subjectName || '',
      competencies: d.competencies || [],
      objectives: d.objectives || [],
      units: (d.units || []).map((u) => ({
        number: u.number,
        title: u.title || '',
        objectives: u.objectives || [],
        topics: u.topics || [],
        subtopics: u.subtopics || [],
        outcomes: u.outcomes || [],
        theoryHours: u.theoryHours ?? '',
        practiceHours: u.practiceHours ?? '',
        evaluationCriteria: u.evaluationCriteria || []
      }))
    };
    missing = d.missing || [];
    engine = d.engine || '';
    warnings = w;
    savedSummary = null;
  }

  onMount(async () => {
    try {
      const { data: courses } = await api('/courses');
      const c = (courses || []).find((x) => x.id === courseId);
      courseName = c?.name || '';
    } catch { /* silencioso */ }

    const raw = sessionStorage.getItem(storageKey);
    if (raw) {
      try { applyResult(JSON.parse(raw)); } catch { sessionStorage.removeItem(storageKey); }
    }
    if (!data) await runAnalysis();
  });

  function addUnit() {
    const next = Math.max(0, ...(data.units || []).map((u) => Number(u.number) || 0)) + 1;
    data.units = [...(data.units || []), {
      number: next, title: '', objectives: [], topics: [], subtopics: [],
      outcomes: [], theoryHours: '', practiceHours: '', evaluationCriteria: []
    }];
  }
  function removeUnit(i) { data.units = data.units.filter((_, idx) => idx !== i); }

  function buildPayload() {
    return {
      subjectName: data.subjectName,
      competencies: data.competencies,
      objectives: data.objectives,
      units: data.units.map((u) => ({
        number: Number(u.number) || 0,
        title: u.title,
        objectives: u.objectives,
        topics: u.topics,
        subtopics: u.subtopics,
        outcomes: u.outcomes,
        theoryHours: u.theoryHours === '' ? null : Number(u.theoryHours),
        practiceHours: u.practiceHours === '' ? null : Number(u.practiceHours),
        evaluationCriteria: u.evaluationCriteria
      }))
    };
  }

  async function save() {
    if (!data.units.length) { error = 'Agrega al menos una unidad antes de guardar.'; return; }
    saving = true;
    error = '';
    notice = '';
    try {
      const result = await api(`/courses/${courseId}/academic-data`, { method: 'POST', body: buildPayload() });
      savedSummary = result.summary || {};
      notice = result.message || 'Información académica guardada correctamente.';
      sessionStorage.removeItem(storageKey);
    } catch (e) {
      error = e.message || 'No se pudo guardar la información.';
    } finally {
      saving = false;
    }
  }
</script>

<div class="page-head">
  <h1>Información académica extraída</h1>
  <p>{courseName ? `Curso: ${courseName}` : 'Revisa y confirma los datos leídos de la carta descriptiva'}</p>
</div>

{#if error}<p class="err">{error}</p>{/if}
{#if notice}<p class="ok">{notice}</p>{/if}

{#if savedSummary}
  <section class="card summary">
    <h2>Resumen del guardado</h2>
    <ul>
      <li>Unidades creadas: {savedSummary.unitsCreated ?? 0}</li>
      <li>Unidades actualizadas: {savedSummary.unitsUpdated ?? 0}</li>
      <li>Resultados de aprendizaje agregados: {savedSummary.outcomesAdded ?? 0}</li>
      <li>Actividades de horas agregadas: {savedSummary.activitiesAdded ?? 0}</li>
      <li>Rúbricas de criterios agregadas: {savedSummary.rubricsAdded ?? 0}</li>
    </ul>
    <div class="actions-row">
      <a href="/cursos/{courseId}/plan" class="btn btn-accent">Ir a Planear</a>
      <a href="/cursos" class="btn btn-ghost">Volver a Cursos</a>
    </div>
  </section>
{/if}

{#if loading}
  <section class="card"><p class="muted">Leyendo y analizando el documento… Esto puede tardar unos segundos.</p></section>
{:else if data}
  <div class="toolbar">
    <p class="muted small">
      Documento analizado{data.documentName ? `: ${data.documentName}` : ''}
      {#if engine}<span class="badge">motor: {engine === 'ai' ? 'inteligencia artificial' : 'extracción automática'}</span>{/if}
    </p>
    <button type="button" class="btn btn-ghost btn-sm" onclick={runAnalysis} disabled={loading}>Volver a analizar</button>
  </div>

  {#if warnings.length}
    <section class="card warn-card">
      <h2>Avisos de lectura</h2>
      <ul>{#each warnings as w}<li>{w}</li>{/each}</ul>
    </section>
  {/if}

  {#if missing.length}
    <section class="card warn-card">
      <h2>No se pudo identificar</h2>
      <p class="muted small">Completa manualmente lo siguiente antes de guardar:</p>
      <ul>{#each missing as m}<li>{m}</li>{/each}</ul>
    </section>
  {/if}

  <section class="card">
    <h2>Datos generales</h2>
    <label class="field">Nombre de la asignatura
      <input bind:value={data.subjectName} placeholder="No identificado" />
    </label>
    <label class="field">Competencias (una por línea)
      <textarea rows="4" value={toLines(data.competencies)} oninput={(e) => data.competencies = fromLines(e.target.value)}></textarea>
    </label>
    <label class="field">Objetivos generales (uno por línea)
      <textarea rows="4" value={toLines(data.objectives)} oninput={(e) => data.objectives = fromLines(e.target.value)}></textarea>
    </label>
  </section>

  <section class="card">
    <div class="card-head">
      <h2>Unidades de aprendizaje ({data.units.length})</h2>
      <button type="button" class="btn btn-ghost btn-sm" onclick={addUnit}>+ Agregar unidad</button>
    </div>

    {#each data.units as u, i (i)}
      <details class="unit" open={i === 0}>
        <summary>
          <strong>Unidad {u.number || i + 1}</strong>
          <span class="muted">{u.title || 'Sin título'}</span>
          <button type="button" class="link danger" onclick={(e) => { e.preventDefault(); removeUnit(i); }}>Quitar</button>
        </summary>
        <div class="unit-body">
          <div class="row">
            <label class="field">Número
              <input type="number" min="1" bind:value={u.number} />
            </label>
            <label class="field">Título
              <input bind:value={u.title} placeholder="Título de la unidad" />
            </label>
            <label class="field">Horas teóricas
              <input type="number" min="0" step="0.5" bind:value={u.theoryHours} placeholder="—" />
            </label>
            <label class="field">Horas prácticas
              <input type="number" min="0" step="0.5" bind:value={u.practiceHours} placeholder="—" />
            </label>
          </div>
          {#each UNIT_LIST_FIELDS as f (f)}
            <label class="field">
              {f === 'objectives' ? 'Objetivos de la unidad' : f === 'topics' ? 'Temas' : f === 'subtopics' ? 'Subtemas' : f === 'outcomes' ? 'Resultados de aprendizaje' : 'Criterios de evaluación'} (uno por línea)
              <textarea rows="3" value={toLines(u[f])} oninput={(e) => u[f] = fromLines(e.target.value)}></textarea>
            </label>
          {/each}
        </div>
      </details>
    {:else}
      <p class="muted">No se identificaron unidades. Usa “+ Agregar unidad” para capturarlas manualmente.</p>
    {/each}
  </section>

  <div class="actions-row sticky">
    <button type="button" class="btn btn-accent" onclick={save} disabled={saving || !data.units.length}>
      {saving ? 'Guardando…' : 'Confirmar y guardar'}
    </button>
    <a href="/cursos" class="btn btn-ghost">Cancelar</a>
  </div>
{/if}

<style>
  .toolbar { display: flex; justify-content: space-between; align-items: center; gap: 1rem; flex-wrap: wrap; margin-bottom: 0.9rem; }
  .small { font-size: 0.82rem; }
  .badge { background: var(--turquoise); color: #fff; border-radius: 999px; padding: 0.15rem 0.6rem; font-size: 0.72rem; margin-left: 0.4rem; }
  .warn-card { border-left: 4px solid #d97706; }
  .warn-card h2 { color: #92400e; }
  .warn-card ul { margin: 0.4rem 0 0; padding-left: 1.2rem; }
  .warn-card li { font-size: 0.85rem; margin: 0.2rem 0; }
  .summary ul { padding-left: 1.2rem; }
  .card-head { display: flex; justify-content: space-between; align-items: center; }
  .card-head h2 { margin: 0; }
  .unit { border: 1px solid var(--border); border-radius: 10px; padding: 0.6rem 0.9rem; margin-top: 0.8rem; }
  .unit summary { display: flex; align-items: center; gap: 0.7rem; cursor: pointer; list-style: none; }
  .unit summary::-webkit-details-marker { display: none; }
  .unit summary .muted { flex: 1; font-size: 0.85rem; }
  .unit-body { margin-top: 0.9rem; }
  .field { display: block; margin: 0.7rem 0 0.2rem; font-size: 0.85rem; }
  textarea { width: 100%; font: inherit; padding: 0.5rem; border: 1px solid var(--border); border-radius: 8px; resize: vertical; }
  input { width: 100%; font: inherit; padding: 0.5rem; border: 1px solid var(--border); border-radius: 8px; }
  .row { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 0.8rem; }
  .actions-row { display: flex; gap: 0.7rem; margin-top: 1rem; flex-wrap: wrap; }
  .actions-row.sticky { position: sticky; bottom: 0; background: var(--bg, #f8fafc); padding: 0.8rem 0; }
  h2 { margin: 0 0 0.6rem; font-size: 1.05rem; color: var(--navy-900); }
  .muted { color: var(--muted); }
  @media (max-width: 700px) { .row { grid-template-columns: 1fr 1fr; } }
</style>
