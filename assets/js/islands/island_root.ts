export interface ClientConfig<T> {
  resolve: (path: string, resolver?: (path: string, ext: string) => Promise<T>) => Promise<T>
  hydrate: (component: T, options: { target: HTMLElement; props: any }) => void
}

const resetInputs = ({ element }: { element: HTMLElement }) => {
  return new Promise<void>((resolve) => {
    if (
      window.performance?.navigation?.type ===
        performance.navigation.TYPE_RELOAD ||
      window.performance?.navigation?.type ===
        performance.navigation.TYPE_BACK_FORWARD
    ) {
      // reset various inputs
      element.querySelectorAll<HTMLInputElement>("input").forEach((el) => {
        switch (el.type) {
          case "checkbox":
          case "radio":
            el.checked = el.defaultChecked;
            break;
          case "file":
            el.value = "";
            break;
          default:
            // text, number, date, color, range, etc.
            el.value = el.defaultValue;
        }
      });

      // reset textareas
      element
        .querySelectorAll<HTMLTextAreaElement>("textarea")
        .forEach((el) => {
          el.value = el.defaultValue;
        });

      // reset selects (single and multiple)
      element
        .querySelectorAll<HTMLSelectElement>("select")
        .forEach((select) => {
          if (select.multiple) {
            Array.from(select.options).forEach((opt) => {
              opt.selected = opt.defaultSelected;
            });
          } else {
            const defaultIndex = Array.from(select.options).findIndex(
              (opt) => opt.defaultSelected,
            );
            select.selectedIndex = defaultIndex > -1 ? defaultIndex : -1;
          }
        });
    }
    resolve();
  });
};

const visible = ({ element }: { element: HTMLElement }) => {
  return new Promise((resolve) => {
    const observer = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          observer.disconnect();
          resolve(true);
        }
      }
    });
    observer.observe(element);
  });
};

const media = ({
  query,
  onMatch,
  onUnmatch,
}: {
  query: string;
  onMatch?: () => void;
  onUnmatch?: () => void;
}) => {
  const handleChange = (event: MediaQueryListEvent) => {
    if (event.matches) {
      onMatch?.();
    } else {
      onUnmatch?.();
    }
  };
  const mediaQuery = window.matchMedia(query);
  if (mediaQuery.matches) {
    onMatch?.();
  } else {
    onUnmatch?.();
  }
  mediaQuery.addEventListener("change", handleChange);
  return () => {
    mediaQuery.removeEventListener("change", handleChange);
  };
};

export const safeJsonParse = (json: string) => {
  try {
    return JSON.parse(json);
  } catch (error) {
    console.warn("Invalid JSON in data-props attribute:", error);
    return {};
  }
};

export function init<T>({ resolve, hydrate }: ClientConfig<T>) {
  class IslandRoot extends HTMLElement {
    private cleanupMediaListener?: any

    async connectedCallback() {
      // Firefox caches client side inputs so we make sure to reset them
      // Chromium based browsers behave "correctly" (but not according to w3 spec)
      await resetInputs({ element: this })

      if (this.hasAttribute('data-lazy')) {
        await visible({ element: this })
      }

      if (this.hasAttribute('data-media')) {
        const query = this.getAttribute('data-media') ?? ''
        this.cleanupMediaListener = media({
          query,
          onMatch: async () => await this.hydrate(),
          onUnmatch: () => (this.innerHTML = ''),
        })
      } else {
        await this.hydrate()
      }
    }

    disconnectedCallback() {
      this.cleanupMediaListener?.()
    }

    async hydrate() {
      const src = this.getAttribute('data-module') ?? ''
      const propsData = this.getAttribute('data-props')
      const props = propsData ? safeJsonParse(propsData) : {}

      const Component = await resolve(src)
      hydrate(Component, { target: this, props })
    }
  }
  customElements.define('island-root', IslandRoot)
}
