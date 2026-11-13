import { Router } from 'express';
import { supabase } from '../lib/supabase.js';
import { requireAuth } from '../lib/auth.js';
import { extractText } from '../services/extractText.js';
import { analyzeText } from '../services/analyze.js';

const router = Router();
router.use(requireAuth);

const BUCKET = 'course-documents';
const storage = () => supabase.storage.from(BUCKET);

function canManageDocument(req, course) {
  return req.user.role === 'admin' || course.instructor_id === req.user.sub;
}

async function requireCourse(req, res) {
  const { data: course, error } = await supabase
    .from('courses').select('id, instructor_id, name, description').eq('id', req.params.id).maybeSingle();
  if (error) { res.status(500).json({ error: error.message }); return null; }
  if (!course) { res.status(404).json({ error: 'Curso no encontrado' }); return null; }
  if (!canManageDocument(req, course)) {
    res.status(403).json({ error: 'No tienes permiso para administrar documentos de este curso' });
    return null;
  }
  return course;
}

async function listCourseObjects(courseId) {
  const { data, error } = await storage().listV2({
    prefix: `${courseId}/`, limit: 100,
    sortBy: { column: 'created_at', order: 'desc' }
  });
  if (error) return { objects: [], error };
  return {
    objects: (data?.objects || []).filter((o) => o.id && o.name?.startsWith(`${courseId}/`) && !o.is_delete_marker),
    error: null
  };
}

async function findLatestDocument(courseId) {
  const { objects, error } = await listCourseObjects(courseId);
  if (error) return { document: null, path: null, error };
  for (const object of objects) {
    const { data: info, error: infoError } = await storage().info(object.name);
    if (infoError) return { document: null, path: null, error: infoError };
    const metadata = info.metadata || {};
    const fileName = info.name?.split('/').pop() || '';
    const extension = (metadata.extension || fileName.split('.').pop() || '').toLowerCase();
    return {
      document: {
        id: metadata.documentId || info.id,
        name: metadata.originalName || fileName,
        extension,
        mimeType: metadata.mimeType || info.contentType
      },
      path: info.name,
      error: null
    };
  }
  return { document: null, path: null, error: null };
}

// POST /courses/:id/documents/analyze — lee el archivo real y extrae datos
router.post('/courses/:id/documents/analyze', async (req, res) => {
  const course = await requireCourse(req, res);
  if (!course) return;

  const { document, path, error } = await findLatestDocument(course.id);
  if (error) return res.status(500).json({ error: `No se pudo consultar el documento: ${error.message}` });
  if (!document || !path) return res.status(404).json({ error: 'Este curso no tiene una carta descriptiva cargada' });

  const { data: blob, error: downloadError } = await storage().download(path);
  if (downloadError || !blob) {
    return res.status(500).json({ error: downloadError?.message || 'No se pudo descargar el documento' });
  }
  const buffer = Buffer.from(await blob.arrayBuffer());

  try {
    const { text, warnings } = await extractText(buffer, document.extension, document.name);
    if (!text.trim()) {
      return res.status(422).json({
        error: 'No se pudo extraer texto del documento. Puede ser un PDF escaneado como imagen.',
        warnings
      });
    }
    const analysis = await analyzeText(text);
    res.json({
      data: {
        documentName: document.name,
        documentId: document.id,
        extractedAt: new Date().toISOString(),
        engine: analysis.engine,
        subjectName: analysis.subjectName,
        competencies: analysis.competencies || [],
        objectives: analysis.objectives || [],
        units: (analysis.units || []).map((u, i) => ({
          number: u.number ?? i + 1,
          title: u.title || '',
          objectives: u.objectives || [],
          topics: u.topics || [],
          subtopics: u.subtopics || [],
          outcomes: u.outcomes || [],
          theoryHours: u.theoryHours ?? null,
          practiceHours: u.practiceHours ?? null,
          evaluationCriteria: u.evaluationCriteria || []
        })),
        missing: analysis.missing || []
      },
      warnings
    });
  } catch (e) {
    console.error('[analyze]', e);
    res.status(500).json({ error: `No se pudo analizar el documento: ${e.message}` });
  }
});

// POST /courses/:id/academic-data — guarda lo confirmado por el usuario.
// No elimina información existente: actualiza unidades por número y
// solo inserta resultados/actividades/rúbricas que no existan ya.
router.post('/courses/:id/academic-data', async (req, res) => {
  const course = await requireCourse(req, res);
  if (!course) return;

  const body = req.body || {};
  const units = Array.isArray(body.units) ? body.units : [];
  const competencies = Array.isArray(body.competencies) ? body.competencies.filter(Boolean) : [];
  const objectives = Array.isArray(body.objectives) ? body.objectives.filter(Boolean) : [];
  if (!units.length) return res.status(400).json({ error: 'No hay unidades para guardar' });

  // Datos generales del curso (solo columnas nuevas de la migración 0005)
  const courseUpdate = {};
  if (competencies.length) courseUpdate.competencies = competencies;
  if (objectives.length) courseUpdate.objectives = objectives;
  if (body.subjectName && body.subjectName !== course.name) {
    courseUpdate.description = course.description
      ? `${course.description}\nAsignatura según carta: ${body.subjectName}`
      : `Asignatura según carta: ${body.subjectName}`;
  }
  if (Object.keys(courseUpdate).length) {
    let { error } = await supabase.from('courses').update(courseUpdate).eq('id', course.id);
    // Si la migración 0005 aún no se ejecuta, reintenta solo con description.
    if (error && /column|competenc|objectives/i.test(error.message) && courseUpdate.description) {
      const { error: retryError } = await supabase
        .from('courses').update({ description: courseUpdate.description }).eq('id', course.id);
      error = retryError;
    }
    if (error) return res.status(500).json({ error: `No se pudieron guardar los datos del curso: ${error.message}` });
  }

  const summary = { unitsCreated: 0, unitsUpdated: 0, outcomesAdded: 0, activitiesAdded: 0, rubricsAdded: 0 };

  const { data: existingUnits, error: unitsErr } = await supabase
    .from('units').select('id, number, title').eq('course_id', course.id);
  if (unitsErr) return res.status(500).json({ error: unitsErr.message });
  const unitByNumber = new Map((existingUnits || []).map((u) => [Number(u.number), u]));

  for (const u of units) {
    const number = Number(u.number) || units.indexOf(u) + 1;
    const payload = {
      course_id: course.id,
      number,
      title: cleanStr(u.title) || `Unidad ${number}`,
      objectives: Array.isArray(u.objectives) && u.objectives.length ? u.objectives.join('\n') : null
    };

    let unitId;
    const existing = unitByNumber.get(number);
    if (existing) {
      unitId = existing.id;
      const { error } = await supabase.from('units').update({ title: payload.title, objectives: payload.objectives }).eq('id', unitId);
      if (error) return res.status(500).json({ error: error.message });
      summary.unitsUpdated++;
    } else {
      const { data, error } = await supabase.from('units').insert(payload).select().single();
      if (error) return res.status(500).json({ error: error.message });
      unitId = data.id;
      unitByNumber.set(number, data);
      summary.unitsCreated++;
    }

    // Resultados de aprendizaje: insertar solo los que no existan (por título)
    const { data: existingOutcomes } = await supabase.from('outcomes').select('title').eq('unit_id', unitId);
    const have = new Set((existingOutcomes || []).map((o) => (o.title || '').toLowerCase()));
    const outcomeRows = (u.outcomes || []).filter((t) => t && !have.has(String(t).toLowerCase()))
      .map((t) => ({ unit_id: unitId, title: String(t).slice(0, 500) }));
    if (outcomeRows.length) {
      const { error } = await supabase.from('outcomes').insert(outcomeRows);
      if (error) return res.status(500).json({ error: error.message });
      summary.outcomesAdded += outcomeRows.length;
    }

    // Horas teóricas/prácticas como actividades (solo si no existen ya con ese título)
    const { data: existingActs } = await supabase.from('activities').select('title, hours').eq('unit_id', unitId);
    const actTitles = new Set((existingActs || []).map((a) => (a.title || '').toLowerCase()));
    const actRows = [];
    const th = Number(u.theoryHours);
    const ph = Number(u.practiceHours);
    if (Number.isFinite(th) && th > 0 && !actTitles.has('carga teórica (carta descriptiva)')) {
      actRows.push({ unit_id: unitId, title: 'Carga teórica (carta descriptiva)', type: 'clase', hours: th, modality: 'presencial' });
    }
    if (Number.isFinite(ph) && ph > 0 && !actTitles.has('carga práctica (carta descriptiva)')) {
      actRows.push({ unit_id: unitId, title: 'Carga práctica (carta descriptiva)', type: 'laboratorio', hours: ph, modality: 'presencial' });
    }
    if (actRows.length) {
      const { error } = await supabase.from('activities').insert(actRows);
      if (error) return res.status(500).json({ error: error.message });
      summary.activitiesAdded += actRows.length;
    }

    // Criterios de evaluación → rúbrica por unidad (una sola vez)
    const criteria = (u.evaluationCriteria || []).map((c) => String(c)).filter(Boolean);
    if (criteria.length) {
      const { data: existingRubrics } = await supabase.from('rubrics').select('id, title').eq('unit_id', unitId);
      const already = (existingRubrics || []).some((r) => /criterios de evaluaci/i.test(r.title || ''));
      if (!already) {
        const { error } = await supabase.from('rubrics').insert({
          unit_id: unitId,
          title: 'Criterios de evaluación (carta descriptiva)',
          criteria: criteria.map((name) => ({ name, levels: [] }))
        });
        if (error) return res.status(500).json({ error: error.message });
        summary.rubricsAdded++;
      }
    }
  }

  res.json({ ok: true, message: 'Información académica guardada correctamente', summary });
});

function cleanStr(s) { return (s || '').replace(/\s+/g, ' ').trim(); }

export default router;
