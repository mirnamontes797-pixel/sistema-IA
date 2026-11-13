<script>
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';

  let courses = $state([]);
  let selected = $state('');
  let result = $state(null);
  let instructors = $state([]);
  let error = $state('');
  let loading = $state(false);

  onMount(async () => {
    try {
      const { data } = await api('/courses');
      courses = data;
      if (data.length) selected = data[0].id;
      const r = await api('/balance/instructors');
      instructors = r.data;
    } catch (e) { error = e.message; }
  });

  async function balance() {
    error = ''; result = null; loading = true;
    try {
      result = await api(`/courses/${selected}/balance`, { method: 'POST', body: {} });
      const r = await api('/balance/instructors');
      instructors = r.data;
    } catch (e) { error = e.message; } finally { loading = false; }
  }

  const maxLoad = $derived(result ? Math.max(...result.loadPerWeek, 1) : 1);
</script>

<div class="page-head">
  <h1>Balance de cargas</h1>
  <p>Distribuye las actividades sin semana asignada minimizando la carga semanal</p>
</div>

{#if error}<p class="err">{error}</p>{/if}

<div class="card controls">
  <label class="field">Curso
    <select bind:value={selected}>
      {#each courses as c (c.id)}<option value={c.id}>{c.name} ({c.cuatrimestre_weeks} sem)</option>{/each}
    </select>
  </label>
  <button class="btn btn-accent" onclick={balance} disabled={loading || !selected}>
    {loading ? 'Balanceando…' : 'Ejecutar balance'}
  </button>
</div>

{#if result}
  <section class="card result">
    <h2>Resultado del balance</h2>
    <div class="stats">
      <div class="stat"><span class="stat-label">Capacidad semanal</span><strong>{result.weeklyCapacity} h</strong></div>
      <div class="stat"><span class="stat-label">Varianza</span><strong>{result.variance}</strong></div>
    </div>
    {#each result.warnings as w}<p class="warn">⚠ {w}</p>{/each}
    <div class="bars">
      {#each result.loadPerWeek as load, i}
        <div class="bar-col">
          <div class="bar" class:over={load > result.weeklyCapacity} style="height:{Math.max(4, (load / maxLoad) * 120)}px"></div>
          <span>Sem {i + 1}</span>
          <small>{load.toFixed(1)}h</small>
        </div>
      {/each}
    </div>
  </section>
{/if}

{#if instructors.length}
  <section class="card">
    <h2>Carga por instructor</h2>
    <div class="table-wrap">
      <table>
        <thead><tr><th>Instructor</th><th>Carga semanal total (h)</th></tr></thead>
        <tbody>
          {#each instructors as ins (ins.instructorId)}
            <tr>
              <td>{ins.instructorId?.slice(0, 8) ?? '—'}</td>
              <td>{ins.weeklyTotal.map((h) => h.toFixed(1)).join(' · ')}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  </section>
{/if}

<style>
  .card { margin-bottom: 1.25rem; }
  .controls { display: flex; align-items: flex-end; gap: 1rem; flex-wrap: wrap; }
  .field { flex: 1; min-width: 240px; margin-bottom: 0; }
  .controls .btn { margin: 0; }

  h2 { margin: 0 0 0.9rem; font-size: 1.05rem; color: var(--navy-900); }
  .stats { display: flex; gap: 1.5rem; margin-bottom: 0.9rem; flex-wrap: wrap; }
  .stat { display: flex; flex-direction: column; }
  .stat-label { font-size: 0.78rem; color: var(--muted); font-weight: 600; text-transform: uppercase; letter-spacing: .04em; }
  .stat strong { font-size: 1.2rem; color: var(--navy-900); }

  .bars {
    display: flex; gap: 6px; align-items: flex-end;
    height: 170px; margin-top: 1.25rem;
    padding: 0.75rem; background: var(--panel-2);
    border: 1px solid var(--border); border-radius: 12px;
  }
  .bar-col { display: flex; flex-direction: column; align-items: center; gap: 2px; flex: 1; height: 100%; justify-content: flex-end; }
  .bar {
    width: 100%; max-width: 42px;
    background: linear-gradient(180deg, var(--turquoise-light), var(--turquoise));
    border-radius: 6px 6px 0 0; transition: height .3s ease;
  }
  .bar.over { background: linear-gradient(180deg, #f87171, var(--danger)); }
  .bar-col span { font-size: 0.68rem; color: var(--muted); }
  .bar-col small { font-size: 0.65rem; color: var(--muted); font-weight: 600; }

  .table-wrap { overflow-x: auto; }
</style>
