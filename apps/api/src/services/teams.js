// Generador de instrucciones para Microsoft Teams
// Produce un texto listo para pegar en la sección "Instrucciones" de una
// tarea de Teams, incluyendo objetivos, rúbrica y fechas.

export function buildTeamsInstructions({
  activity,
  unit,
  outcomes = [],
  rubric = null,
  course
}) {
  const lines = [];
  lines.push(`## ${activity.title}`);
  lines.push('');
  lines.push(`**Curso:** ${course?.name || 'N/A'}`);
  lines.push(`**Unidad:** ${unit ? `${unit.number}. ${unit.title}` : 'N/A'}`);
  lines.push(`**Tipo:** ${activity.type} · **Modalidad:** ${activity.modality} · **Horas estimadas:** ${activity.hours ?? 0}`);
  if (activity.start_date) lines.push(`**Fecha límite:** ${activity.start_date}`);
  lines.push('');

  if (unit?.objectives) {
    lines.push('### Objetivos de la unidad');
    lines.push(unit.objectives);
    lines.push('');
  }

  if (outcomes.length) {
    lines.push('### Resultados de aprendizaje evaluados');
    for (const o of outcomes) {
      lines.push(`- **${o.code || 'RA'}** ${o.title}${o.bloom_level ? ` _(Bloom: ${o.bloom_level})_` : ''}`);
    }
    lines.push('');
  }

  lines.push('### Instrucciones para el estudiante');
  lines.push('1. Revisa el material de la unidad en el canal correspondiente.');
  lines.push('2. Realiza la actividad siguiendo los criterios indicados.');
  lines.push('3. Adjunta tu entrega en formato PDF o el indicado por el docente.');
  lines.push('4. Verifica que tu nombre y matrícula aparezcan en el documento.');
  lines.push('');

  if (rubric?.criteria?.length) {
    lines.push(`### Rúbrica: ${rubric.title}`);
    lines.push('| Criterio | Niveles |');
    lines.push('|---|---|');
    for (const c of rubric.criteria) {
      const levels = (c.levels || []).map((l) => `${l.label} (${l.points})`).join(', ');
      lines.push(`| ${c.name} | ${levels} |`);
    }
    lines.push('');
  }

  lines.push('### Entrega');
  lines.push('- **Canal:** Esta tarea de Teams');
  lines.push('- **Puntos:** Configurar según ponderación de la evaluación');
  return lines.join('\n');
}
