import components from "virtual:components";
import { init } from "./runtime/hydration";
import { hydrate, type Component, unmount } from "svelte";

init<Component<any, Record<string, any>>, Record<string, any>>({
  resolve: async (name) => {
    const importFn = components[name];
    if (!importFn) throw new Error(`Component not found: ${name}`);
    const module = await importFn();
    return module.default;
  },
  hydrate: (Component, { target, props }) => {
    return hydrate(Component, { target, props });
  },
  destroy: (component) => {
    void unmount(component);
  },
});

import "phoenix_html";

// Handle flash close
document.querySelectorAll("[role=alert][data-flash]").forEach((el) => {
  el.addEventListener("click", () => {
    el.setAttribute("hidden", "");
  });
});

declare global {
  interface Window {
    Swup: any;
    // SwupFadeTheme: any;
    SwupPreloadPlugin: any;
    SwupFormsPlugin: any;
  }
}

const swup = new window.Swup({
  plugins: [
    // new window.SwupFadeTheme(),
    new window.SwupPreloadPlugin(),
    new window.SwupFormsPlugin(),
  ],
});

const normalizePath = (url: string) => {
  try {
    return new URL(url, window.location.origin).pathname;
  } catch {
    return null;
  }
};

swup.hooks.on("form:submit", (_visit: unknown, { el }: { el: Element }) => {
  if (!(el instanceof HTMLFormElement)) return;

  const submittedPath = normalizePath(el.action || window.location.href);
  const currentPath = normalizePath(window.location.href);

  swup.cache.prune((url: string) => {
    const cachedPath = normalizePath(url);
    if (!cachedPath) return false;
    return cachedPath === submittedPath || cachedPath === currentPath;
  });
});
