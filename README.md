# Plataforma de Planeación Académica

Sistema de administración para organizar **contenidos, resultados de aprendizaje, actividades y evaluaciones** según las semanas disponibles del cuatrimestre.

## Stack

| Capa | Tecnología |
|---|---|
| Frontend | SvelteKit (Svelte 5) |
| Backend | Node.js + Express (serverless en Vercel) |
| Base de datos | Supabase (PostgreSQL) |
| Deploy | Vercel (monorepo, 2 proyectos) |

## Estructura

```
├── apps/
│   ├── api/          # Express + Supabase + JWT + bcrypt
│   │   ├── api/index.js      # entrada serverless Vercel
│   │   └── src/              # rutas, servicios, auth
│   └── web/          # SvelteKit + adapter-vercel
├── supabase/
│   └── migrations/   # esquema SQL
├── .env.example      # plantilla de variables (nunca subir .env)
└── package.json      # workspaces npm
```

## Funciones

- **Planeación por unidad**: unidades, resultados de aprendizaje (taxonomía de Bloom), actividades y evaluaciones por curso.
- **Cronogramas**: vista semanal de actividades y evaluaciones (`/cursos/:id/cronograma`).
- **Distribución de horas**: `POST /api/courses/:id/balance` reparte actividades sin semana en las semanas con menor carga (greedy por horas, respeta asignaciones manuales y unidad).
- **Balance entre instructores**: `GET /api/balance/instructors` suma la carga semanal por instructor.
- **Rúbricas**: criterios con niveles y puntos, asociadas a unidad o evaluación.
- **Instrucciones para Teams**: `POST /api/teams/instructions` genera el texto listo para pegar en una tarea de Teams (objetivos, RAs, rúbrica, entrega).

## Seguridad

- Contraseñas hasheadas con **bcrypt** (`BCRYPT_ROUNDS`, default 12).
- Autenticación **JWT** (`JWT_SECRET`); rutas protegidas con middleware.
- Service Role Key de Supabase **solo en el backend**; el front nunca la ve.
- Todo lo sensible va en `.env` (ver `.env.example`); `.env` está en `.gitignore`.

## Setup local

1. `npm install`
2. Crear proyecto en [Supabase](https://supabase.com) y ejecutar `supabase/migrations/0001_init.sql` en el SQL Editor.
3. Copiar `.env.example` → `.env` y rellenar:
   - `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (Settings → API)
   - `JWT_SECRET` (ej. `openssl rand -base64 48`)
4. `npm run dev:api` (puerto 3001) y `npm run dev:web` (puerto 5173, proxy `/api`).

## Deploy en Vercel (monorepo)

Crea **dos proyectos** en Vercel importando el mismo repo:

**Proyecto API** (`apps/api`):
- Root Directory: `apps/api`
- Framework: Other
- Env vars: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `JWT_SECRET`, `JWT_EXPIRES_IN`, `BCRYPT_ROUNDS`, `NODE_ENV=production`

**Proyecto Web** (`apps/web`):
- Root Directory: `apps/web`
- Framework: SvelteKit (auto-detectado)
- Env vars: `PUBLIC_API_URL=https://<tu-api>.vercel.app/api` (la API expone rutas bajo `/api`).

## API (resumen)

```
POST /api/auth/register|login     GET /api/auth/me
GET|POST /api/courses             PATCH|DELETE /api/courses/:id
GET|POST /api/units|outcomes|activities|evaluations|rubrics
GET  /api/courses/:id/plan        GET /api/courses/:id/schedule
POST /api/courses/:id/balance     GET /api/balance/instructors
POST /api/teams/instructions
```

Todas las rutas excepto `/api/auth/*` y `/api/health` requieren `Authorization: Bearer <token>`.
