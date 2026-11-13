// Cálculo del calendario y disponibilidad académica del cuatrimestre.
// weekday: 0 = lunes ... 6 = domingo. Las semanas son bloques de 7 días
// que comienzan en config.start_date.

export const WEEKDAY_NAMES = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
export const EVENT_TYPES = {
  inhabil: 'Día inhábil',
  suspension: 'Suspensión académica',
  eval_ordinaria: 'Evaluación ordinaria',
  eval_extraordinaria: 'Evaluación extraordinaria',
  evento: 'Evento académico'
};
const BLOCKING_TYPES = new Set(['inhabil', 'suspension']);
const SESSION_TYPES = ['presencial', 'virtual_sincrona', 'autonomo'];

export function parseISODate(s) {
  if (!s) return null;
  const [y, m, d] = String(s).slice(0, 10).split('-').map(Number);
  if (!y || !m || !d) return null;
  return new Date(y, m - 1, d);
}

export function toISODate(d) {
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

function addDays(d, n) {
  const x = new Date(d);
  x.setDate(x.getDate() + n);
  return x;
}

function diffDays(a, b) { return Math.round((a - b) / 86400000); }

// 0 = lunes ... 6 = domingo (independiente del locale)
function jsDow(d) { return (d.getDay() + 6) % 7; }

function minutesOf(t) {
  const [h, m] = String(t || '0:0').split(':').map(Number);
  return (h || 0) * 60 + (m || 0);
}

function clockMinutes(start, end) {
  let d = minutesOf(end) - minutesOf(start);
  if (d <= 0) d += 24 * 60;
  return d;
}

function round1(n) { return Math.round((Number(n) || 0) * 10) / 10; }

/**
 * @param {object} input
 * @param {object} input.config   course_academic_configs row (o defaults)
 * @param {Array}  input.sessions schedule_sessions rows
 * @param {Array}  input.events   academic_events rows
 * @param {object} input.required { theory, practice, total } horas de la carta descriptiva
 */
export function computeAcademicSummary({ config = {}, sessions = [], events = [], required = {} } = {}) {
  const start = parseISODate(config.start_date);
  const end = parseISODate(config.end_date);
  const perAcademicHour = Number(config.academic_hour_minutes) > 0 ? Number(config.academic_hour_minutes) : 50;
  const autonomousWeekly = Number(config.autonomous_hours_per_week) || 0;

  let weeksTotal = Number(config.weeks) || 0;
  if (!weeksTotal && start && end && end >= start) weeksTotal = Math.floor(diffDays(end, start) / 7) + 1;

  const activeSessions = (sessions || [])
    .filter((s) => s && s.active !== false && s.weekday != null)
    .slice()
    .sort((a, b) => (Number(a.position) || 0) - (Number(b.position) || 0) || Number(a.weekday) - Number(b.weekday));

  const allEvents = (events || [])
    .filter((e) => e && e.start_date)
    .map((e) => ({ ...e, end_date: e.end_date || e.start_date }))
    .sort((a, b) => String(a.start_date).localeCompare(String(b.start_date)));

  const eventsOn = (iso) => allEvents.filter((e) => e.start_date <= iso && e.end_date >= iso);
  const isBlocking = (iso) => eventsOn(iso).some((e) => BLOCKING_TYPES.has(e.type));

  const totals = {
    academic: { presencial: 0, virtual_sincrona: 0, autonomo: 0 },
    clockMinutes: 0,
    occurrences: 0,
    cancelled: 0,
    duplicatesAvoided: 0
  };
  const weeks = [];
  const seenSlots = new Set();
  const inhabilDates = new Set();
  for (const e of allEvents) {
    if (!BLOCKING_TYPES.has(e.type)) continue;
    let d = parseISODate(e.start_date);
    const last = parseISODate(e.end_date);
    while (d && last && d <= last) {
      const iso = toISODate(d);
      if ((!start || d >= start) && (!end || d <= end)) inhabilDates.add(iso);
      d = addDays(d, 1);
    }
  }

  if (start && weeksTotal > 0) {
    const startDow = jsDow(start);
    for (let w = 1; w <= weeksTotal; w++) {
      const weekStart = addDays(start, (w - 1) * 7);
      const weekEnd = addDays(weekStart, 6);
      const info = {
        number: w,
        start: toISODate(weekStart),
        end: toISODate(weekEnd),
        days: [],
        scheduledCount: 0,
        cancelledCount: 0,
        academicHours: 0,
        clockMinutes: 0,
        classDays: new Set()
      };

      for (let dow = 0; dow < 7; dow++) {
        const date = addDays(weekStart, (dow - startDow + 7) % 7);
        const iso = toISODate(date);
        const inPeriod = date >= start && (!end || date <= end);
        const dayEvents = inPeriod ? eventsOn(iso) : [];
        const blocked = dayEvents.some((e) => BLOCKING_TYPES.has(e.type));
        const day = {
          date: iso,
          weekday: dow,
          inPeriod,
          events: dayEvents.map((e) => ({ type: e.type, title: e.title || EVENT_TYPES[e.type] || e.type })),
          blocked,
          sessions: [],
          academicHours: 0,
          clockMinutes: 0,
          classDay: false
        };

        if (inPeriod) {
          for (const s of activeSessions) {
            if (Number(s.weekday) !== dow) continue;
            const key = `${iso}|${s.start_time}|${s.end_time}`;
            if (seenSlots.has(key)) { totals.duplicatesAvoided++; continue; }
            seenSlots.add(key);
            const cm = clockMinutes(s.start_time, s.end_time);
            const ah = s.academic_hours !== null && s.academic_hours !== undefined && s.academic_hours !== ''
              ? Number(s.academic_hours)
              : cm / perAcademicHour;
            const type = SESSION_TYPES.includes(s.session_type) ? s.session_type : 'presencial';
            info.scheduledCount++;
            day.sessions.push({ type, start: s.start_time, end: s.end_time, academicHours: round1(ah), clockMinutes: cm, blocked });
            if (blocked) {
              totals.cancelled++;
              info.cancelledCount++;
              continue;
            }
            day.classDay = true;
            day.academicHours += ah;
            day.clockMinutes += cm;
            info.academicHours += ah;
            info.clockMinutes += cm;
            info.classDays.add(iso);
            totals.academic[type] += ah;
            totals.clockMinutes += cm;
            totals.occurrences++;
          }
        }
        info.days.push(day);
      }
      weeks.push(info);
    }
  }

  const weeksEffective = weeks.filter((w) => w.classDays.size > 0).length;
  const effectiveDays = weeks.reduce((n, w) => n + w.classDays.size, 0);
  const weeksWithoutClass = weeks.filter((w) => w.scheduledCount === 0).map((w) => w.number);
  const weeksWithLowAttendance = weeks.filter((w) => w.scheduledCount > 0 && w.classDays.size === 0).map((w) => w.number);

  // Trabajo autónomo: horas semanales configuradas × semanas efectivas
  totals.academic.autonomo += autonomousWeekly * weeksEffective;

  const reqTheory = config.required_theory_hours !== null && config.required_theory_hours !== undefined && config.required_theory_hours !== ''
    ? Number(config.required_theory_hours) : Number(required.theory) || 0;
  const reqPractice = config.required_practice_hours !== null && config.required_practice_hours !== undefined && config.required_practice_hours !== ''
    ? Number(config.required_practice_hours) : Number(required.practice) || 0;
  const reqTotal = reqTheory + reqPractice || Number(required.total) || 0;

  const availableAcademic = totals.academic.presencial + totals.academic.virtual_sincrona + totals.academic.autonomo;
  const perWeek = weeksEffective ? round1(availableAcademic / weeksEffective) : 0;
  const clockHours = round1(totals.clockMinutes / 60);

  const avgRequired = weeksEffective && reqTotal ? reqTotal / weeksEffective : 0;
  const highLoadThreshold = avgRequired ? Math.max(6, avgRequired * 1.5) : 8;
  const highLoadWeeks = weeks
    .filter((w) => w.academicHours > highLoadThreshold)
    .map((w) => ({ week: w.number, hours: round1(w.academicHours) }));

  const difference = round1(availableAcademic - reqTotal);
  const status = reqTotal > 0 ? (availableAcademic >= reqTotal ? 'sufficient' : 'insufficient') : 'unknown';

  const alerts = [];
  if (status === 'insufficient') alerts.push(`Horas insuficientes: faltan ${round1(reqTotal - availableAcademic)} h académicas para cubrir la carta descriptiva.`);
  if (status === 'sufficient') alerts.push('Las horas disponibles cubren la carga requerida por la carta descriptiva.');
  if (weeksWithoutClass.length) alerts.push(`Semanas sin clases programadas: ${weeksWithoutClass.join(', ')}.`);
  if (weeksWithLowAttendance.length) alerts.push(`Semanas con todas las sesiones suspendidas o inhábiles: ${weeksWithLowAttendance.join(', ')}.`);
  if (highLoadWeeks.length) alerts.push(`Semanas con carga académica elevada (>${round1(highLoadThreshold)} h): ${highLoadWeeks.map((w) => w.week).join(', ')}.`);
  if (totals.duplicatesAvoided) alerts.push(`${totals.duplicatesAvoided} sesión(es) duplicada(s) en fecha y horario no se contaron dos veces.`);
  if (inhabilDates.size) alerts.push(`${inhabilDates.size} día(s) inhábil(es) o de suspensión dentro del periodo.`);

  return {
    period: {
      name: config.period_name || '',
      modality: config.modality || '',
      institution: config.institution || '',
      start: config.start_date || '',
      end: config.end_date || '',
      weeksTotal,
      academicHourMinutes: perAcademicHour
    },
    totals: {
      weeksTotal,
      weeksEffective,
      weeksWithoutClass,
      effectiveDays,
      scheduledOccurrences: totals.occurrences,
      cancelledOccurrences: totals.cancelled,
      duplicatesAvoided: totals.duplicatesAvoided,
      academicHours: {
        presencial: round1(totals.academic.presencial),
        virtual: round1(totals.academic.virtual_sincrona),
        autonomo: round1(totals.academic.autonomo)
      },
      clockHours,
      autonomousHoursPerWeek: autonomousWeekly,
      inhabilDays: inhabilDates.size
    },
    required: {
      theory: round1(reqTheory),
      practice: round1(reqPractice),
      total: round1(reqTotal),
      source: (Number(config.required_theory_hours) || Number(config.required_practice_hours)) ? 'manual' : 'carta'
    },
    available: {
      academicHours: round1(availableAcademic),
      perWeek,
      clockHours
    },
    difference,
    status,
    indicators: {
      sufficient: status === 'sufficient',
      insufficient: status === 'insufficient',
      highLoadWeeks,
      weeksWithoutClass
    },
    alerts,
    calendar: weeks.map((w) => ({
      number: w.number,
      start: w.start,
      end: w.end,
      scheduledCount: w.scheduledCount,
      cancelledCount: w.cancelledCount,
      academicHours: round1(w.academicHours),
      classDays: w.classDays.size,
      days: w.days
    }))
  };
}
