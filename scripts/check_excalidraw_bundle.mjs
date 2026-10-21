import fs from "node:fs";
import path from "node:path";

const bundleDir = path.join(process.cwd(), "app/assets/builds/excalidraw_app");
const filesToScan = ["index.js", "index.js.map", "index.css", "index.css.map"];

const forbiddenPatterns = [
  ["Google API key", /AIza[0-9A-Za-z_-]{35}/],
  ["esm.sh CDN font fallback", /esm\.sh/],
  ["Excalidraw Firebase project", /excalidraw-room-persistence/],
  ["Firebase host", /firebase(?:app|io)?\.com/],
  ["Excalidraw collaboration backend", /oss-collab\.excalidraw\.com/],
  ["Excalidraw AI backend", /oss-ai\.excalidraw\.com/],
  ["Excalidraw JSON backend", /json(?:-dev)?\.excalidraw\.com/],
  ["Excalidraw app handoff", /app\.excalidraw\.com/],
  ["Excalidraw library backend", /us-central1-excalidraw-room-persistence\.cloudfunctions\.net/],
];

let failed = false;

// The font asset path baked into the bundle must be the versioned dir that the build produced.
const version = JSON.parse(
  fs.readFileSync(path.join(process.cwd(), "node_modules/@excalidraw/excalidraw/package.json"), "utf8")
).version;
const assetPath = `/excalidraw-assets/${version}/`;
const bundlePath = path.join(bundleDir, "index.js");
if (fs.existsSync(bundlePath) && !fs.readFileSync(bundlePath, "utf8").includes(assetPath)) {
  failed = true;
  console.error(`index.js does not reference ${assetPath}; rebuild.`);
}
if (!fs.existsSync(path.join(process.cwd(), "public", assetPath, "fonts"))) {
  failed = true;
  console.error(`public${assetPath}fonts is missing; rebuild.`);
}

for (const fileName of filesToScan) {
  const filePath = path.join(bundleDir, fileName);
  if (!fs.existsSync(filePath)) continue;

  const content = fs.readFileSync(filePath, "utf8");
  for (const [label, pattern] of forbiddenPatterns) {
    const match = content.match(pattern);
    if (!match) continue;

    failed = true;
    const index = match.index ?? 0;
    const line = content.slice(0, index).split("\n").length;
    console.error(`${fileName}:${line}: forbidden Excalidraw connector leaked: ${label}`);
  }
}

if (failed) {
  console.error("\nExcalidraw bundle must stay local-only. Rebuild with the sanitized Excalidraw env plugin and verify again.");
  process.exit(1);
}

console.log("Excalidraw bundle check passed: no Google API keys or upstream connector endpoints found.");
