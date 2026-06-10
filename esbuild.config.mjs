import * as esbuild from "esbuild";
import fs from "node:fs";
import path from "node:path";

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

function excalidrawLocalOnlyPlugin() {
  const connectorEnvChunks = findExcalidrawConnectorEnvChunks();

  return {
    name: "excalidraw-local-only",
    setup(build) {
      build.onResolve({ filter: /^\.\.??\/chunk-.*\.js$/ }, (args) => {
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
    outdir: "app/assets/builds/excalidraw_app",
    minify: !watch,
    splitting: false,
    plugins: [excalidrawLocalOnlyPlugin()],
  },
  {
    ...common,
    entryPoints: ["app/javascript/typing_unlock_animation/index.js"],
    outdir: "app/assets/builds/typing_unlock_animation",
    minify: !watch,
    splitting: false,
  },
];

if (watch) {
  for (const cfg of builds) {
    const ctx = await esbuild.context(cfg);
    await ctx.watch();
  }
  console.log("esbuild: watching…");
} else {
  await Promise.all(builds.map((cfg) => esbuild.build(cfg)));
}
