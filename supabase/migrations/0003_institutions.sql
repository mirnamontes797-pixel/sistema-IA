-- ============================================================
-- Migración: Mapa de Instituciones
-- Ejecutar en Supabase: SQL Editor > New query > pegar y Run.
-- ============================================================

-- ---------- Instituciones educativas ----------
create table if not exists public.institutions (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  address text not null,
  latitude numeric(9,6) not null check (latitude between -90 and 90),
  longitude numeric(9,6) not null check (longitude between -180 and 180),
  created_at timestamptz not null default now()
);

create index if not exists idx_institutions_coords on public.institutions(latitude, longitude);

-- ---------- RLS ----------
alter table public.institutions enable row level security;

create policy "service role full access" on public.institutions
  for all using (auth.role() = 'service_role');
