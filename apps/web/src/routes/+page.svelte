<script>
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';

  let user = $state(null);
  let courses = $state([]);
  let docsCount = $state(0);
  let error = $state('');
  let loading = $state(true);

  onMount(async () => {
    const raw = localStorage.getItem('user');
    if (raw) user = JSON.parse(raw);
    try {
      const { data } = await api('/courses');
      courses = data;
      const docs = await Promise.all(
        data.map((c) =>
          api(`/courses/${c.id}/documents`)
            .then((r) => (r.data ? 1 : 0))
            .catch(() => 0)
        )
      );
      docsCount = docs.reduce((s, n) => s + n, 0);
    } catch (e) {
      error = e.message;
    } finally {
      loading = false;
    }
  });

  const totalHours = $derived(courses.reduce((s, c) => s + (Number(c.total_hours) || 0), 0));
  const maxWeeks = $derived(courses.reduce((m, c) => Math.max(m, Number(c.cuatrimestre_weeks) || 0), 0));
  const recent = $derived(courses.slice(0, 5));

  const kpis = $derived([
    { label: 'Cursos registrados', value: courses.length, icon: 'book', tone: '' },
    { label: 'Horas totales planificadas', value: totalHours, icon: 'clock', tone: 'turq' },
    { label: 'Semanas del cuatrimestre', value: maxWeeks || '—', icon: 'calendar', tone: 'green' },
    { label: 'Cartas descriptivas', value: docsCount, icon: 'doc', tone: 'amber' }
  ]);

  const icons = {
    book: 'M4 19.5A2.5 2.5 0 0 1 6.5 17H20M4 19.5A2.5 2.5 0 0 0 6.5 22H20V2H6.5A2.5 2.5 0 0 0 4 4.5v15Z',
    clock: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20Zm0-14v6l4 2',
    calendar: 'M8 2v4m8-4v4M3 10h18M5 4h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Z',
    bolt: 'M13 2 4 14h6l-1 8 9-12h-6l1-8Z',
    doc: 'M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8l-6-6Zm0 0v6h6M9 13h6m-6 4h6',
    balance: 'M4 20V10m6 10V4m6 16v-7m4 7H2',
    users: 'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2m16-10a4 4 0 1 0-8 0m-4 0a4 4 0 1 0-8 0M16 3.13a4 4 0 0 1 0 7.75M12 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z',
    plus: 'M12 5v14m-7-7h14'
  };

  const quick = [
    { href: '/cursos', title: 'Gestionar cursos', desc: 'Crea cursos y sube cartas descriptivas', icon: 'book', tone: '' },
    { href: '/balance', title: 'Balance de cargas', desc: 'Distribuye actividades por semana', icon: 'balance', tone: 'turq' },
    { href: '/equipos', title: 'Instrucciones Teams', desc: 'Genera texto para tareas de Teams', icon: 'users', tone: 'green' }
  ];
</script>

<div class="page-head">
  <h1>Hola{user?.full_name ? `, ${user.full_name.split(' ')[0]}` : ''}</h1>
  <p>Resumen general de la planeación académica</p>
</div>

{#if error}<p class="err">{error}</p>{/if}

<div class="kpi-grid">
  {#each kpis as k (k.label)}
    <div class="kpi">
      <span class="kpi-icon {k.tone}">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="22" height="22"><path d={icons[k.icon]}/></svg>
      </span>
      <div>
        <div class="kpi-value">{loading ? '…' : k.value}</div>
        <div class="kpi-label">{k.label}</div>
      </div>
    </div>
  {/each}
</div>

<div class="quick-grid">
  {#each quick as q (q.href)}
    <a href={q.href} class="quick-card">
      <span class="kpi-icon {q.tone}">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="20" height="20"><path d={icons[q.icon]}/></svg>
      </span>
      <span>
        <strong>{q.title}</strong>
        <span>{q.desc}</span>
      </span>
    </a>
  {/each}
  <a href="/cursos" class="quick-card accent-card">
    <span class="kpi-icon turq">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" width="20" height="20"><path d={icons.plus}/></svg>
    </span>
    <span>
      <strong>Nuevo curso</strong>
      <span>Ir al formulario de creación</span>
    </span>
  </a>
</div>

{#if recent.length}
  <section class="card">
    <div class="section-head">
      <h2>Cursos recientes</h2>
      <a href="/cursos" class="btn btn-ghost btn-sm">Ver todos</a>
    </div>
    <table>
      <thead>
        <tr><th>Curso</th><th>Semanas</th><th>Horas</th><th>Acciones</th></tr>
      </thead>
      <tbody>
        {#each recent as c (c.id)}
          <tr>
            <td><strong>{c.name}</strong>{#if c.description}<br /><span class="muted" style="font-size:.8rem">{c.description}</span>{/if}</td>
            <td>{c.cuatrimestre_weeks}</td>
            <td>{c.total_hours} h</td>
            <td class="row-actions">
              <a class="btn btn-ghost btn-sm" href="/cursos/{c.id}/plan">Planear</a>
              <a class="btn btn-ghost btn-sm" href="/cursos/{c.id}/cronograma">Cronograma</a>
            </td>
          </tr>
        {/each}
      </tbody>
    </table>
  </section>
{:else if !loading}
  <section class="card empty-state">
    <p class="muted">Aún no hay cursos registrados. Crea el primero para comenzar a planear.</p>
    <a href="/cursos" class="btn btn-accent">Ir a Cursos</a>
  </section>
{/if}

<style>
  .section-head {
    display: flex; align-items: center; justify-content: space-between;
    margin-bottom: 0.75rem;
  }
  .section-head h2 { margin: 0; font-size: 1.05rem; color: var(--navy-900); }
  .row-actions { display: flex; gap: 0.4rem; flex-wrap: wrap; }
  .btn-sm { padding: 0.35rem 0.75rem; font-size: 0.78rem; }
  .empty-state { text-align: center; padding: 2.5rem 1rem; }
  .empty-state .btn { margin-top: 1rem; }
</style>
