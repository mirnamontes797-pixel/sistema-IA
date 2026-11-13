<script>
  import { page } from '$app/state';
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';
  import { computeAcademicSummary, WEEKDAY_NAMES, EVENT_TYPES, toISODate, parseISODate } from '$lib/academicCalc.js';

  const courseId = $derived(page.params.id);
  const MODALITIES = { presencial: 'Presencial', virtual: 'Virtual', mixta: 'Mixta' };
  const MODALITY_OPTIONS = [['presencial', 'Presencial'], ['virtual', 'Virtual'], ['mixta', 'Mixta']];
  const SESSION_TYPES = { presencial: 'Presencial', virtual_sincrona: 'Virtual sincrónica', autonomo: 'Trabajo autónomo' };
  const SESSION_TYPE_OPTIONS = [['presencial', 'Presencial'], ['virtual_sincrona', 'Virtual sincrónica'], ['autonomo', 'Trabajo autónomo']];
  const EVENT_TYPE_OPTIONS = [['inhabil', 'Día inhábil'], ['suspension', 'Suspensión académica'], ['eval_ordinaria', 'Evaluación ordinaria'], ['eval_extraordinaria', 'Evaluación extraordinaria'], ['evento', 'Evento académico']];

  let course = $state(null);
  let config = $state({});
  let schedule = $state([]);          // [{ weekday, sessions: [] }]
  let events = $state([]);
  let presets = $state([]);
  let previous = $state([]);
  let required = $state({ theory: 0, practice: 0, total: 0 });
  let hasPlan = $state(false);
  let error = $state('');
  let notice = $state('');
  let saving = $state(false);
  let loading = $state(true);
  let weeksManual = $state(false);
  let presetForm = $state('');        // preset a aplicar
  let copyId = $state('');            // curso del que copiar configuración
  let eventForm = $state({ type: 'evento', title: '', start_date: '', end_date: '', note: '' });
  let selectedDay = $state('');

  const flatSessions = $derived(
    schedule.flatMap((d) => d.sessions.map((s, i) => ({ ...s, weekday: d.weekday, position: i })))
  );

  const summary = $derived(
    computeAcademicSummary({ config, sessions: flatSessions, events, required })
  );

  function blankSchedule() {
    return Array.from({ length: 7 }, (_, i) => ({ weekday: i, sessions: [] }));
  }

  function clockMinutes(start, end) {
    const m = (t) => { const [h, mm] = String(t || '0:0').split(':').map(Number); return (h || 0) * 60 + (mm || 0); };
    let d = m(end) - m(start);
    if (d <= 0) d += 1440;
    return d;
  }

  function fmtHours(n) { return (Math.round((Number(n) || 0) * 10) / 10).toFixed(1); }
  function fmtClock(mins) {
    const h = Math.floor(mins / 60), m = mins % 60;
    return `${h} h${m ? ` ${m} min` : ''}`;
  }
  function sessionAcademicHours(s) {
    if (s.academic_hours !== '' && s.academic_hours != null) return Number(s.academic_hours);
    const per = Number(config.academic_hour_minutes) > 0 ? Number(config.academic_hour_minutes) : 50;
    return clockMinutes(s.start_time, s.end_time) / per;
  }

  function autoWeeks() {
    const a = parseISODate(config.start_date), b = parseISODate(config.end_date);
    if (!a || !b || b < a) return config.weeks;
    return Math.floor((b - a) / 86400000 / 7) + 1;
  }

  function onDatesChange() {
    if (!weeksManual) config.weeks = autoWeeks();
  }

  async function load() {
    loading = true;
    error = '';
    try {
      const res = await api(`/courses/${courseId}/academic-config`);
      const d = res.data;
      course = d.course;
      config = { ...d.config };
      if (config.modality == null) config.modality = '';
      required = d.required || required;
      presets = d.presets || [];
      previous = d.previous || [];
      events = (d.events || []).map((e) => ({ ...e }));
      schedule = blankSchedule();
      for (const s of d.sessions || []) {
        const day = schedule.find((x) => x.weekday === Number(s.weekday));
        if (day) day.sessions.push({
          start_time: s.start_time, end_time: s.end_time,
          session_type: s.session_type, academic_hours: s.academic_hours ?? '',
          active: s.active !== false
        });
      }
      weeksManual = config.weeks != null && config.weeks !== autoWeeks();
      try {
        const plan = await api(`/courses/${courseId}/plan`);
        hasPlan = (plan.units || []).length > 0;
      } catch { hasPlan = false; }
    } catch (e) {
      error = e.message || 'No se pudo cargar la configuración.';
    } finally {
      loading = false;
    }
  }
  onMount(load);

  function addSession(day) {
    day.sessions = [...day.sessions, { start_time: '08:00', end_time: '10:00', session_type: 'presencial', academic_hours: '', active: true }];
  }
  function removeSession(day, i) { day.sessions = day.sessions.filter((_, idx) => idx !== i); }

  function addEvent() {
    if (!eventForm.start_date) { error = 'Selecciona la fecha del evento (puedes hacer clic en un día del calendario).'; return; }
    events = [...events, { ...eventForm, end_date: eventForm.end_date || eventForm.start_date }];
    eventForm = { type: 'evento', title: '', start_date: '', end_date: '', note: '' };
    selectedDay = '';
    error = '';
  }
  function removeEvent(i) { events = events.filter((_, idx) => idx !== i); }

  function pickDay(iso) {
    selectedDay = iso;
    eventForm.start_date = iso;
    if (!eventForm.end_date) eventForm.end_date = iso;
  }

  function applyPreset() {
    const p = presets.find((x) => x.id === presetForm);
    if (!p) return;
    if (p.modality) config.modality = p.modality;
    if (p.institution) config.institution = p.institution;
    if (p.weeks && !weeksManual) { config.weeks = p.weeks; }
    if (p.academic_hour_minutes) config.academic_hour_minutes = p.academic_hour_minutes;
    if (p.autonomous_hours_per_week != null) config.autonomous_hours_per_week = p.autonomous_hours_per_week;
    if (!config.period_name) config.period_name = p.name;
    presetForm = '';
    notice = `Se aplicó la configuración predeterminada "${p.name}". Guarda para confirmar.`;
  }

  async function savePreset() {
    const name = prompt('Nombre de la configuración predeterminada:');
    if (!name) return;
    try {
      await api('/period-presets', {
        method: 'POST',
        body: {
          name,
          modality: config.modality,
          institution: config.institution,
          weeks: config.weeks,
          academic_hour_minutes: config.academic_hour_minutes,
          autonomous_hours_per_week: config.autonomous_hours_per_week
        }
      });
      const res = await api('/courses/' + courseId + '/academic-config');
      presets = res.data.presets || [];
      notice = 'Configuración guardada como predeterminada.';
    } catch (e) { error = e.message; }
  }

  async function copyFromPrevious() {
    const src = previous.find((p) => p.course_id === copyId);
    if (!src) { error = 'Selecciona primero el curso del que copiar la configuración.'; return; }
    if (!confirm(`¿Copiar la configuración de "${src.course_name || src.course_id}" a este curso? Se reemplazará la configuración local (aún no guardada).`)) return;
    try {
      const res = await api(`/courses/${src.course_id}/academic-config`);
      const d = res.data;
      config = { ...d.config, course_id: courseId };
      events = (d.events || []).map((e) => ({ ...e }));
      schedule = blankSchedule();
      for (const s of d.sessions || []) {
        const day = schedule.find((x) => x.weekday === Number(s.weekday));
        if (day) day.sessions.push({ start_time: s.start_time, end_time: s.end_time, session_type: s.session_type, academic_hours: s.academic_hours ?? '', active: s.active !== false });
      }
      notice = `Configuración copiada de "${d.course.name}". Revisa y guarda.`;
    } catch (e) { error = e.message; }
  }

  async function save() {
    if (hasPlan && !confirm('Este curso ya tiene una planeación registrada. La configuración del cuatrimestre se guardará sin modificar unidades, actividades ni evaluaciones. ¿Continuar?')) return;
    saving = true;
    error = '';
    notice = '';
    try {
      const body = {
        config: {
          period_name: config.period_name,
          start_date: config.start_date,
          end_date: config.end_date,
          weeks: config.weeks === '' ? null : config.weeks,
          modality: config.modality || null,
          institution: config.institution,
          academic_hour_minutes: config.academic_hour_minutes,
          autonomous_hours_per_week: config.autonomous_hours_per_week,
          required_theory_hours: config.required_theory_hours === '' ? null : config.required_theory_hours,
          required_practice_hours: config.required_practice_hours === '' ? null : config.required_practice_hours
        },
        sessions: flatSessions.map((s) => ({
          weekday: s.weekday, start_time: s.start_time, end_time: s.end_time,
          session_type: s.session_type, academic_hours: s.academic_hours === '' ? null : s.academic_hours,
          active: s.active !== false, position: s.position
        })),
        events: events.map((e) => ({
          type: e.type, title: e.title, start_date: e.start_date, end_date: e.end_date || e.start_date, note: e.note
        }))
      };
      const res = await api(`/courses/${courseId}/academic-config`, { method: 'PUT', body });
      notice = res.message || 'Configuración guardada correctamente.';
      await load();
    } catch (e) {
      error = e.message || 'No se pudo guardar la configuración.';
    } finally {
      saving = false;
    }
  }

  const STATUS_LABEL = { sufficient: 'Horas suficientes', insufficient: 'Horas insuficientes', unknown: 'Sin datos de carta' };
</script>

<div class="page-head">
  <h1>Configuración del cuatrimestre</h1>
  <p>{course ? `${course.name} — define el periodo, horarios, calendario y disponibilidad real de horas` : 'Cargando…'}</p>
</div>

{#if error}<p class="err">{error}</p>{/if}
{#if notice}<p class="ok">{notice}</p>{/if}

{#if loading}
  <section class="card"><p class="muted">Cargando configuración…</p></section>
{:else}

  <!-- ============ 1. Periodo académico ============ -->
  <section class="card">
    <div class="card-head">
      <h2>Periodo académico</h2>
      <div class="head-actions">
        {#if presets.length}
          <select class="inline-select" bind:value={presetForm} onchange={applyPreset}>
            <option value="">Aplicar predeterminado…</option>
            {#each presets as p (p.id)}<option value={p.id}>{p.name}{p.institution ? ` · ${p.institution}` : ''}</option>{/each}
          </select>
        {/if}
        <button type="button" class="btn btn-ghost btn-sm" onclick={savePreset}>Guardar como predeterminado</button>
        {#if previous.length}
          <select class="inline-select" bind:value={copyId} title="Curso del que copiar">
            <option value="">Copiar de otro curso…</option>
            {#each previous as p (p.course_id)}<option value={p.course_id}>{p.course_name || p.course_id} — {p.period_name || '(sin nombre)'} ({p.start_date || '?'})</option>{/each}
          </select>
          <button type="button" class="btn btn-ghost btn-sm" onclick={copyFromPrevious} disabled={!copyId}>Copiar</button>
        {/if}
      </div>
    </div>

    <div class="grid-form">
      <label class="field">Nombre del periodo
        <input bind:value={config.period_name} placeholder="Ej. Cuatrimestre Otoño 2026" />
      </label>
      <label class="field">Institución educativa
        <input bind:value={config.institution} placeholder="Ej. UTEQ, UV, UACJ…" list="institutions-list" />
        <datalist id="institutions-list">
          {#each [...new Set(presets.map((p) => p.institution).filter(Boolean))] as i}<option value={i}></option>{/each}
        </datalist>
      </label>
      <label class="field">Fecha de inicio
        <input type="date" bind:value={config.start_date} onchange={onDatesChange} />
      </label>
      <label class="field">Fecha de finalización
        <input type="date" bind:value={config.end_date} onchange={onDatesChange} />
      </label>
      <label class="field">Semanas académicas {#if !weeksManual && config.start_date && config.end_date}<span class="hint">(calculado de las fechas)</span>{/if}
        <input type="number" min="1" max="30" bind:value={config.weeks} oninput={() => (weeksManual = true)} />
      </label>
      <label class="field">Modalidad
        <select bind:value={config.modality}>
          <option value="">— Seleccionar —</option>
          {#each MODALITY_OPTIONS as m}<option value={m[0]}>{m[1]}</option>{/each}
        </select>
      </label>
      <label class="field">Minutos por hora académica
        <input type="number" min="30" max="90" step="5" bind:value={config.academic_hour_minutes} title="Duración de reloj que equivale a 1 hora académica (ej. 50 min)" />
      </label>
      <label class="field">Horas de trabajo autónomo por semana
        <input type="number" min="0" step="0.5" bind:value={config.autonomous_hours_per_week} />
      </label>
      <label class="field">Horas teóricas requeridas (carta)
        <input type="number" min="0" step="0.5" bind:value={config.required_theory_hours} placeholder={required.theory ? String(required.theory) : 'Automático'} />
      </label>
      <label class="field">Horas prácticas requeridas (carta)
        <input type="number" min="0" step="0.5" bind:value={config.required_practice_hours} placeholder={required.practice ? String(required.practice) : 'Automático'} />
      </label>
    </div>
    <p class="muted small">
      Si dejas las horas requeridas vacías se usan las extraídas de la carta descriptiva
      {#if required.total}({fmtHours(required.theory)} teóricas + {fmtHours(required.practice)} prácticas = {fmtHours(required.total)} h).{/if}
      La hora académica puede durar distinto a la hora de reloj según la institución.
    </p>
  </section>

  <!-- ============ 2. Horarios ============ -->
  <section class="card">
    <h2>Horarios semanales</h2>
    <p class="muted small">Agrega una o más sesiones por día. Las horas académicas se calculan solas; puedes sobrescribirlas si la institución las define distinto.</p>
    <div class="sched">
      {#each schedule as day (day.weekday)}
        <div class="sched-day" class:has-class={day.sessions.length > 0}>
          <div class="sched-head">
            <strong>{WEEKDAY_NAMES[day.weekday]}</strong>
            <button type="button" class="btn btn-ghost btn-sm" onclick={() => addSession(day)}>+ Sesión</button>
          </div>
          {#each day.sessions as s, i (i)}
            <div class="sess">
              <label class="chk"><input type="checkbox" bind:checked={s.active} /> Activa</label>
              <input type="time" bind:value={s.start_time} title="Inicio" />
              <span class="muted">–</span>
              <input type="time" bind:value={s.end_time} title="Fin" />
              <select bind:value={s.session_type}>
                {#each SESSION_TYPE_OPTIONS as t}<option value={t[0]}>{t[1]}</option>{/each}
              </select>
              <input type="number" min="0" step="0.5" bind:value={s.academic_hours} placeholder={fmtHours(sessionAcademicHours(s))} title="Horas académicas (vacío = automático)" />
              <span class="sess-meta muted">{fmtClock(clockMinutes(s.start_time, s.end_time))} reloj · {fmtHours(sessionAcademicHours(s))} h académicas</span>
              <button type="button" class="link danger" onclick={() => removeSession(day, i)}>Quitar</button>
            </div>
          {:else}
            <p class="muted small">Sin clases este día.</p>
          {/each}
        </div>
      {/each}
    </div>
  </section>

  <!-- ============ 3. Calendario académico ============ -->
  <section class="card">
    <h2>Calendario académico</h2>
    {#if !config.start_date}
      <p class="muted">Define la fecha de inicio del periodo para ver el calendario por semanas.</p>
    {:else}
      <div class="legend">
        <span><i class="dot dot-class"></i> Clase programada</span>
        <span><i class="dot dot-blocked"></i> Suspendida / inhábil</span>
        <span><i class="dot dot-eval"></i> Evaluación</span>
        <span><i class="dot dot-event"></i> Evento</span>
        <span class="muted small">Haz clic en un día para registrar un evento desde esa fecha.</span>
      </div>
      <div class="cal-weeks">
        {#each summary.calendar as w (w.number)}
          <div class="cal-week" class:no-class={w.scheduledCount === 0}>
            <div class="cal-week-head">
              <strong>Semana {w.number}</strong>
              <span class="muted small">{w.start} → {w.end}</span>
              {#if w.scheduledCount === 0}<span class="badge badge-amber">sin clases</span>{/if}
              {#if w.academicHours > 0}<span class="muted small">{fmtHours(w.academicHours)} h acad.</span>{/if}
            </div>
            <div class="cal-days">
              {#each w.days as d (d.date)}
                <button
                  type="button"
                  class="cal-day"
                  class:out={!d.inPeriod}
                  class:selected={selectedDay === d.date}
                  class:blocked={d.blocked}
                  class:classday={d.classDay}
                  disabled={!d.inPeriod}
                  onclick={() => pickDay(d.date)}
                  title={d.inPeriod ? `${d.date}${d.events.length ? ' · ' + d.events.map((e) => e.title).join(', ') : ''}` : ''}
                >
                  <span class="cal-num">{Number(d.date.slice(8))}</span>
                  <span class="cal-dow">{WEEKDAY_NAMES[d.weekday].slice(0, 3)}</span>
                  <span class="cal-dots">
                    {#each d.sessions as s, i (i)}<i class="dot dot-class" title={SESSION_TYPES[s.type]}></i>{/each}
                    {#each d.events as e (e.type + e.title)}<i class="dot dot-{e.type === 'eval_ordinaria' || e.type === 'eval_extraordinaria' ? 'eval' : e.type === 'evento' ? 'event' : 'blocked'}" title={e.title}></i>{/each}
                  </span>
                </button>
              {/each}
            </div>
          </div>
        {/each}
      </div>

      <h3>Eventos del periodo</h3>
      <div class="event-form">
        <select bind:value={eventForm.type}>
          {#each EVENT_TYPE_OPTIONS as ev}<option value={ev[0]}>{ev[1]}</option>{/each}
        </select>
        <input bind:value={eventForm.title} placeholder="Título / descripción" />
        <input type="date" bind:value={eventForm.start_date} title="Desde" />
        <input type="date" bind:value={eventForm.end_date} title="Hasta (opcional)" />
        <input bind:value={eventForm.note} placeholder="Nota (opcional)" />
        <button type="button" class="btn btn-accent btn-sm" onclick={addEvent}>+ Agregar</button>
      </div>
      {#if events.length}
        <div class="table-wrap">
          <table>
            <thead><tr><th>Tipo</th><th>Evento</th><th>Desde</th><th>Hasta</th><th></th></tr></thead>
            <tbody>
              {#each events as e, i (i)}
                <tr>
                  <td><span class="badge {e.type === 'inhabil' || e.type === 'suspension' ? 'badge-red' : e.type === 'evento' ? 'badge-navy' : 'badge-amber'}">{EVENT_TYPES[e.type] || e.type}</span></td>
                  <td>{e.title || '—'}{e.note ? ` · ${e.note}` : ''}</td>
                  <td>{e.start_date}</td>
                  <td>{e.end_date || e.start_date}</td>
                  <td><button type="button" class="link danger" onclick={() => removeEvent(i)}>Quitar</button></td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {:else}
        <p class="muted small">Sin eventos registrados. Los días inhábiles y suspensiones descuentan automáticamente las horas de las sesiones afectadas.</p>
      {/if}
    {/if}
  </section>

  <!-- ============ 4. Resumen académico ============ -->
  <section class="card">
    <h2>Resumen académico</h2>
    <div class="kpi-grid">
      <div class="kpi"><div class="kpi-icon"></div><div><div class="kpi-value">{summary.totals.weeksTotal}</div><div class="kpi-label">Semanas totales</div></div></div>
      <div class="kpi"><div class="kpi-icon turq"></div><div><div class="kpi-value">{summary.totals.weeksEffective}</div><div class="kpi-label">Semanas efectivas de clase</div></div></div>
      <div class="kpi"><div class="kpi-icon green"></div><div><div class="kpi-value">{summary.totals.effectiveDays}</div><div class="kpi-label">Días efectivos de clase</div></div></div>
      <div class="kpi"><div class="kpi-icon turq"></div><div><div class="kpi-value">{fmtHours(summary.available.academicHours)}</div><div class="kpi-label">Horas académicas disponibles</div></div></div>
      <div class="kpi"><div class="kpi-icon"></div><div><div class="kpi-value">{fmtHours(summary.required.total)}</div><div class="kpi-label">Horas requeridas (carta)</div></div></div>
      <div class="kpi"><div class="kpi-icon {summary.difference < 0 ? 'amber' : 'green'}"></div><div><div class="kpi-value">{summary.difference > 0 ? '+' : ''}{fmtHours(summary.difference)}</div><div class="kpi-label">Diferencia disponible − requerida</div></div></div>
    </div>

    <div class="summary-grid">
      <table>
        <thead><tr><th>Concepto</th><th>Horas académicas</th><th>Horas de reloj</th></tr></thead>
        <tbody>
          <tr><td>Presencial</td><td>{fmtHours(summary.totals.academicHours.presencial)}</td><td>—</td></tr>
          <tr><td>Virtual sincrónica</td><td>{fmtHours(summary.totals.academicHours.virtual)}</td><td>—</td></tr>
          <tr><td>Trabajo autónomo</td><td>{fmtHours(summary.totals.academicHours.autonomo)}</td><td>—</td></tr>
          <tr><td><strong>Total disponible</strong></td><td><strong>{fmtHours(summary.available.academicHours)}</strong></td><td><strong>{fmtHours(summary.totals.clockHours)}</strong></td></tr>
          <tr><td>Teóricas requeridas</td><td>{fmtHours(summary.required.theory)}</td><td>—</td></tr>
          <tr><td>Prácticas requeridas</td><td>{fmtHours(summary.required.practice)}</td><td>—</td></tr>
          <tr><td><strong>Total requerido</strong> <span class="muted small">({summary.required.source === 'manual' ? 'captura manual' : 'carta descriptiva'})</span></td><td><strong>{fmtHours(summary.required.total)}</strong></td><td>—</td></tr>
        </tbody>
      </table>
      <div class="facts">
        <p><strong>Periodo:</strong> {config.period_name || '—'} · {config.start_date || '—'} → {config.end_date || '—'}</p>
        <p><strong>Modalidad:</strong> {config.modality ? MODALITIES[config.modality] : '—'} · <strong>Institución:</strong> {config.institution || '—'}</p>
        <p><strong>Sesiones programadas:</strong> {summary.totals.scheduledOccurrences} · <strong>canceladas por inhábiles/suspensiones:</strong> {summary.totals.cancelledOccurrences}</p>
        <p><strong>Días inhábiles registrados:</strong> {summary.totals.inhabilDays} · <strong>Duplicados evitados:</strong> {summary.totals.duplicatesAvoided}</p>
        <p><strong>Estado:</strong> <span class="badge {summary.status === 'sufficient' ? 'badge-turq' : summary.status === 'insufficient' ? 'badge-red' : 'badge-amber'}">{STATUS_LABEL[summary.status]}</span></p>
      </div>
    </div>

    {#if summary.alerts.length}
      <div class="alerts {summary.status === 'insufficient' ? 'warn' : 'ok'}">
        {#each summary.alerts as a}<p>• {a}</p>{/each}
      </div>
    {/if}
  </section>

  <div class="actions-row sticky">
    <button type="button" class="btn btn-accent" onclick={save} disabled={saving}>
      {saving ? 'Guardando…' : 'Guardar configuración'}
    </button>
    <a href="/cursos/{courseId}/plan" class="btn btn-ghost">Ir a Planear</a>
    <a href="/cursos" class="btn btn-ghost">Volver a Cursos</a>
  </div>
{/if}

<style>
  .card { margin-bottom: 1.25rem; }
  .card h2 { margin: 0 0 0.4rem; font-size: 1.05rem; color: var(--navy-900); }
  h3 { font-size: 0.95rem; color: var(--navy-900); margin: 1.2rem 0 0.5rem; }
  .card-head { display: flex; justify-content: space-between; align-items: center; gap: 0.8rem; flex-wrap: wrap; }
  .card-head h2 { margin-bottom: 0.6rem; }
  .head-actions { display: flex; gap: 0.5rem; align-items: center; flex-wrap: wrap; }
  .inline-select { width: auto; padding: 0.4rem 0.6rem; font-size: 0.82rem; }
  .btn-sm { padding: 0.4rem 0.8rem; font-size: 0.8rem; }
  .small { font-size: 0.82rem; }
  .hint { color: var(--muted); font-weight: 400; font-size: 0.75rem; }
  .field { display: block; margin: 0.7rem 0 0.2rem; font-size: 0.85rem; }
  .grid-form { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 0.2rem 1rem; }
  .muted.small { margin-top: 0.6rem; }

  .sched { display: flex; flex-direction: column; gap: 0.8rem; margin-top: 0.6rem; }
  .sched-day { border: 1px solid var(--border); border-radius: 12px; padding: 0.7rem 0.9rem; }
  .sched-day.has-class { border-color: var(--turquoise); background: var(--panel-2); }
  .sched-head { display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.4rem; }
  .sess { display: flex; align-items: center; gap: 0.5rem; flex-wrap: wrap; padding: 0.35rem 0; border-top: 1px dashed var(--border); }
  .sess input[type="time"] { width: 110px; }
  .sess select { width: auto; min-width: 150px; }
  .sess input[type="number"] { width: 90px; }
  .sess-meta { font-size: 0.75rem; flex-basis: 100%; }
  .chk { display: flex; align-items: center; gap: 0.3rem; color: var(--text); font-size: 0.78rem; }
  .chk input { width: auto; }
  .link { background: none; border: 0; color: var(--turquoise); cursor: pointer; padding: 0; font: inherit; font-size: 0.8rem; font-weight: 600; }
  .link.danger { color: var(--danger); }

  .legend { display: flex; gap: 1rem; flex-wrap: wrap; font-size: 0.8rem; color: var(--muted); margin-bottom: 0.8rem; align-items: center; }
  .legend span { display: inline-flex; align-items: center; gap: 0.35rem; }
  .dot { width: 10px; height: 10px; border-radius: 50%; display: inline-block; }
  .dot-class { background: var(--turquoise); }
  .dot-blocked { background: var(--danger); }
  .dot-eval { background: var(--warn); }
  .dot-event { background: var(--navy-700); }

  .cal-weeks { display: flex; flex-direction: column; gap: 0.7rem; }
  .cal-week { border: 1px solid var(--border); border-radius: 12px; padding: 0.6rem 0.8rem; }
  .cal-week.no-class { border-style: dashed; }
  .cal-week-head { display: flex; align-items: center; gap: 0.7rem; flex-wrap: wrap; margin-bottom: 0.45rem; }
  .cal-week-head strong { color: var(--navy-900); font-size: 0.88rem; }
  .cal-days { display: grid; grid-template-columns: repeat(7, 1fr); gap: 0.35rem; }
  .cal-day {
    display: flex; flex-direction: column; align-items: center; gap: 0.15rem;
    padding: 0.45rem 0.2rem; border: 1px solid var(--border); border-radius: 10px;
    background: var(--panel); cursor: pointer; font: inherit; color: var(--text);
    min-height: 64px; justify-content: center;
  }
  .cal-day:hover:not(:disabled) { border-color: var(--turquoise); }
  .cal-day.out { opacity: 0.35; cursor: default; }
  .cal-day.classday { border-color: var(--turquoise); background: var(--turquoise-soft); }
  .cal-day.blocked { background: var(--danger-soft); border-color: #fecaca; }
  .cal-day.selected { outline: 2px solid var(--turquoise-light); outline-offset: 1px; }
  .cal-num { font-weight: 700; font-size: 0.9rem; }
  .cal-dow { font-size: 0.68rem; color: var(--muted); }
  .cal-dots { display: flex; gap: 3px; min-height: 10px; flex-wrap: wrap; justify-content: center; }

  .event-form { display: grid; grid-template-columns: 1.2fr 1.6fr 0.9fr 0.9fr 1.4fr auto; gap: 0.5rem; align-items: end; margin-bottom: 0.8rem; }
  .table-wrap { overflow-x: auto; }

  .summary-grid { display: grid; grid-template-columns: 1.2fr 1fr; gap: 1.2rem; align-items: start; }
  .facts p { font-size: 0.86rem; margin: 0.4rem 0; }
  .alerts { margin-top: 1rem; padding: 0.8rem 1rem; border-radius: 10px; }
  .alerts p { margin: 0.25rem 0; font-size: 0.85rem; }
  .actions-row { display: flex; gap: 0.7rem; margin-top: 0.5rem; flex-wrap: wrap; }
  .actions-row.sticky { position: sticky; bottom: 0; background: var(--bg); padding: 0.8rem 0; }

  @media (max-width: 1000px) { .summary-grid { grid-template-columns: 1fr; } }
  @media (max-width: 760px) {
    .cal-days { grid-template-columns: repeat(4, 1fr); }
    .event-form { grid-template-columns: 1fr 1fr; }
    .sess { font-size: 0.8rem; }
  }
</style>
