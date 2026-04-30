import { useState, useCallback, useRef, useEffect } from "react";
import { createRoot, Root } from "react-dom/client";
import { Excalidraw, exportToBlob } from "@excalidraw/excalidraw";

type Scene = {
  elements: readonly any[];
  appState: Record<string, any>;
  files: Record<string, any>;
};

type SaveResponse = {
  id: number;
  title: string;
  role?: string;
  position?: number | null;
  png_url?: string | null;
};

function csrfToken(): string {
  const meta = document.querySelector('meta[name="csrf-token"]');
  return meta ? meta.getAttribute("content") || "" : "";
}

async function postJSON(url: string, method: string, body: unknown): Promise<Response> {
  return fetch(url, {
    method,
    headers: {
      "Content-Type": "application/json",
      "Accept": "application/json",
      "X-CSRF-Token": csrfToken(),
    },
    body: JSON.stringify(body),
  });
}

function blobToDataUrl(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result as string);
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
}

async function renderPngDataUrl(scene: Scene): Promise<string | null> {
  if (!scene.elements || scene.elements.length === 0) return null;
  try {
    const blob = await exportToBlob({
      elements: scene.elements,
      appState: { ...scene.appState, exportBackground: true },
      files: scene.files,
      mimeType: "image/png",
    } as any);
    if (!blob) return null;
    return await blobToDataUrl(blob);
  } catch (e) {
    console.warn("Drawing PNG export failed:", e);
    return null;
  }
}

function useDebouncedCallback<T extends (...args: any[]) => void>(
  callback: T,
  delayMs: number
): T {
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const cbRef = useRef(callback);
  useEffect(() => {
    cbRef.current = callback;
  }, [callback]);

  return useCallback(
    ((...args: any[]) => {
      if (timeoutRef.current) clearTimeout(timeoutRef.current);
      timeoutRef.current = setTimeout(() => cbRef.current(...args), delayMs);
    }) as T,
    [delayMs]
  );
}

type Props = {
  container: HTMLElement;
  initialId: number | null;
  initialTitle: string;
  initialContent: Scene | null;
  initialRole: string;
  createUrl: string;
  showUrlPattern: string;
};

function ExcalidrawApp({
  container,
  initialId,
  initialTitle,
  initialContent,
  initialRole,
  createUrl,
  showUrlPattern,
}: Props) {
  const [drawingId, setDrawingId] = useState<number | null>(initialId);
  const [title, setTitle] = useState(initialTitle);
  const [saveStatus, setSaveStatus] = useState<"idle" | "saving" | "saved" | "error">("idle");

  const sceneRef = useRef<Scene>({
    elements: initialContent?.elements ?? [],
    appState: { ...(initialContent?.appState ?? {}), theme: "dark" },
    files: initialContent?.files ?? {},
  });
  const titleRef = useRef(title);
  useEffect(() => {
    titleRef.current = title;
  }, [title]);

  const showUrlFor = (id: number) => showUrlPattern.replace(/__ID__|:id/, String(id));

  const save = useCallback(async () => {
    setSaveStatus("saving");
    try {
      const payload = sceneRef.current;
      const currentTitle = titleRef.current || "Untitled";
      const pngDataUrl = await renderPngDataUrl(payload);

      const body: Record<string, any> = {
        drawing: {
          title: currentTitle,
          content: payload,
          role: initialRole,
        },
      };
      if (pngDataUrl) body.drawing.png_data_url = pngDataUrl;

      let res: Response;
      if (drawingId) {
        res = await postJSON(showUrlFor(drawingId), "PATCH", body);
      } else {
        res = await postJSON(createUrl, "POST", body);
      }
      if (!res.ok) throw new Error(`Save failed: ${res.status}`);
      const result: SaveResponse = await res.json();
      if (!drawingId) {
        setDrawingId(result.id);
        // Only update URL bar if we own the page (full-page editor, not modal).
        if (container.dataset.standalone === "true") {
          window.history.replaceState({}, "", showUrlFor(result.id));
        }
      }
      setSaveStatus("saved");
      container.dispatchEvent(
        new CustomEvent("drawing:saved", { detail: result, bubbles: true })
      );
    } catch (e) {
      console.error("Drawing save failed:", e);
      setSaveStatus("error");
    }
  }, [drawingId, createUrl, showUrlPattern, container, initialRole]);

  const debouncedSave = useDebouncedCallback(save, 2000);

  const handleChange = useCallback(
    (elements: readonly any[], appState: any, files: any) => {
      sceneRef.current = { elements, appState, files };
      setSaveStatus((prev) => (prev === "saved" ? "idle" : prev));
      debouncedSave();
    },
    [debouncedSave]
  );

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "s") {
        e.preventDefault();
        save();
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [save]);

  const initialData = {
    elements: initialContent?.elements ?? [],
    appState: {
      ...(initialContent?.appState ?? {}),
      theme: "dark",
      collaborators: new Map(),
    },
    files: initialContent?.files ?? {},
    scrollToContent: true,
  };

  return (
    <div style={{ width: "100%", height: "100%", position: "relative" }}>
      <div className="excalidraw-topbar">
        <input
          type="text"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="Drawing title…"
        />
        <button onClick={save} type="button">Save</button>
        <span className={`save-status ${saveStatus === "error" ? "error" : ""}`}>
          {saveStatus === "saving" && "Saving…"}
          {saveStatus === "saved" && "✓ Saved"}
          {saveStatus === "error" && "⚠ Error"}
          {saveStatus === "idle" && ""}
        </span>
      </div>

      <Excalidraw
        initialData={initialData as any}
        onChange={handleChange as any}
        theme="dark"
      />
    </div>
  );
}

function parseInitialContent(raw: string | undefined): Scene | null {
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === "object") {
      return {
        elements: Array.isArray(parsed.elements) ? parsed.elements : [],
        appState: parsed.appState ?? {},
        files: parsed.files ?? {},
      };
    }
  } catch (e) {
    console.warn("Failed to parse initial drawing content:", e);
  }
  return null;
}

const roots = new WeakMap<Element, Root>();

function mount(container: HTMLElement) {
  if (roots.has(container)) return;

  const initialId = container.dataset.drawingId
    ? parseInt(container.dataset.drawingId, 10)
    : null;
  const initialTitle = container.dataset.drawingTitle || "Untitled";
  const initialContent = parseInitialContent(container.dataset.drawingContent);
  const initialRole = container.dataset.drawingRole || "general";
  const createUrl = container.dataset.createUrl || "";
  const showUrlPattern = container.dataset.showUrlPattern || "";

  const root = createRoot(container);
  roots.set(container, root);
  root.render(
    <ExcalidrawApp
      container={container}
      initialId={initialId}
      initialTitle={initialTitle}
      initialContent={initialContent}
      initialRole={initialRole}
      createUrl={createUrl}
      showUrlPattern={showUrlPattern}
    />
  );
}

function unmount(container: HTMLElement) {
  const root = roots.get(container);
  if (root) {
    root.unmount();
    roots.delete(container);
  }
}

const w = window as any;
w.IdeaApp = w.IdeaApp || {};
w.IdeaApp.mountExcalidraw = mount;
w.IdeaApp.unmountExcalidraw = unmount;

// Notify any Stimulus controllers that were waiting for the bundle.
document.dispatchEvent(new CustomEvent("excalidraw:ready"));
