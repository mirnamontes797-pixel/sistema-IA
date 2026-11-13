// Balance de cargas: distribuye actividades en semanas del cuatrimestre
// minimizando la varianza de horas por semana.

/**
 * @param {Array<{id:string, hours:number, week:number|null, unit_number:number}>} activities
 * @param {number} totalWeeks
 * @param {number} weeklyCapacityHoras - horas semanales disponibles
 * @returns {{ assignments: Map<id, week>, load: number[], variance: number, warnings: string[] }}
 */
export function balanceWorkload(activities, totalWeeks, weeklyCapacityHoras) {
  const weeks = Array.from({ length: totalWeeks }, (_, i) => i + 1);
  const load = new Map(weeks.map((w) => [w, 0]));
  const assignments = new Map();
  const warnings = [];

  // Ordenar por unidad y horas descendente (las más pesadas primero)
  const sorted = [...activities].sort(
    (a, b) => a.unit_number - b.unit_number || b.hours - a.hours
  );

  // 1) Respetar semanas ya asignadas manualmente
  for (const a of sorted) {
    if (a.week && a.week >= 1 && a.week <= totalWeeks) {
      assignments.set(a.id, a.week);
      load.set(a.week, load.get(a.week) + Number(a.hours || 0));
    }
  }

  // 2) Asignar las no programadas a la semana con menor carga
  //    dentro del bloque razonable de su unidad (evita mezclar unidades).
  const pending = sorted.filter((a) => !assignments.has(a.id));
  for (const a of pending) {
    const hours = Number(a.hours || 0);
    let candidates = weeks;
    // Preferir semanas cercanas a la unidad (unit_number aprox semana base)
    const preferred = weeks.filter((w) => Math.abs(w - a.unit_number * 2) <= 4);
    if (preferred.length) candidates = preferred;

    candidates.sort((x, y) => load.get(x) - load.get(y));
    const target = candidates[0];
    assignments.set(a.id, target);
    load.set(target, load.get(target) + hours);

    if (load.get(target) > weeklyCapacityHoras) {
      warnings.push(
        `Semana ${target} supera la capacidad (${load.get(target).toFixed(1)}h > ${weeklyCapacityHoras}h)`
      );
    }
  }

  const loads = weeks.map((w) => load.get(w));
  const mean = loads.reduce((s, v) => s + v, 0) / loads.length || 1;
  const variance = loads.reduce((s, v) => s + (v - mean) ** 2, 0) / loads.length;

  return { assignments, load: loads, variance, warnings };
}

/** Carga por instructor (varias secciones del mismo curso comparten instructor) */
export function balanceByInstructor(courseLoads) {
  // courseLoads: [{ courseId, instructorId, weeklyHours[] }]
  const perInstructor = new Map();
  for (const c of courseLoads) {
    if (!c.instructorId) continue;
    const arr = perInstructor.get(c.instructorId) || [];
    arr.push(c.weeklyHours);
    perInstructor.set(c.instructorId, arr);
  }
  const result = [];
  for (const [instructorId, loads] of perInstructor) {
    const maxWeeks = Math.max(...loads.map((l) => l.length));
    const totalPerWeek = Array.from({ length: maxWeeks }, (_, i) =>
      loads.reduce((s, l) => s + (l[i] || 0), 0)
    );
    result.push({ instructorId, weeklyTotal: totalPerWeek });
  }
  return result;
}
