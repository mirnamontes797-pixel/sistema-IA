import { Router } from 'express';
import multer from 'multer';
import { randomUUID } from 'node:crypto';
import { supabase } from '../lib/supabase.js';
import { requireAuth } from '../lib/auth.js';

const router = Router();
router.use(requireAuth);

const BUCKET = 'course-documents';
const MIME_BY_EXTENSION = {
  pdf: 'application/pdf',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
};
const ALLOWED_EXTENSIONS = new Set(Object.keys(MIME_BY_EXTENSION));
const MAX_SIZE = 25 * 1024 * 1024;
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_SIZE, files: 1 },
  fileFilter: (req, file, cb) => {
    const extension = file.originalname.split('.').pop()?.toLowerCase();
    if (!ALLOWED_EXTENSIONS.has(extension)) {
      return cb(new Error('Solo se permiten archivos PDF, Word (.docx) o Excel (.xlsx)'));
    }
    cb(null, true);
  }
});

const storage = () => supabase.storage.from(BUCKET);

function documentView(info) {
  const metadata = info.metadata || {};
  const fileName = info.name?.split('/').pop() || '';
  const extension = (metadata.extension || fileName.split('.').pop() || '').toLowerCase();
  return {
    id: metadata.documentId || info.id,
    courseId: metadata.courseId,
    name: metadata.originalName || fileName,
    format: extension.toUpperCase(),
    mimeType: metadata.mimeType || info.contentType,
    sizeBytes: Number(metadata.sizeBytes ?? info.size ?? 0),
    uploadedAt: metadata.uploadedAt || info.createdAt || info.lastModified
  };
}

function uploadError(err, req, res) {
  if (err instanceof multer.MulterError) {
    return res.status(err.code === 'LIMIT_FILE_SIZE' ? 413 : 400).json({ error: err.code === 'LIMIT_FILE_SIZE' ? 'El archivo no puede superar 25 MB' : 'Solo se permite un archivo por carga' });
  }
  return res.status(400).json({ error: err.message || 'No se pudo procesar el archivo' });
}

function canManageDocument(req, course) {
  return req.user.role === 'admin' || course.instructor_id === req.user.sub;
}

async function requireDocumentAccess(req, res) {
  const { data: course, error } = await supabase.from('courses').select('id, instructor_id').eq('id', req.params.id).maybeSingle();
  if (error) {
    res.status(500).json({ error: `No se pudo consultar el curso: ${error.message}` });
    return null;
  }
  if (!course) {
    res.status(404).json({ error: 'Curso no encontrado' });
    return null;
  }
  if (!canManageDocument(req, course)) {
    res.status(403).json({ error: 'No tienes permiso para administrar documentos de este curso' });
    return null;
  }
  return course;
}

async function listCourseObjects(courseId) {
  const { data, error } = await storage().listV2({
    prefix: `${courseId}/`,
    limit: 100,
    sortBy: { column: 'created_at', order: 'desc' }
  });
  if (error) return { objects: [], error };
  return {
    objects: (data?.objects || []).filter((object) => object.id && object.name?.startsWith(`${courseId}/`) && !object.is_delete_marker),
    error: null
  };
}

async function findStoredDocument(courseId, documentId) {
  const { objects, error } = await listCourseObjects(courseId);
  if (error) return { document: null, path: null, error };
  for (const object of objects) {
    const { data: info, error: infoError } = await storage().info(object.name);
    if (infoError) return { document: null, path: null, error: infoError };
    const document = documentView(info);
    if (!documentId || document.id === documentId) return { document, path: info.name, error: null };
  }
  return { document: null, path: null, error: null };
}

async function uploadDocument(req, res) {
  if (!req.file) return res.status(400).json({ error: 'Selecciona un archivo PDF, Word o Excel' });
  const course = await requireDocumentAccess(req, res);
  if (!course) return;

  const extension = req.file.originalname.split('.').pop().toLowerCase();
  const documentId = randomUUID();
  const safeName = req.file.originalname.replace(/[^\w.áéíóúñü()-]/gi, '_').slice(-120);
  const storagePath = `${course.id}/${documentId}_${safeName}`;
  const { objects: previousObjects, error: listError } = await listCourseObjects(course.id);
  if (listError) return res.status(500).json({ error: `No se pudo consultar el documento actual: ${listError.message}` });

  const { error: storageError } = await storage().upload(storagePath, req.file.buffer, {
    contentType: MIME_BY_EXTENSION[extension],
    cacheControl: '31536000',
    upsert: false,
    metadata: {
      documentId,
      courseId: course.id,
      originalName: req.file.originalname,
      mimeType: MIME_BY_EXTENSION[extension],
      extension,
      sizeBytes: req.file.size,
      uploadedBy: req.user.sub,
      uploadedAt: new Date().toISOString()
    }
  });
  if (storageError) return res.status(500).json({ error: `No se pudo guardar el archivo: ${storageError.message}` });

  const { data: info, error: infoError } = await storage().info(storagePath);
  if (infoError) {
    await storage().remove([storagePath]);
    return res.status(500).json({ error: `No se pudo registrar el documento: ${infoError.message}` });
  }

  if (previousObjects.length) await storage().remove(previousObjects.map((object) => object.name));
  res.status(previousObjects.length ? 200 : 201).json({
    data: documentView(info),
    message: previousObjects.length ? 'Documento reemplazado correctamente' : 'Documento cargado correctamente'
  });
}

router.get('/courses/:id/documents', async (req, res) => {
  const course = await requireDocumentAccess(req, res);
  if (!course) return;
  const { document, error } = await findStoredDocument(course.id);
  if (error) return res.status(500).json({ error: `No se pudo consultar el documento: ${error.message}` });
  res.json({ data: document });
});

router.post('/courses/:id/documents', (req, res) => upload.single('file')(req, res, (err) => {
  if (err) return uploadError(err, req, res);
  uploadDocument(req, res).catch((error) => res.status(500).json({ error: error.message }));
}));

router.get('/courses/:id/documents/:documentId/file', async (req, res) => {
  const course = await requireDocumentAccess(req, res);
  if (!course) return;
  const { document, path, error } = await findStoredDocument(course.id, req.params.documentId);
  if (error) return res.status(500).json({ error: `No se pudo consultar el documento: ${error.message}` });
  if (!document || !path) return res.status(404).json({ error: 'Documento no encontrado' });

  const { data, error: downloadError } = await storage().download(path);
  if (downloadError || !data) return res.status(500).json({ error: downloadError?.message || 'No se pudo abrir el documento' });
  const buffer = Buffer.from(await data.arrayBuffer());
  const disposition = req.query.download === 'true' ? 'attachment' : 'inline';
  const safeName = document.name.replace(/["\\]/g, '_');
  res.set({
    'Content-Type': document.mimeType,
    'Content-Length': buffer.length,
    'Content-Disposition': `${disposition}; filename="${safeName}"; filename*=UTF-8''${encodeURIComponent(document.name)}`
  });
  res.send(buffer);
});

router.delete('/courses/:id/documents/:documentId', async (req, res) => {
  const course = await requireDocumentAccess(req, res);
  if (!course) return;
  const { document, path, error } = await findStoredDocument(course.id, req.params.documentId);
  if (error) return res.status(500).json({ error: `No se pudo consultar el documento: ${error.message}` });
  if (!document || !path) return res.status(404).json({ error: 'Documento no encontrado' });

  const { error: deleteError } = await storage().remove([path]);
  if (deleteError) return res.status(500).json({ error: `No se pudo eliminar el archivo: ${deleteError.message}` });
  res.json({ ok: true, message: 'Documento eliminado correctamente' });
});

export default router;
