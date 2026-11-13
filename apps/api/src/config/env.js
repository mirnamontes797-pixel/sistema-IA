import 'dotenv/config';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';

// En monorepo el .env vive en la raíz; en Vercel las vars vienen del entorno.
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootEnv = path.resolve(__dirname, '../../../../.env');
dotenv.config({ path: rootEnv });
dotenv.config(); // también lee .env local del paquete

const required = ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'JWT_SECRET'];
const missing = required.filter((k) => !process.env[k]);
if (missing.length && process.env.NODE_ENV === 'production') {
  throw new Error(`Faltan variables de entorno: ${missing.join(', ')}`);
}

export const env = {
  supabaseUrl: process.env.SUPABASE_URL,
  supabaseKey: process.env.SUPABASE_SERVICE_ROLE_KEY,
  jwtSecret: process.env.JWT_SECRET || 'dev-only-secret-change-me',
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '7d',
  bcryptRounds: Number(process.env.BCRYPT_ROUNDS || 12),
  port: Number(process.env.API_PORT || 3001),
  nodeEnv: process.env.NODE_ENV || 'development'
};
