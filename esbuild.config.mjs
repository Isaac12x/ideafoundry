import * as esbuild from "esbuild";
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";

const watch = process.argv.includes("--watch");
const nodeEnv =
  process.env.NODE_ENV || (watch ? "development" : "production");

const common = {
  bundle: true,
  sourcemap: true,
  format: "esm",
  conditions: [nodeEnv === "production" ? "production" : "development"],
  loader: {
    ".tsx": "tsx",
    ".ts": "ts",
    ".jsx": "jsx",
    ".js": "jsx",
    ".woff2": "file",
  },
  jsx: "automatic",
  define: {
    "process.env.NODE_ENV": JSON.stringify(nodeEnv),
    "process.env.IS_PREACT": JSON.stringify("false"),
  },
  logLevel: "info",
};

const sanitizedExcalidrawEnv = `
const sanitizedExcalidrawEnv = {
  VITE_APP_BACKEND_V2_GET_URL: "",
  VITE_APP_BACKEND_V2_POST_URL: "",
  VITE_APP_LIBRARY_URL: "",
  VITE_APP_LIBRARY_BACKEND: "",
  VITE_APP_PLUS_LP: "",
  VITE_APP_PLUS_APP: "",
  VITE_APP_AI_BACKEND: "",
  VITE_APP_WS_SERVER_URL: "",
  VITE_APP_FIREBASE_CONFIG: "{}",
  VITE_APP_ENABLE_TRACKING: "false",
  VITE_APP_PLUS_EXPORT_PUBLIC_KEY: "",
  VITE_APP_DEBUG_ENABLE_TEXT_CONTAINER_BOUNDING_BOX: "false",
  VITE_APP_COLLAPSE_OVERLAY: "false",
  VITE_APP_ENABLE_ESLINT: "false",
  VITE_APP_DEV_DISABLE_LIVE_RELOAD: "",
  VITE_APP_PORT: "",
  VITE_APP_ENABLE_PWA: "false",
  FAST_REFRESH: "false",
  PKG_NAME: "@excalidraw/excalidraw",
  PKG_VERSION: "local-only",
  PROD: true,
  DEV: false,
};
export { sanitizedExcalidrawEnv as a, sanitizedExcalidrawEnv as define_import_meta_env_default };
`;

function findExcalidrawConnectorEnvChunks() {
  const packageRoot = path.join(
    process.cwd(),
    "node_modules",
    "@excalidraw",
    "excalidraw",
    "dist"
  );
  const chunks = new Set();

  for (const buildName of ["prod", "dev"]) {
    const buildDir = path.join(packageRoot, buildName);
    if (!fs.existsSync(buildDir)) continue;

    for (const fileName of fs.readdirSync(buildDir)) {
      if (!/^chunk-.*\.js$/.test(fileName)) continue;
      const filePath = path.join(buildDir, fileName);
      const content = fs.readFileSync(filePath, "utf8");
      if (content.includes("VITE_APP_FIREBASE_CONFIG")) {
        chunks.add(fileName);
      }
    }
  }

  return chunks;
}

// Fonts are served from public/ (not the digesting asset pipeline): Excalidraw resolves
// "fonts/<Family>/<file>" against window.EXCALIDRAW_ASSET_PATH, and its own fallback is a CDN.
// Versioned so the long public cache busts when @excalidraw/excalidraw is upgraded.
const EXCALIDRAW_VERSION = JSON.parse(
  fs.readFileSync(path.join("node_modules", "@excalidraw", "excalidraw", "package.json"), "utf8")
).version;
const EXCALIDRAW_PUBLIC_ROOT = "public/excalidraw-assets";
const EXCALIDRAW_PUBLIC_DIR = `${EXCALIDRAW_PUBLIC_ROOT}/${EXCALIDRAW_VERSION}`;
const EXCALIDRAW_PUBLIC_URL = `/excalidraw-assets/${EXCALIDRAW_VERSION}`;

// Everything for the editor is emitted straight into the versioned public dir (code-split, so the
// entry only pulls the chunks it needs), and wiped per build. Chunk and entry names carry content
// hashes; manifest.json maps the entry for the Rails helper.
function prepareExcalidrawPublicDir() {
  fs.rmSync(EXCALIDRAW_PUBLIC_ROOT, { recursive: true, force: true }); // drops older version dirs too
  fs.mkdirSync(EXCALIDRAW_PUBLIC_DIR, { recursive: true });
  fs.cpSync(
    path.join("node_modules", "@excalidraw", "excalidraw", "dist", "prod", "fonts"),
    path.join(EXCALIDRAW_PUBLIC_DIR, "fonts"),
    { recursive: true }
  );
  // The old digested output is no longer used.
  fs.rmSync("app/assets/builds/excalidraw_app", { recursive: true, force: true });
}

function writeExcalidrawManifest(metafile) {
  const outputs = metafile.outputs;
  const entry = Object.keys(outputs).find((o) => outputs[o].entryPoint?.endsWith("excalidraw_app/index.tsx"));
  // Entry plus every chunk it imports statically: what a click needs, so what to preload.
  const preload = [];
  const walk = (out) => {
    if (preload.includes(out) || !outputs[out]) return;
    preload.push(out);
    for (const imp of outputs[out].imports) if (imp.kind === "import-statement") walk(imp.path);
  };
  walk(entry);
  const base = (o) => path.basename(o);
  fs.writeFileSync(
    path.join(EXCALIDRAW_PUBLIC_DIR, "manifest.json"),
    JSON.stringify({ js: base(entry), css: base(outputs[entry].cssBundle), preload: preload.map(base) }, null, 2)
  );
}

// Precompressed siblings: ActionDispatch::Static serves .br/.gz when the client accepts them.
function precompressExcalidrawAssets() {
  for (const name of fs.readdirSync(EXCALIDRAW_PUBLIC_DIR)) {
    if (!/\.(js|css)$/.test(name)) continue;
    const file = path.join(EXCALIDRAW_PUBLIC_DIR, name);
    const data = fs.readFileSync(file);
    fs.writeFileSync(`${file}.br`, zlib.brotliCompressSync(data, { params: { [zlib.constants.BROTLI_PARAM_QUALITY]: 9, [zlib.constants.BROTLI_PARAM_SIZE_HINT]: data.length } }));
    fs.writeFileSync(`${file}.gz`, zlib.gzipSync(data, { level: 9 }));
  }
}

function excalidrawLocalOnlyPlugin() {
  const connectorEnvChunks = findExcalidrawConnectorEnvChunks();

  return {
    name: "excalidraw-local-only",
    setup(build) {
      // Point Excalidraw's built-in CDN font fallback (esm.sh) at our own origin (it sits inside a template literal): local-only, no remote.
      build.onLoad({ filter: /node_modules\/@excalidraw\/excalidraw\/dist\/.*\.js$/ }, (args) => {
        const source = fs.readFileSync(args.path, "utf8");
        if (!source.includes("https://esm.sh/")) return undefined;
        return { contents: source.replaceAll("https://esm.sh/", "${window.location.origin}" + `${EXCALIDRAW_PUBLIC_URL}/-/`), loader: "js" };
      });
      build.onEnd((result) => {
        if (!result.metafile) return;
        writeExcalidrawManifest(result.metafile);
        if (!watch) precompressExcalidrawAssets();
      });

      build.onResolve({ filter: /^(?:\.{1,2}\/)+chunk-.*\.js$/ }, (args) => {
        if (
          args.importer.includes("node_modules/@excalidraw/excalidraw/dist/") &&
          connectorEnvChunks.has(path.basename(args.path))
        ) {
          return { path: args.path, namespace: "excalidraw-local-only-env" };
        }
      });

      build.onLoad({ filter: /.*/, namespace: "excalidraw-local-only-env" }, () => ({
        contents: sanitizedExcalidrawEnv,
        loader: "js",
      }));
    },
  };
}

const builds = [
  {
    ...common,
    entryPoints: ["app/javascript/graph/index.js"],
    outdir: "app/assets/builds/graph",
    minify: !watch,
    splitting: false,
  },
  {
    ...common,
    entryPoints: ["app/javascript/excalidraw_app/index.tsx"],
    outdir: EXCALIDRAW_PUBLIC_DIR,
    entryNames: "index-[hash]",
    chunkNames: "chunk-[hash]",
    publicPath: EXCALIDRAW_PUBLIC_URL,
    metafile: true,
    // Split: mermaid, locales and other lazy imports become chunks fetched only when used. Served from
    // public/ (no digest rewriting), so relative chunk imports resolve.
    splitting: true,
    // No map: it is huge and publicPath would point its URL at a 404.
    sourcemap: watch ? "inline" : false,
    define: { ...common.define, __EXCALIDRAW_ASSET_PATH__: JSON.stringify(`${EXCALIDRAW_PUBLIC_URL}/`) },
    minify: !watch,
    plugins: [excalidrawLocalOnlyPlugin()],
  },
  {
    // Lazy-loaded by kb_diagram_controller. No splitting: Sprockets fingerprints
    // filenames, so relative chunk imports would 404; mermaid's lazy diagram
    // modules are inlined into this one file instead.
    ...common,
    entryPoints: ["app/javascript/mermaid_app/index.js"],
    outdir: "app/assets/builds/mermaid_app",
    minify: !watch,
    splitting: false,
  },
  {
    ...common,
    entryPoints: ["app/javascript/typing_unlock_animation/index.js"],
    outdir: "app/assets/builds/typing_unlock_animation",
    minify: !watch,
    splitting: false,
  },
  {
    // Lazy viewers: imported on demand by kb_model / kb_book controllers (three.js + occt, epub.js).
    ...common,
    entryPoints: ["app/javascript/kb_viewers/model.js", "app/javascript/kb_viewers/book.js"],
    outdir: "app/assets/builds/kb_viewers",
    minify: !watch,
    splitting: false,
    external: ["path"], // occt-import-js only requires it on its node code path
  },
];

// occt-import-js fetches its wasm by URL (locateFile), so it ships as a plain asset next to the bundle.
fs.mkdirSync("app/assets/builds/kb_viewers", { recursive: true });
fs.copyFileSync(
  path.join("node_modules", "occt-import-js", "dist", "occt-import-js.wasm"),
  "app/assets/builds/kb_viewers/occt-import-js.wasm"
);

prepareExcalidrawPublicDir();

if (watch) {
  for (const cfg of builds) {
    const ctx = await esbuild.context(cfg);
    await ctx.watch();
  }
  console.log("esbuild: watching…");
} else {
  await Promise.all(builds.map((cfg) => esbuild.build(cfg)));
}
