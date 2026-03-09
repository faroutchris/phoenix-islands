<script lang="ts">
  import { onMount } from "svelte";

  type Theme = "system" | "light" | "dark";

  function normalizeTheme(value: string | null): Theme {
    if (value === "light" || value === "dark") return value;
    return "system";
  }

  function applyTheme(theme: Theme) {
    if (theme === "system") {
      localStorage.removeItem("phx:theme");
      document.documentElement.removeAttribute("data-theme");
      return;
    }

    localStorage.setItem("phx:theme", theme);
    document.documentElement.setAttribute("data-theme", theme);
  }

  function setTheme(theme: Theme) {
    applyTheme(theme);
  }

  onMount(() => {
    const onStorage = (event: StorageEvent) => {
      if (event.key !== "phx:theme") return;
      applyTheme(normalizeTheme(event.newValue));
    };

    window.addEventListener("storage", onStorage);

    return () => {
      window.removeEventListener("storage", onStorage);
    };
  });
</script>

<div
  class="card relative flex flex-row items-center rounded-full border-2 border-base-300 bg-base-300"
>
  <div
    class="absolute left-0 h-full w-1/3 rounded-full border-1 border-base-200 bg-base-100 brightness-200 transition-[left] [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3"
  ></div>

  <button
    type="button"
    class="relative z-10 flex w-1/3 cursor-pointer justify-center p-2 text-[10px] font-semibold uppercase tracking-wide opacity-75 transition-opacity hover:opacity-100"
    onclick={() => setTheme("system")}
    aria-label="Use system theme"
    title="System theme"
  >
    Sys
  </button>

  <button
    type="button"
    class="relative z-10 flex w-1/3 cursor-pointer justify-center p-2 text-[10px] font-semibold uppercase tracking-wide opacity-75 transition-opacity hover:opacity-100"
    onclick={() => setTheme("light")}
    aria-label="Use light theme"
    title="Light theme"
  >
    Light
  </button>

  <button
    type="button"
    class="relative z-10 flex w-1/3 cursor-pointer justify-center p-2 text-[10px] font-semibold uppercase tracking-wide opacity-75 transition-opacity hover:opacity-100"
    onclick={() => setTheme("dark")}
    aria-label="Use dark theme"
    title="Dark theme"
  >
    Dark
  </button>
</div>
