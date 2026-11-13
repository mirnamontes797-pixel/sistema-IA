<script>
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';

  let courses = $state([]);
  let courseId = $state('');
  let plan = $state(null);
  let instructions = $state('');
  let error = $state('');
  let copied = $state(false);

  onMount(async () => {
    try {
      const { data } = await api('/courses');
      courses = data;
      if (data.length) { courseId = data[0].id; loadPlan(); }
    } catch (e) { error = e.message; }
  });

  async function loadPlan() {
    plan = await api(`/courses/${courseId}/plan`);
    instructions = '';
  }

  const allActivities = $derived(
    (plan?.units || []).flatMap((u) => u.activities.map((a) => ({ ...a, unit: u })))
  );
  const allEvaluations = $derived(
    (plan?.units || []).flatMap((u) => u.evaluations.map((ev) => ({ ...ev, unit: u })))
  );

  async function generate(kind, id) {
    error = ''; instructions = ''; copied = false;
    try {
      const body = kind === 'activity' ? { activity_id: id } : { evaluation_id: id };
      const res = await api('/teams/instructions', { method: 'POST', body });
      instructions = res.instructions;
    } catch (e) { error = e.message; }
  }

  async function copy() {
    await navigator.clipboard.writeText(instructions);
    copied = true;
    setTimeout(() => (copied = false), 2000);
  }
</script>

<div class="page-head">
  <h1>Instrucciones para Teams</h1>
  <p>Genera texto listo para pegar en las instrucciones de una tarea de Microsoft Teams</p>
</div>

{#if error}<p class="err">{error}</p>{/if}

<div class="card controls">
  <label class="field">Curso
    <select bind:value={courseId} onchange={loadPlan}>
      {#each courses as c (c.id)}<option value={c.id}>{c.name}</option>{/each}
    </select>
  </label>
</div>

{#if plan}
  <div class="grid">
    <section class="card">
      <div class="section-head">
        <h2>Actividades</h2>
        <span class="badge badge-navy">{allActivities.length}</span>
      </div>
      {#each allActivities as a (a.id)}
        <div class="item">
          <div class="item-info">
            <strong>{a.title}</strong>
            <span class="muted">Unidad {a.unit.number} · {a.modality} · {a.hours}h</span>
          </div>
          <button class="btn btn-sm btn-ghost" onclick={() => generate('activity', a.id)}>Generar</button>
        </div>
      {:else}<p class="muted">Sin actividades.</p>{/each}
    </section>
    <section class="card">
      <div class="section-head">
        <h2>Evaluaciones</h2>
        <span class="badge badge-turq">{allEvaluations.length}</span>
      </div>
      {#each allEvaluations as ev (ev.id)}
        <div class="item">
          <div class="item-info">
            <strong>{ev.title}</strong>
            <span class="muted">Unidad {ev.unit.number} · {ev.weight}%</span>
          </div>
          <button class="btn btn-sm btn-accent" onclick={() => generate('evaluation', ev.id)}>Generar</button>
        </div>
      {:else}<p class="muted">Sin evaluaciones.</p>{/each}
    </section>
  </div>
{/if}

{#if instructions}
  <section class="card">
    <div class="section-head">
      <h2>Instrucciones generadas</h2>
      <button class="btn btn-accent btn-sm" onclick={copy}>{copied ? '¡Copiado!' : 'Copiar'}</button>
    </div>
    <pre>{instructions}</pre>
  </section>
{/if}

<style>
  .controls { margin-bottom: 1.25rem; }
  .field { max-width: 420px; margin-bottom: 0; }
  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 1.25rem; align-items: start; }
  .card { margin-bottom: 1.25rem; }
  h2 { margin: 0; font-size: 1.05rem; color: var(--navy-900); }
  .section-head { display: flex; align-items: center; justify-content: space-between; margin-bottom: 0.6rem; }
  .item {
    display: flex; justify-content: space-between; align-items: center;
    gap: 0.75rem; padding: 0.7rem 0.4rem;
    border-bottom: 1px solid var(--border);
  }
  .item:last-child { border-bottom: 0; }
  .item-info { min-width: 0; }
  .item-info strong { display: block; font-size: 0.9rem; color: var(--navy-900); }
  .item-info .muted { font-size: 0.78rem; }
  .btn-sm { padding: 0.4rem 0.8rem; font-size: 0.8rem; white-space: nowrap; }
  pre {
    white-space: pre-wrap; background: var(--panel-2);
    border: 1px solid var(--border); border-radius: 12px;
    padding: 1.1rem; font-size: 0.85rem; line-height: 1.6; color: var(--text);
    margin: 0;
  }

  @media (max-width: 800px) {
    .grid { grid-template-columns: 1fr; }
  }
</style>
