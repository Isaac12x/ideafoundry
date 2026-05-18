import fs from "node:fs";
import path from "node:path";

const bundleDir = path.join(process.cwd(), "app/assets/builds/excalidraw_app");
const filesToScan = ["index.js", "index.js.map", "index.css", "index.css.map"];

const forbiddenPatterns = [
  ["Google API key", /AIza[0-9A-Za-z_-]{35}/],
  ["Excalidraw Firebase project", /excalidraw-room-persistence/],
  ["Firebase host", /firebase(?:app|io)?\.com/],
  ["Excalidraw collaboration backend", /oss-collab\.excalidraw\.com/],
  ["Excalidraw AI backend", /oss-ai\.excalidraw\.com/],
  ["Excalidraw JSON backend", /json(?:-dev)?\.excalidraw\.com/],
  ["Excalidraw app handoff", /app\.excalidraw\.com/],
  ["Excalidraw library backend", /us-central1-excalidraw-room-persistence\.cloudfunctions\.net/],
];

let failed = false;

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
