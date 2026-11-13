<script>
  import { page } from '$app/state';
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';

  const courseId = $derived(page.params.id);
  let plan = $state(null);
  let error = $state('');
  let newUnit = $state({ number: 1, title: '', objectives: '' });
  let selUnit = $state('');
  let forms = $state({
    outcome: { code: '', title: '', bloom_level: 'comprension' },
    activity: { title: '', type: 'clase', hours: 2, modality: 'presencial', week: '', start_date: '' },
    evaluation: { title: '', type: 'parcial', weight: 20, week: '', due_date: '' },
    rubric: { title: '', criteriaText: '' }
  });

  async function load() {
    try {
      const res = await api(`/courses/${courseId}/plan`);
      plan = res;
      if (!selUnit && res.units.length) selUnit = res.units[0].id;
    } catch (e) { error = e.message; }
  }
  onMount(load);

  const unit = $derived(plan?.units.find((u) => u.id === selUnit));

  async function addUnit(e) {
    e.preventDefault();
    await api('/units', { method: 'POST', body: { course_id: courseId, ...newUnit } });
    newUnit = { number: (plan?.units.length || 0) + 1, title: '', objectives: '' };
    load();
  }
  async function addOutcome(e) {
    e.preventDefault();
    await api('/outcomes', { method: 'POST', body: { unit_id: selUnit, ...forms.outcome } });
    forms.outcome.title = ''; forms.outcome.code = '';
    load();
  }
  async function addActivity(e) {
    e.preventDefault();
    const b = { ...forms.activity, unit_id: selUnit, week: forms.activity.week ? Number(forms.activity.week) : null };
    await api('/activities', { method: 'POST', body: b });
    forms.activity.title = '';
    load();
  }
  async function addEvaluation(e) {
    e.preventDefault();
    const b = { ...forms.evaluation, unit_id: selUnit, weight: Number(forms.evaluation.weight), week: forms.evaluation.week ? Number(forms.evaluation.week) : null };
    await api('/evaluations', { method: 'POST', body: b });
    forms.evaluation.title = '';
    load();
  }
  async function addRubric(e) {
    e.preventDefault();
    // criteriaText: "Criterio|Excelente:4,Bueno:3" por línea
    const criteria = forms.rubric.criteriaText.split('\n').filter(Boolean).map((line) => {
      const [name, levelsStr] = line.split('|').map((s) => s.trim());
      const levels = (levelsStr || 'Excelente:4,Bueno:3,Regular:2,Insuficiente:1')
        .split(',').map((p) => p.split(':'))
        .map(([label, points]) => ({ label: label.trim(), points: Number(points) || 0 }));
      return { name, levels };
    });
    await api('/rubrics', { method: 'POST', body: { unit_id: selUnit, title: forms.rubric.title, criteria } });
    forms.rubric.title = ''; forms.rubric.criteriaText = '';
    load();
  }
</script>

{#if error}<p class="err">{error}</p>{/if}
{#if plan}
  <div class="page-head">
    <h1>{plan.course.name} — Planeación</h1>
    <p>{plan.course.cuatrimestre_weeks} semanas · {plan.course.total_hours} h totales · <a href="/cursos/{courseId}/configuracion">Configuración del cuatrimestre</a></p>
  </div>

  <div class="layout">
    <aside class="card">
      <h2>Unidades</h2>
      <form onsubmit={addUnit} class="mini">
        <div class="mini-row">
          <input type="number" bind:value={newUnit.number} placeholder="#" required title="Número" />
          <input bind:value={newUnit.title} placeholder="Título de unidad" required />
        </div>
        <textarea bind:value={newUnit.objectives} placeholder="Objetivos" rows="2"></textarea>
        <button class="btn btn-sm btn-block">+ Unidad</button>
      </form>
      <ul class="unit-list">
        {#each plan.units as u (u.id)}
          <li>
            <button class="unit-btn" class:sel={u.id === selUnit} onclick={() => (selUnit = u.id)}>
              <strong>{u.number}.</strong> {u.title}
            </button>
          </li>
        {/each}
      </ul>
    </aside>

    {#if unit}
      <div class="content">
        <section class="card">
          <h2 class="unit-title">Unidad {unit.number}: {unit.title}</h2>
          {#if unit.objectives}<p class="muted">{unit.objectives}</p>{/if}

          <h3>Resultados de aprendizaje</h3>
          <ul class="outcomes">
            {#each unit.outcomes as o (o.id)}
              <li><span class="badge badge-navy">{o.code || 'RA'}</span> {o.title} <em class="muted">({o.bloom_level})</em></li>
            {:else}<li class="muted">Sin resultados capturados.</li>{/each}
          </ul>
          <form onsubmit={addOutcome} class="row-form">
            <input bind:value={forms.outcome.code} placeholder="Código (RA1)" />
            <input bind:value={forms.outcome.title} placeholder="Resultado de aprendizaje" required />
            <select bind:value={forms.outcome.bloom_level}>
              {#each ['conocimiento','comprension','aplicacion','analisis','sintesis','evaluacion'] as b}<option value={b}>{b}</option>{/each}
            </select>
            <button class="btn btn-sm">+ RA</button>
          </form>
        </section>

        <section class="card">
          <h3>Actividades</h3>
          <div class="table-wrap">
            <table>
              <thead><tr><th>Actividad</th><th>Tipo</th><th>Hrs</th><th>Modalidad</th><th>Semana</th></tr></thead>
              <tbody>
                {#each unit.activities as a (a.id)}
                  <tr><td>{a.title}</td><td><span class="badge badge-turq">{a.type}</span></td><td>{a.hours}</td><td>{a.modality}</td><td>{a.week ?? '—'}</td></tr>
                {:else}<tr><td colspan="5" class="muted">Sin actividades.</td></tr>{/each}
              </tbody>
            </table>
          </div>
          <form onsubmit={addActivity} class="row-form">
            <input bind:value={forms.activity.title} placeholder="Actividad" required />
            <select bind:value={forms.activity.type}>
              {#each ['clase','laboratorio','proyecto','examen','tarea','foro','seminario','lectura','asesoria'] as t}<option value={t}>{t}</option>{/each}
            </select>
            <input type="number" step="0.5" bind:value={forms.activity.hours} title="Horas" />
            <select bind:value={forms.activity.modality}>
              <option value="presencial">Presencial</option><option value="teams">Teams</option><option value="asincrona">Asincrónica</option>
            </select>
            <input type="number" bind:value={forms.activity.week} placeholder="Sem" title="Semana" />
            <button class="btn btn-sm">+ Actividad</button>
          </form>
        </section>

        <section class="card">
          <h3>Evaluaciones</h3>
          <div class="table-wrap">
            <table>
              <thead><tr><th>Evaluación</th><th>Tipo</th><th>Peso %</th><th>Semana</th><th>Fecha</th></tr></thead>
              <tbody>
                {#each unit.evaluations as ev (ev.id)}
                  <tr><td>{ev.title}</td><td><span class="badge badge-amber">{ev.type}</span></td><td>{ev.weight}</td><td>{ev.week ?? '—'}</td><td>{ev.due_date ?? '—'}</td></tr>
                {:else}<tr><td colspan="5" class="muted">Sin evaluaciones.</td></tr>{/each}
              </tbody>
            </table>
          </div>
          <form onsubmit={addEvaluation} class="row-form">
            <input bind:value={forms.evaluation.title} placeholder="Evaluación" required />
            <select bind:value={forms.evaluation.type}>
              {#each ['parcial','final','entrega','quiz','examen','participacion','proyecto'] as t}<option value={t}>{t}</option>{/each}
            </select>
            <input type="number" step="0.5" bind:value={forms.evaluation.weight} placeholder="Peso %" />
            <input type="number" bind:value={forms.evaluation.week} placeholder="Sem" />
            <input type="date" bind:value={forms.evaluation.due_date} />
            <button class="btn btn-sm">+ Evaluación</button>
          </form>
        </section>

        <section class="card">
          <h3>Rúbricas</h3>
          {#each unit.rubrics as r (r.id)}
            <div class="rubric">
              <strong>{r.title}</strong>
              <ul>
                {#each r.criteria || [] as c}<li>{c.name}: {(c.levels || []).map((l) => `${l.label} (${l.points})`).join(' · ')}</li>{/each}
              </ul>
            </div>
          {:else}<p class="muted">Sin rúbricas.</p>{/each}
          <form onsubmit={addRubric} class="stack">
            <input bind:value={forms.rubric.title} placeholder="Título de la rúbrica" required />
            <textarea bind:value={forms.rubric.criteriaText} rows="3"
              placeholder="Un criterio por línea: Nombre | Excelente:4,Bueno:3,Regular:2,Insuficiente:1"></textarea>
            <button class="btn btn-sm">+ Rúbrica</button>
          </form>
        </section>
      </div>
    {/if}
  </div>
{:else}<p class="muted">Cargando…</p>{/if}

<style>
  .layout { display: grid; grid-template-columns: 300px 1fr; gap: 1.25rem; align-items: start; }
  .card { margin-bottom: 1rem; }
  .muted { color: var(--muted); }

  h2.unit-title { margin-top: 0; }
  h2, h3 { color: var(--navy-900); }
  h3 { font-size: 0.95rem; margin: 1.1rem 0 0.5rem; }

  .mini input, .mini textarea, .row-form input, .row-form select, .stack input, .stack textarea {
    width: 100%; padding: 0.5rem 0.65rem; margin: 0.3rem 0;
  }
  .mini-row { display: flex; gap: 0.4rem; }
  .mini-row input:first-child { width: 56px; flex-shrink: 0; }
  .btn-block { width: 100%; justify-content: center; margin-top: 0.5rem; }
  .btn-sm { padding: 0.4rem 0.8rem; font-size: 0.8rem; }

  .unit-list { list-style: none; padding: 0; margin: 1rem 0 0; }
  .unit-list li { padding: 0.15rem 0; }
  .unit-btn {
    width: 100%; text-align: left;
    background: var(--panel-2); border: 1px solid var(--border);
    border-radius: 10px; padding: 0.55rem 0.75rem;
    color: var(--text); font-size: 0.85rem; cursor: pointer;
    transition: border-color .15s ease, background .15s ease;
  }
  .unit-btn:hover { border-color: var(--turquoise); }
  .unit-btn.sel {
    background: var(--turquoise-soft); border-color: var(--turquoise);
    color: #0f766e; font-weight: 600;
  }

  .outcomes { list-style: none; padding: 0; margin: 0 0 0.75rem; }
  .outcomes li { padding: 0.35rem 0; font-size: 0.9rem; display: flex; align-items: center; gap: 0.5rem; flex-wrap: wrap; }

  .table-wrap { overflow-x: auto; }
  table { margin: 0.25rem 0 0.75rem; }

  .row-form {
    display: grid;
    grid-template-columns: 2fr 1fr 0.6fr 1fr 0.6fr auto;
    gap: 0.4rem; align-items: center;
  }
  .row-form button { margin-top: 0; }

  .rubric {
    border-left: 3px solid var(--turquoise);
    background: var(--panel-2); border-radius: 0 10px 10px 0;
    padding: 0.7rem 0.9rem; margin-bottom: 0.75rem;
  }
  .rubric strong { color: var(--navy-900); font-size: 0.9rem; }
  .rubric ul { margin: 0.35rem 0 0; padding-left: 1.1rem; font-size: 0.85rem; color: var(--muted); }

  .stack input, .stack textarea { display: block; }

  @media (max-width: 1000px) {
    .layout { grid-template-columns: 1fr; }
  }
  @media (max-width: 700px) {
    .row-form { grid-template-columns: 1fr 1fr; }
    .row-form button { grid-column: 1 / -1; }
  }
</style>
