// Separate esbuild entry point: bundles the pdf.js worker so it is emitted to
// priv/static/assets/js/pdf.worker.js and served at /assets/js/pdf.worker.js.
// app.js points GlobalWorkerOptions.workerSrc at that URL. The worker is only
// fetched by the browser when a PDF is actually previewed.
import "../vendor/pdfjs/pdf.worker.min.mjs"
