import { createApp } from './app.js';
import { env } from './config/env.js';

const app = createApp();

// En Vercel no se hace listen: se exporta la app para el runtime serverless.
export default app;

if (!process.env.VERCEL) {
  app.listen(env.port, () => {
    console.log(`API escuchando en http://localhost:${env.port}`);
  });
}
