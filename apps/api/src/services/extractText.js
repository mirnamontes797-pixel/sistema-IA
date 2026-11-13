import mammoth from 'mammoth';
import * as XLSX from 'xlsx';

// Extrae texto plano de un buffer según la extensión del archivo.
// Devuelve { text, warnings } — nunca inventa contenido.
export async function extractText(buffer, extension, originalName = '') {
  const ext = (extension || originalName.split('.').pop() || '').toLowerCase();
  const warnings = [];

  if (ext === 'pdf') {
    // Import dinámico: pdfjs-dist es pesado y en Vercel intenta cargar
    // @napi-rs/canvas (binario nativo). Solo se carga al analizar PDFs.
    const pdfjs = await import('pdfjs-dist/legacy/build/pdf.mjs');
    const doc = await pdfjs.getDocument({
      data: new Uint8Array(buffer),
      useWorkerFetch: false,
      isEvalSupported: false,
      disableFontFace: true
    }).promise;
    const parts = [];
    for (let p = 1; p <= doc.numPages; p++) {
      const page = await doc.getPage(p);
      const content = await page.getTextContent();
      // Agrupa fragmentos por coordenada Y para conservar los renglones.
      let text = '';
      let lastY = null;
      for (const item of content.items) {
        if (!item.str) continue;
        const y = item.transform?.[5];
        if (lastY !== null && typeof y === 'number' && Math.abs(y - lastY) > 2) text += '\n';
        else if (text && !text.endsWith('\n')) text += ' ';
        text += item.str;
        if (typeof y === 'number') lastY = y;
      }
      parts.push(text);
    }
    await doc.destroy();
    const text = parts.join('\n');
    if (!text.trim()) warnings.push('El PDF no contiene texto seleccionable (puede ser una imagen escaneada).');
    return { text, warnings };
  }

  if (ext === 'docx') {
    const result = await mammoth.extractRawText({ buffer });
    const text = result.value || '';
    for (const m of result.messages || []) {
      if (m.type === 'warning') warnings.push(`Word: ${m.message}`);
    }
    if (!text.trim()) warnings.push('El documento Word no contiene texto extraíble.');
    return { text, warnings };
  }

  if (ext === 'xlsx' || ext === 'xls' || ext === 'csv') {
    const workbook = XLSX.read(buffer, { type: 'buffer' });
    const parts = [];
    for (const sheetName of workbook.SheetNames) {
      const sheet = workbook.Sheets[sheetName];
      const csv = XLSX.utils.sheet_to_csv(sheet, { blankrows: false });
      if (csv.trim()) parts.push(`--- Hoja: ${sheetName} ---\n${csv}`);
    }
    const text = parts.join('\n\n');
    if (!text.trim()) warnings.push('El archivo Excel no contiene datos en ninguna hoja.');
    return { text, warnings };
  }

  throw new Error(`Formato no soportado para análisis: .${ext || '(sin extensión)'}`);
}
