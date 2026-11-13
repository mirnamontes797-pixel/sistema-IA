// Análisis estructurado de cartas descriptivas / programas de asignatura.
// Motor 1 (por defecto): parser heurístico sobre el texto extraído.
// Motor 2 (opcional): LLM compatible con API OpenAI si están definidas
//   AI_API_BASE, AI_API_KEY y AI_MODEL en el entorno.

const clean = (s) => (s || '').replace(/\s+/g, ' ').trim();

function norm(s) {
  return clean(s).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
}

// norm() sin colapsar espacios: conserva longitud para cortar el original.
function normKeep(s) {
  return (s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
}

// Etiquetas de sección. Se comparan contra texto normalizado (sin acentos).
const SECTION_LABELS = [
  { key: 'subtopics', re: /^sub\s?temas?\b/ },
  { key: 'topics', re: /^(temas?|temario|contenido\s+tematico|contenidos?\s+tematicos?)\b/ },
  { key: 'outcomes', re: /^(resultados?\s+(del|de)\s+aprendizaje|resultados?\s+de\s+aprendizaje|r\.?a\.?s?\.?)\b/ },
  { key: 'theoryHours', re: /^(horas?\s+(teoricas|teoricas\s+practicas)|teoricas\s+horas)\b/ },
  { key: 'practiceHours', re: /^(horas?\s+practicas|practicas\s+horas)\b/ },
  { key: 'criteria', re: /^(criterios?\s+de\s+evaluacion|evaluacion|instrumentos?\s+de\s+evaluacion|criterios?\s+de\s+evaluacion\s+y\s+aprobacion)\b/ },
  { key: 'objectives', re: /^(objetivos?(\s+(general|especifico|de\s+la\s+unidad|de\s+aprendizaje|especificos|generales))?|proposito(\s+esperado)?|finalidad|intencion)\b/ },
  { key: 'competencies', re: /^(competencias?(\s+(generales?|especificas?|profesionales?|de\s+la\s+unidad|generales|especificas))?|competencia\s+general|competencia\s+especifica)\b/ }
];

function labelKey(line) {
  const t = norm(line);
  for (const l of SECTION_LABELS) if (l.re.test(t)) return l.key;
  return null;
}

// Líneas que son encabezados de tabla/pies de página: se saltan sin
// cortar la sección actual (pueden ser encabezados de columna).
const IGNORE_RE = /^(unidades de aprendizaje|tiempo asignado|horas del|horas totales|saber|saber hacer|ser y convivir|dimensi[oó]n\s+\w+|proceso\s+enseñanza\s*-\s*aprendizaje|metodos\s+y\s+tecnicas\s+de\s+ensenanza|medios\s+y\s+materiales\s+didacticos|espacio\s+formativo|aula\b|solucion\s+de\s+problemas|equipos\s+colaborativos|practicas\s+en\s+laboratorio|proceso\s+de\s+evaluacion|tipo\s+de|cuatrimestre|creditos|modalidad|horas\s+por\s+semana|funciones|capacidades|criterios\s+de\s+desempeno|totales|elaboro|elaboro:|f\s*-\s*da|aprobo|vigente|programa\s+educativo)/;

function isIgnoreLine(line) {
  return IGNORE_RE.test(norm(line));
}

// Ítems que son ruido de tabla y no deben listarse (ya normalizados).
const STOP_ITEMS = new Set([
  'temas', 'saber', 'saber hacer', 'ser y convivir', 'asignatura',
  'de aprendizaje de la', 'horas del', 'horas totales', 'tiempo asignado',
  'dimension conceptual', 'dimension actuacional', 'dimension socioafectiva',
  'evidencia de aprendizaje', 'instrumentos de evaluacion',
  'evidencia de aprendizaje instrumentos de evaluacion',
  'unidades de aprendizaje', 'resultado de aprendizaje',
  'proposito esperado', 'propósito esperado'
]);
const NOISE_LINE_RE = /^(elaboro|f\s*-\s*da|aprobo|vigente|unidades de aprendizaje)/;

// Texto que sigue a la etiqueta en la misma línea.
function inlineValue(line, key) {
  const colon = line.indexOf(':');
  if (colon >= 0) return clean(line.slice(colon + 1));
  const label = SECTION_LABELS.find((l) => l.key === key);
  const m = normKeep(line).match(label.re);
  return m ? clean(line.slice(m[0].length)) : '';
}

function toList(lines, { maxLen = 0 } = {}) {
  const items = [];
  for (const raw of lines) {
    let s = clean(raw);
    if (!s) continue;
    s = s.replace(/^([•·▪◦*\-–—]|\(?\d+[.)]|[a-zA-Z][.)]|[a-zA-Z][-–—.])\s+/, '');
    s = clean(s);
    const ns = norm(s);
    if (!s || s.length <= 2 || STOP_ITEMS.has(ns) || NOISE_LINE_RE.test(ns)) continue;
    if (maxLen && s.length > maxLen) continue;
    if (!items.includes(s)) items.push(s);
  }
  return items;
}

function parseHours(text) {
  const m = (text || '').match(/(\d+(?:[.,]\d+)?)/);
  return m ? Number(m[1].replace(',', '.')) : null;
}

const ROMAN = { i: 1, ii: 2, iii: 3, iv: 4, v: 5, vi: 6, vii: 7, viii: 8, ix: 9, x: 10, xi: 11, xii: 12 };
const UNIT_START = /^unidad\b(\s+de\s+aprendizaje|\s+aprendizaje|\s+tematica)?\s*[:.\-]?\s*(\d+|[ivxlcdm]+)?\s*[:.\-–—]?\s*(.*)$/i;

function isUnitHeaderLine(line) {
  const m = clean(line).match(UNIT_START);
  return !!(m && norm(line).startsWith('unidad')
    && (m[2] || (m[1] && m[3] && m[3].trim().length > 2)));
}

// "12   Horas del Saber Hacer   18   Horas Totales   30"
// → Saber (teoría) = 12, Saber Hacer (práctica) = 18
const SABER_HOURS_RE = /(\d+(?:[.,]\d+)?)\s+horas\s+del\s+saber\s+hacer\s+(\d+(?:[.,]\d+)?)\s+horas\s+totales\s+(\d+(?:[.,]\d+)?)/i;

// Instrumentos de evaluación que aparecen como lista al final de la unidad.
const CRITERIA_ITEM_RE = /^(caso\s+practico|lista\s+de\s+cotejo|rubrica\.?|examen|portafolio|ensayo|proyecto|presentacion|bitacora|diario\s+de\s+campo)/;

function parseUnits(lines) {
  const units = [];
  let current = null;

  const flush = () => { if (current) units.push(current); current = null; };

  for (const raw of lines) {
    const line = clean(raw);
    if (!line) continue;
    const n = norm(line);

    if (isUnitHeaderLine(line)) {
      flush();
      const m = line.match(UNIT_START);
      const numStr = (m[2] || '').toLowerCase();
      const number = /^[0-9]+$/.test(numStr) ? Number(numStr) : (ROMAN[numStr] || null);
      let title = clean(m[3] || '');
      title = title.replace(/^(num\.?|numero|no\.?|#)\s*[\d.:]+\s*/i, '');
      title = title.replace(/^[:.\-–—\s]+/, '');
      current = {
        number: number ?? units.length + 1,
        title: title || `Unidad ${units.length + 1}`,
        objectives: [], competencies: [], topics: [], subtopics: [],
        outcomes: [], theoryHours: null, practiceHours: null,
        evaluationCriteria: [], _sections: {}, _lastKey: null
      };
      continue;
    }

    if (!current) continue; // líneas antes de la primera unidad

    // Horas "Saber / Saber Hacer / Totales" en formato tabla
    const hm = line.match(SABER_HOURS_RE);
    if (hm) {
      current.theoryHours = Number(hm[1].replace(',', '.'));
      current.practiceHours = Number(hm[2].replace(',', '.'));
      current._lastKey = null;
      continue;
    }

    // Encabezados/pies de página: se saltan sin cortar la sección
    if (isIgnoreLine(line)) continue;

    // Instrumentos de evaluación listados al final ("Lista de cotejo", "Rúbrica.")
    if (CRITERIA_ITEM_RE.test(n)) {
      const item = line.replace(/^[-–—•*]\s*/, '');
      if (!current.evaluationCriteria.includes(item)) current.evaluationCriteria.push(item);
      current._lastKey = null;
      continue;
    }

    // "Competencia a la que contribuye la asignatura" viene partida en dos líneas
    if (n.startsWith('competencia a la que')) { current._lastKey = null; continue; }

    const key = labelKey(line);
    if (key) {
      if (!current._sections[key]) current._sections[key] = { inline: '', lines: [] };
      const inline = inlineValue(line, key);
      if (inline) current._sections[key].inline = clean(inline);
      current._lastKey = key;
      continue;
    }

    if (current._lastKey) current._sections[current._lastKey].lines.push(line);
  }
  flush();

  for (const u of units) {
    for (const [key, sec] of Object.entries(u._sections || {})) {
      const all = [...(sec.inline ? [sec.inline] : []), ...sec.lines];
      if (key === 'theoryHours' || key === 'practiceHours') {
        const v = parseHours(all.join(' '));
        if (v != null) u[key] = v; // no borrar horas ya detectadas
      }
      else if (key === 'topics') u.topics = toList(all, { maxLen: 120 });
      else if (key === 'subtopics') u.subtopics = toList(all, { maxLen: 120 });
      else if (key === 'outcomes') u.outcomes = toList(all);
      else if (key === 'criteria') u.evaluationCriteria = [...new Set([...u.evaluationCriteria, ...toList(all)])];
      else if (key === 'objectives') u.objectives = toList(all);
      else if (key === 'competencies') u.competencies = toList(all);
    }
    u.evaluationCriteria = toList(u.evaluationCriteria);
    delete u._sections;
    delete u._lastKey;
  }
  return units;
}

function parseGeneral(lines, unitsEndIndex) {
  const general = { subjectName: null, competencies: [], objectives: [] };
  let currentKey = null;

  for (const raw of lines.slice(0, unitsEndIndex)) {
    const line = clean(raw);
    if (!line) continue;
    const n = norm(line);

    // "PROGRAMA DE ASIGNATURA: NOMBRE   CLAVE : X"
    const prog = line.match(/programa\s+de\s+asignatura\s*[:.]?\s*(.+?)(?:\s+clave\s*[:.]?|$)/i);
    if (prog && prog[1]) { general.subjectName = clean(prog[1]); continue; }

    const subj = line.match(/^(nombre\s+de\s+la\s+asignatura|asignatura|materia|curso|denominacion\s+de\s+la\s+asignatura)\s*[:.\-]?\s*(.+)$/i);
    if (subj && subj[2]) { general.subjectName = clean(subj[2]); continue; }

    if (isIgnoreLine(line)) { currentKey = null; continue; }
    if (n.startsWith('competencia a la que')) { currentKey = 'competencies'; continue; }
    if (currentKey === 'competencies' && n === 'contribuye la asignatura') continue;

    const key = labelKey(line);
    if (key === 'competencies' || key === 'objectives') {
      currentKey = key;
      const inline = inlineValue(line, key);
      if (inline) (key === 'competencies' ? general.competencies : general.objectives).push(inline);
      continue;
    }
    if (currentKey === 'competencies') general.competencies.push(line);
    else if (currentKey === 'objectives') general.objectives.push(line);
  }
  general.competencies = toList(general.competencies);
  general.objectives = toList(general.objectives);
  return general;
}

function findFirstUnitIndex(lines) {
  for (let i = 0; i < lines.length; i++) {
    if (isUnitHeaderLine(lines[i])) return i;
  }
  return lines.length;
}

export function analyzeTextHeuristic(text) {
  const lines = (text || '').split('\n').map((l) => l.trim()).filter((l) => l.length > 0);
  const units = parseUnits(lines);
  const general = parseGeneral(lines, findFirstUnitIndex(lines));

  const missing = [];
  if (!general.subjectName) missing.push('nombre de la asignatura');
  if (!general.competencies.length) missing.push('competencias generales');
  if (!general.objectives.length) missing.push('objetivos generales');
  if (!units.length) {
    missing.push('unidades de aprendizaje');
  } else {
    if (!units.some((u) => u.topics.length)) missing.push('temas');
    if (!units.some((u) => u.outcomes.length)) missing.push('resultados de aprendizaje');
    if (!units.some((u) => u.theoryHours != null || u.practiceHours != null)) missing.push('horas teóricas/prácticas');
    if (!units.some((u) => u.evaluationCriteria.length)) missing.push('criterios de evaluación');
    for (const u of units) {
      if (!u.title || /^unidad \d+$/i.test(u.title)) missing.push(`título de la unidad ${u.number}`);
    }
  }

  return {
    subjectName: general.subjectName,
    competencies: general.competencies,
    objectives: general.objectives,
    units,
    missing: [...new Set(missing)],
    engine: 'heuristic'
  };
}

// ---------- Motor opcional: LLM (API compatible con OpenAI) ----------
const AI_MAX_CHARS = 30000;

async function analyzeTextAI(text) {
  const base = process.env.AI_API_BASE;
  const key = process.env.AI_API_KEY;
  const model = process.env.AI_MODEL || 'gpt-4o-mini';
  if (!base || !key) return null;

  const prompt = `Eres un analista de cartas descriptivas de cursos universitarios mexicanos. Del siguiente texto extraído de un documento, extrae un JSON con esta estructura exacta:
{
  "subjectName": string|null,
  "competencies": string[],
  "objectives": string[],
  "units": [{
    "number": number, "title": string, "objectives": string[], "topics": string[],
    "subtopics": string[], "outcomes": string[],
    "theoryHours": number|null, "practiceHours": number|null,
    "evaluationCriteria": string[]
  }]
}
Reglas: no inventes datos; si algo no aparece usa null o []. Responde SOLO con JSON válido.`;

  const res = await fetch(`${base.replace(/\/$/, '')}/chat/completions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}` },
    body: JSON.stringify({
      model,
      messages: [
        { role: 'system', content: prompt },
        { role: 'user', content: text.slice(0, AI_MAX_CHARS) }
      ],
      temperature: 0,
      response_format: { type: 'json_object' }
    })
  });
  if (!res.ok) throw new Error(`AI API error ${res.status}: ${(await res.text()).slice(0, 200)}`);
  const json = await res.json();
  const content = json.choices?.[0]?.message?.content;
  if (!content) throw new Error('La IA no devolvió contenido');
  const parsed = JSON.parse(content);
  return { ...parsed, engine: 'ai', missing: [] };
}

export async function analyzeText(text) {
  // Intenta IA si está configurada; si falla, cae al parser heurístico.
  try {
    const ai = await analyzeTextAI(text);
    if (ai && Array.isArray(ai.units)) return ai;
  } catch (e) {
    console.warn(`[analyze] Motor IA no disponible, usando heurístico: ${e.message}`);
  }
  return analyzeTextHeuristic(text);
}
