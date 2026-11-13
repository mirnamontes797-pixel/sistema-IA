export async function loadLeaflet() {
  if (typeof window === 'undefined' || typeof document === 'undefined') {
    throw new Error('Leaflet solo está disponible en el navegador');
  }

  const [{ default: L }] = await Promise.all([
    import('leaflet'),
    import('leaflet/dist/leaflet.css')
  ]);

  return L;
}
