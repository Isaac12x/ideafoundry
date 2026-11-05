import { useState, useCallback, useRef, useEffect } from "react";
import { createRoot, Root } from "react-dom/client";
import { Excalidraw, exportToBlob, CaptureUpdateAction } from "@excalidraw/excalidraw";
import type { ExcalidrawImperativeAPI } from "@excalidraw/excalidraw/types";
import "@excalidraw/excalidraw/index.css";

// Fonts live in public/excalidraw-assets/<version> (esbuild.config.mjs); never let Excalidraw reach a CDN.
declare const __EXCALIDRAW_ASSET_PATH__: string;
(window as any).EXCALIDRAW_ASSET_PATH = __EXCALIDRAW_ASSET_PATH__;

const LOCAL_ONLY_UI_OPTIONS = {
  canvasActions: {
    export: false,
    loadScene: false,
    saveToActiveFile: false,
  },
} as const;

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

type Session = {
  nonce: number;
  id: number | null;
  title: string;
  content: Scene | null;
  role: string;
  createUrl: string;
  showUrlPattern: string;
};

const SAVE_DELAY_MS = 2000;

// Cheap change signature: any edit bumps an element version or the element count.
function sceneSignature(elements: readonly any[]): string {
  let sum = 0;
  for (const el of elements) sum += el.version ?? 0;
  return `${elements.length}:${sum}`;
}

function sceneFrom(content: Scene | null): Scene {
  return {
    elements: content?.elements ?? [],
    appState: { ...(content?.appState ?? {}), theme: "dark" },
    files: content?.files ?? {},
  };
}

// The container lives in a hidden modal between openings; ignore the editor then.
function isVisible(el: HTMLElement): boolean {
  return el.getClientRects().length > 0;
}

type Props = {
  container: HTMLElement;
  session: Session;
  register: (flush: () => Promise<void>) => void;
};

function ExcalidrawApp({ container, session, register }: Props) {
  const [title, setTitle] = useState(session.title);
  const [saveStatus, setSaveStatus] = useState<"idle" | "saving" | "saved" | "error">("idle");

  const apiRef = useRef<ExcalidrawImperativeAPI | null>(null);
  const sessionRef = useRef(session);
  const idRef = useRef<number | null>(session.id);
  const sceneRef = useRef<Scene>(sceneFrom(session.content));
  const savedSigRef = useRef(sceneSignature(sceneRef.current.elements));
  const savedTitleRef = useRef(session.title || "Untitled");
  const titleRef = useRef(title);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const chainRef = useRef<Promise<void>>(Promise.resolve());
  const appliedNonce = useRef(session.nonce);

  useEffect(() => {
    titleRef.current = title;
  }, [title]);

  const isDirty = () =>
    sceneSignature(sceneRef.current.elements) !== savedSigRef.current ||
    (titleRef.current || "Untitled") !== savedTitleRef.current;

  const showUrlFor = (id: number) => sessionRef.current.showUrlPattern.replace(/__ID__|:id/, String(id));

  const doSave = async () => {
    const owner = sessionRef.current;
    const scene = sceneRef.current;
    const sig = sceneSignature(scene.elements);
    const currentTitle = titleRef.current || "Untitled";
    setSaveStatus("saving");
    try {
      const pngDataUrl = await renderPngDataUrl(scene);
      const { collaborators: _omit, ...appState } = scene.appState;
      const body: Record<string, any> = {
        drawing: {
          title: currentTitle,
          content: { elements: scene.elements, appState, files: scene.files },
          role: owner.role,
        },
      };
      if (pngDataUrl) body.drawing.png_data_url = pngDataUrl;

      const id = idRef.current;
      const res = id
        ? await postJSON(showUrlFor(id), "PATCH", body)
        : await postJSON(owner.createUrl, "POST", body);
      if (!res.ok) throw new Error(`Save failed: ${res.status}`);
      const result: SaveResponse = await res.json();

      // The editor may have moved on to another drawing while this save was in flight.
      if (sessionRef.current === owner) {
        if (!id) {
          idRef.current = result.id;
          if (container.dataset.standalone === "true") {
            window.history.replaceState({}, "", showUrlFor(result.id));
          }
        }
        savedSigRef.current = sig;
        savedTitleRef.current = currentTitle;
        setSaveStatus("saved");
      }
      container.dispatchEvent(new CustomEvent("drawing:saved", { detail: result, bubbles: true }));
    } catch (e) {
      console.error("Drawing save failed:", e);
      if (sessionRef.current === owner) setSaveStatus("error");
    }
  };

  // Saves run one at a time so a slow first POST can't be followed by a second create.
  const save = useCallback((force = false): Promise<void> => {
    if (timerRef.current) {
      clearTimeout(timerRef.current);
      timerRef.current = null;
    }
    chainRef.current = chainRef.current.then(() => (force || isDirty() ? doSave() : undefined));
    return chainRef.current;
  }, []);

  useEffect(() => {
    register(() => save(false));
  }, [register, save]);

  // Re-opening with another drawing swaps the scene in place; the editor stays mounted.
  useEffect(() => {
    if (appliedNonce.current === session.nonce) return;
    appliedNonce.current = session.nonce;
    sessionRef.current = session;
    idRef.current = session.id;
    sceneRef.current = sceneFrom(session.content);
    savedSigRef.current = sceneSignature(sceneRef.current.elements);
    savedTitleRef.current = session.title || "Untitled";
    titleRef.current = session.title;
    setTitle(session.title);
    setSaveStatus("idle");

    const api = apiRef.current;
    if (!api) return;
    const scene = sceneRef.current;
    api.resetScene();
    api.addFiles(Object.values(scene.files));
    api.updateScene({
      elements: scene.elements as any,
      appState: { ...scene.appState, collaborators: new Map() } as any,
      captureUpdate: CaptureUpdateAction.NEVER,
    });
    api.history.clear();
    const live = scene.elements.filter((el) => !el.isDeleted);
    if (live.length) requestAnimationFrame(() => api.setViewport({ target: live as any, fit: "scale-down" }));
  }, [session]);

  // Tell the host the editor shows the requested drawing (open-latency measurement).
  useEffect(() => {
    const raf = requestAnimationFrame(() =>
      container.dispatchEvent(new CustomEvent("drawing:ready", { bubbles: true }))
    );
    return () => cancelAnimationFrame(raf);
  }, [container, session.nonce]);

  // Flush on unmount (standalone page navigations) so a pending edit is not lost.
  useEffect(() => () => void save(false), [save]);

  const handleChange = useCallback(
    (elements: readonly any[], appState: any, files: any) => {
      if (!isVisible(container)) return;
      sceneRef.current = { elements, appState, files };
      if (!isDirty()) return;
      setSaveStatus((prev) => (prev === "saved" ? "idle" : prev));
      if (timerRef.current) clearTimeout(timerRef.current);
      timerRef.current = setTimeout(() => void save(false), SAVE_DELAY_MS);
    },
    [container, save]
  );

  // Title edits autosave too (the thumbnail label follows).
  useEffect(() => {
    if (!isVisible(container) || !isDirty()) return;
    if (timerRef.current) clearTimeout(timerRef.current);
    timerRef.current = setTimeout(() => void save(false), SAVE_DELAY_MS);
  }, [title, container, save]);

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "s" && isVisible(container)) {
        e.preventDefault();
        void save(true);
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [container, save]);

  // Only the first mount reads initialData; later sessions go through updateScene above.
  const initialData = useRef({
    elements: session.content?.elements ?? [],
    appState: {
      ...(session.content?.appState ?? {}),
      theme: "dark",
      collaborators: new Map(),
    },
    files: session.content?.files ?? {},
    scrollToContent: true,
  }).current;

  return (
    <div style={{ width: "100%", height: "100%", position: "relative" }}>
      <div className="excalidraw-topbar">
        <input
          type="text"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="Drawing title…"
        />
        <button onClick={() => void save(true)} type="button">Save</button>
        <span className={`save-status ${saveStatus === "error" ? "error" : ""}`}>
          {saveStatus === "saving" && "Saving…"}
          {saveStatus === "saved" && "✓ Saved"}
          {saveStatus === "error" && "⚠ Error"}
          {saveStatus === "idle" && ""}
        </span>
      </div>

      <Excalidraw
        initialData={initialData as any}
        onExcalidrawAPI={(api) => {
          apiRef.current = api;
        }}
        onChange={handleChange as any}
        theme="dark"
        isCollaborating={false}
        aiEnabled={false}
        validateEmbeddable={false}
        UIOptions={LOCAL_ONLY_UI_OPTIONS as any}
        renderTopRightUI={() => null}
        onLinkOpen={(_, event) => event.preventDefault()}
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

type Host = {
  root: Root;
  setSession: (s: Session) => void;
  flush: () => Promise<void>;
  nonce: number;
};
const hosts = new WeakMap<Element, Host>();

function readSession(container: HTMLElement, nonce: number): Session {
  return {
    nonce,
    id: container.dataset.drawingId ? parseInt(container.dataset.drawingId, 10) : null,
    title: container.dataset.drawingTitle || "Untitled",
    content: parseInitialContent(container.dataset.drawingContent),
    role: container.dataset.drawingRole || "general",
    createUrl: container.dataset.createUrl || "",
    showUrlPattern: container.dataset.showUrlPattern || "",
  };
}

function HostRoot({ container, initial, host }: { container: HTMLElement; initial: Session; host: { current: Host | null } }) {
  const [session, setSession] = useState(initial);
  const flushRef = useRef<() => Promise<void>>(async () => {});
  useEffect(() => {
    if (host.current) host.current.setSession = setSession;
  }, [host]);
  const register = useCallback((fn: () => Promise<void>) => {
    flushRef.current = fn;
    if (host.current) host.current.flush = fn;
  }, [host]);
  return <ExcalidrawApp container={container} session={session} register={register} />;
}

// First call creates the root; later calls (re-opening the modal) only swap the scene.
function mount(container: HTMLElement) {
  const existing = hosts.get(container);
  if (existing) {
    const next = readSession(container, ++existing.nonce);
    // Finish any pending save of the previous drawing first.
    existing.flush().finally(() => existing.setSession(next));
    return;
  }

  const root = createRoot(container);
  const ref: { current: Host | null } = { current: null };
  const host: Host = { root, setSession: () => {}, flush: async () => {}, nonce: 0 };
  ref.current = host;
  hosts.set(container, host);
  root.render(<HostRoot container={container} initial={readSession(container, 0)} host={ref} />);
}

function unmount(container: HTMLElement) {
  const host = hosts.get(container);
  if (host) {
    host.root.unmount();
    hosts.delete(container);
  }
}

function flush(container: HTMLElement): Promise<void> {
  return hosts.get(container)?.flush() ?? Promise.resolve();
}

const w = window as any;
w.IdeaApp = w.IdeaApp || {};
w.IdeaApp.mountExcalidraw = mount;
w.IdeaApp.unmountExcalidraw = unmount;
w.IdeaApp.flushExcalidraw = flush;

// Notify any Stimulus controllers that were waiting for the bundle.
document.dispatchEvent(new CustomEvent("excalidraw:ready"));
