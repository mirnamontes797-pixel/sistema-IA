-- ============================================================
-- Migración: datos académicos extraídos de la carta descriptiva
-- Ejecutar en Supabase: SQL Editor > New query > pegar y Run.
-- ============================================================

alter table public.courses
  add column if not exists competencies text[] not null default '{}',
  add column if not exists objectives text[] not null default '{}';
