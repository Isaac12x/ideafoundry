let loadPromise = null;

export function loadExcalidrawAssets(bundleUrl, stylesheetUrl) {
  if (window.IdeaApp?.mountExcalidraw) {
    return Promise.resolve();
  }

  if (!loadPromise) {
    loadPromise = (async () => {
      if (stylesheetUrl && !document.querySelector("[data-excalidraw-stylesheet]")) {
        const link = document.createElement("link");
        link.rel = "stylesheet";
        link.href = stylesheetUrl;
        link.dataset.excalidrawStylesheet = "true";
        document.head.appendChild(link);
      }

      if (!window.IdeaApp?.mountExcalidraw) {
        await import(/* webpackIgnore: true */ bundleUrl);
      }
    })().catch((error) => {
      loadPromise = null;
      throw error;
    });
  }

  return loadPromise;
}
