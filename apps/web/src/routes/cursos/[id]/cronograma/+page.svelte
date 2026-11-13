<script>
  import { page } from '$app/state';
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';

  let schedule = $state(null);
  let error = $state('');
  onMount(async () => {
    try {
      schedule = await api(`/courses/${page.params.id}/schedule`);
    } catch (e) { error = e.message; }
  });
</script>

{#if error}<p class="err">{error}</p>{/if}
{#if schedule}
  <div class="page-head">
    <h1>{schedule.course.name} — Cronograma</h1>
    <p>{schedule.course.cuatrimestre_weeks} semanas · {schedule.course.total_hours} h totales</p>
  </div>
  <div class="weeks">
    {#each schedule.weeks as w (w.week)}
      <div class="card week" class:empty={!w.activities.length && !w.evaluations.length}>
        <h3><span class="week-num">{w.week}</span> Semana {w.week}</h3>
        {#each w.activities as a (a.id)}
          <p class="act"><span class="badge badge-turq">{a.type}</span> {a.title} <span class="muted">({a.units?.number} · {a.hours}h)</span></p>
        {/each}
        {#each w.evaluations as ev (ev.id)}
          <p class="ev"><span class="badge badge-red">{ev.type}</span> <strong>{ev.title}</strong> <span class="muted">{ev.weight}%</span></p>
        {/each}
        {#if !w.activities.length && !w.evaluations.length}<p class="muted empty-week">Sin actividades</p>{/if}
      </div>
    {/each}
  </div>
{:else}<p class="muted">Cargando…</p>{/if}

<style>
  .weeks {
    display: grid; gap: 0.9rem;
    grid-template-columns: repeat(auto-fill, minmax(230px, 1fr));
  }
  .week { padding: 1rem; }
  .week.empty { opacity: 0.5; background: var(--panel-2); }
  h3 { margin: 0 0 0.6rem; font-size: 0.92rem; color: var(--navy-900); display: flex; align-items: center; gap: 0.5rem; }
  .week-num {
    width: 26px; height: 26px; border-radius: 8px; flex-shrink: 0;
    background: linear-gradient(135deg, var(--navy-800), var(--navy-700));
    color: #fff; font-size: 0.75rem; font-weight: 700;
    display: inline-flex; align-items: center; justify-content: center;
  }
  .week.empty .week-num { background: #cbd5e1; }
  .act, .ev { font-size: 0.82rem; margin: 0.45rem 0; line-height: 1.4; }
  .act .badge, .ev .badge { margin-right: 0.3rem; }
  .ev strong { color: var(--navy-900); }
  .empty-week { font-size: 0.8rem; font-style: italic; }
  .muted { color: var(--muted); }
</style>
