import * as esbuild from "esbuild";

const watch = process.argv.includes("--watch");
const nodeEnv =
  process.env.NODE_ENV || (watch ? "development" : "production");

const common = {
  bundle: true,
  sourcemap: true,
  format: "esm",
  loader: {
    ".tsx": "tsx",
    ".ts": "ts",
    ".jsx": "jsx",
    ".js": "jsx",
  },
  jsx: "automatic",
  define: {
    "process.env.NODE_ENV": JSON.stringify(nodeEnv),
    "process.env.IS_PREACT": JSON.stringify("false"),
  },
  logLevel: "info",
};

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
