-- ============================================================
-- Migración inicial: Plataforma de Planeación Académica
-- Ejecutar en Supabase: SQL Editor > New query > pegar y Run.
-- ============================================================

create extension if not exists "pgcrypto";

-- ---------- Usuarios ----------
create table if not exists public.users (
  id uuid primary key default gen_random_uuid(),
  email text unique not null,
  password_hash text not null,
  full_name text not null,
  role text not null default 'instructor' check (role in ('admin', 'instructor', 'viewer')),
  created_at timestamptz not null default now()
);

-- ---------- Cursos ----------
create table if not exists public.courses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  instructor_id uuid references public.users(id) on delete set null,
  cuatrimestre_weeks int not null default 16 check (cuatrimestre_weeks between 1 and 30),
  total_hours numeric(6,1) not null default 64,
  created_at timestamptz not null default now()
);

-- ---------- Unidades ----------
create table if not exists public.units (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  number int not null,
  title text not null,
  objectives text,
  created_at timestamptz not null default now(),
  unique (course_id, number)
);

-- ---------- Resultados de aprendizaje (RA) ----------
create table if not exists public.outcomes (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id) on delete cascade,
  code text,
  title text not null,
  bloom_level text check (bloom_level in ('conocimiento','comprension','aplicacion','analisis','sintesis','evaluacion')),
  created_at timestamptz not null default now()
);

-- ---------- Actividades ----------
create table if not exists public.activities (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id) on delete cascade,
  title text not null,
  type text not null default 'clase' check (type in ('clase','laboratorio','proyecto','examen','tarea','foro','seminario','lectura','asesoria')),
  hours numeric(5,1) not null default 0,
  modality text not null default 'presencial' check (modality in ('presencial','teams','asincrona')),
  week int,
  start_date date,
  created_at timestamptz not null default now()
);

-- ---------- Evaluaciones ----------
create table if not exists public.evaluations (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.units(id) on delete cascade,
  title text not null,
  type text not null default 'parcial' check (type in ('parcial','final','entrega','quiz','examen','participacion','proyecto')),
  weight numeric(5,2) not null default 0 check (weight between 0 and 100),
  week int,
  due_date date,
  created_at timestamptz not null default now()
);

-- ---------- Rúbricas ----------
create table if not exists public.rubrics (
  id uuid primary key default gen_random_uuid(),
  evaluation_id uuid references public.evaluations(id) on delete cascade,
  unit_id uuid references public.units(id) on delete cascade,
  title text not null,
  criteria jsonb not null default '[]'::jsonb,
  -- criteria: [{ "name": "...", "levels": [{"label":"Excelente","points":4},...] }]
  created_at timestamptz not null default now()
);

-- ---------- Índices ----------
create index if not exists idx_units_course on public.units(course_id);
create index if not exists idx_outcomes_unit on public.outcomes(unit_id);
create index if not exists idx_activities_unit on public.activities(unit_id);
create index if not exists idx_evaluations_unit on public.evaluations(unit_id);
create index if not exists idx_rubrics_unit on public.rubrics(unit_id);

-- ---------- RLS ----------
-- El backend usa service_role (bypass RLS). Estas políticas son
-- para acceso directo desde clientes anon/auth si se habilita.
alter table public.users enable row level security;
alter table public.courses enable row level security;
alter table public.units enable row level security;
alter table public.outcomes enable row level security;
alter table public.activities enable row level security;
alter table public.evaluations enable row level security;
alter table public.rubrics enable row level security;

create policy "service role full access" on public.users
  for all using (auth.role() = 'service_role');
create policy "service role full access" on public.courses
  for all using (auth.role() = 'service_role');
create policy "service role full access" on public.units
  for all using (auth.role() = 'service_role');
create policy "service role full access" on public.outcomes
  for all using (auth.role() = 'service_role');
create policy "service role full access" on public.activities
  for all using (auth.role() = 'service_role');
create policy "service role full access" on public.evaluations
  for all using (auth.role() = 'service_role');
create policy "service role full access" on public.rubrics
  for all using (auth.role() = 'service_role');
