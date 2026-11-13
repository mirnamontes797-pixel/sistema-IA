-- ============================================================
-- Migración: almacenamiento privado de cartas descriptivas
-- Ejecutar en Supabase: SQL Editor > New query > pegar y Run.
-- ============================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'course-documents',
  'course-documents',
  false,
  25000000,
  array[
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  ]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- La metadata del documento (nombre original, usuario, curso y fecha)
-- se guarda en storage.objects.metadata. El acceso está controlado por
-- la API con JWT propio; el bucket permanece privado y no hay URLs públicas.
