import express from 'express';
import cors from 'cors';
import authRoutes from './routes/auth.js';
import crudRoutes from './routes/crud.js';
import planRoutes from './routes/plan.js';
import documentRoutes from './routes/documents.js';
import institutionRoutes from './routes/institutions.js';
import geofenceRoutes from './routes/geofences.js';
import analysisRoutes from './routes/analysis.js';
import academicConfigRoutes from './routes/academicConfig.js';
import { env } from './config/env.js';

export function createApp() {
  const app = express();
  app.use(cors());
  app.use(express.json({ limit: '1mb' }));

  app.get('/api/health', (req, res) => res.json({ ok: true, env: env.nodeEnv }));
  app.use('/api/auth', authRoutes);
  app.use('/api', crudRoutes);
  app.use('/api', planRoutes);
  app.use('/api', documentRoutes);
  app.use('/api', institutionRoutes);
  app.use('/api', geofenceRoutes);
  app.use('/api', analysisRoutes);
  app.use('/api', academicConfigRoutes);

  app.use((req, res) => res.status(404).json({ error: 'Ruta no encontrada' }));
  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    console.error(err);
    res.status(500).json({ error: 'Error interno del servidor' });
  });
  return app;
}
