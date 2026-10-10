// Same-origin PDF renderer. No eval, CDN scripts, document uploads or public links.
let pdfLibrary;
const library = () => pdfLibrary ??= import('./vendor/pdfjs/pdf.min.mjs').then(pdf => {
  pdf.GlobalWorkerOptions.workerSrc = new URL('./vendor/pdfjs/pdf.worker.min.mjs', import.meta.url).href;
  return pdf;
});
window.recipeScoutPdfRaster = async bytes => {
  const pdf = await library();
  const task = pdf.getDocument({data: bytes.slice(), isEvalSupported: false,
    useSystemFonts: false, wasmUrl: new URL('./vendor/pdfjs/wasm/', import.meta.url).href});
  const document = await task.promise;
  try {
    if (document.numPages > 100) throw new Error('Too many document pages');
    const pages = [];
    for (let n = 1; n <= document.numPages; n++) {
      const page = await document.getPage(n);
      const viewport = page.getViewport({scale: 85 / 72});
      const canvas = window.document.createElement('canvas');
      canvas.width = Math.ceil(viewport.width); canvas.height = Math.ceil(viewport.height);
      await page.render({canvasContext: canvas.getContext('2d'), viewport}).promise;
      const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/png'));
      if (!blob) throw new Error('Preview unavailable');
      pages.push(new Uint8Array(await blob.arrayBuffer()));
      page.cleanup(); canvas.width = 0; canvas.height = 0;
    }
    return pages;
  } finally { await document.destroy(); }
};
window.recipeScoutPdfPrint = (bytes, name) => new Promise((resolve, reject) => {
  const blob = new Blob([bytes], {type:'application/pdf'});
  const url = URL.createObjectURL(blob);
  const frame = document.createElement('iframe');
  frame.title = name;
  Object.assign(frame.style, {position:'fixed',width:'1px',height:'1px',bottom:'0',right:'0',opacity:'0.01',pointerEvents:'none'});
  let settled = false;
  const cleanup = () => { frame.remove(); URL.revokeObjectURL(url); };
  const fail = () => { if (!settled) { settled = true; cleanup(); reject(new Error('Print dialog unavailable')); } };
  const timeout = setTimeout(fail, 20000);
  frame.onerror = fail;
  frame.onload = () => setTimeout(() => {
    if (settled) return;
    try {
      frame.contentWindow.addEventListener('afterprint', cleanup, {once:true});
      frame.contentWindow.focus(); frame.contentWindow.print();
      settled = true; clearTimeout(timeout); resolve(true);
      setTimeout(cleanup, 120000);
    } catch (_) { fail(); }
  }, 500);
  frame.src = url; document.body.appendChild(frame);
});
