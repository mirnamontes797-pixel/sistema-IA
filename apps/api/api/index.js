// Entrada serverless para Vercel (project root = apps/api)
import { createApp } from '../src/app.js';

const app = createApp();

// Handler explícito: Vercel requiere que el default export sea una función.
export default function handler(req, res) {
  return app(req, res);
}
