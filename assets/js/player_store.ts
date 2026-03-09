import { writable } from "svelte/store";

export type PlayerMedia = {
  id: string;
  feedId: string;
  attachments: { url: string; mimeType?: string | null }[];
  title: string;
  feedTitle: string;
  image: string | null;
};

export type PlayerStatus = "idle" | "loading" | "playing" | "paused" | "error";

export type PlayerCommand =
  | { id: number; type: "play"; media: PlayerMedia }
  | { id: number; type: "pause" }
  | { id: number; type: "toggle"; media?: PlayerMedia }
  | { id: number; type: "seek"; time: number }
  | { id: number; type: "setVolume"; volume: number }
  | { id: number; type: "toggleMute" };

export type PlayerState = {
  current: PlayerMedia | null;
  status: PlayerStatus;
  currentTime: number;
  duration: number;
  volume: number;
  muted: boolean;
  error: string | null;
  lastCommand: PlayerCommand | null;
};

const initialState: PlayerState = {
  current: null,
  status: "idle",
  currentTime: 0,
  duration: 0,
  volume: 1,
  muted: false,
  error: null,
  lastCommand: null,
};

function createPlayerStore() {
  const { subscribe, update } = writable<PlayerState>(initialState);

  let commandId = 0;

  function issue(command: Omit<PlayerCommand, "id">) {
    const fullCommand = { ...command, id: ++commandId } as PlayerCommand;

    update((state) => {
      let commandToApply: PlayerCommand = fullCommand;

      if (
        fullCommand.type === "toggle" &&
        fullCommand.media &&
        state.current?.id !== fullCommand.media.id
      ) {
        commandToApply = {
          id: fullCommand.id,
          type: "play",
          media: fullCommand.media,
        };
      }

      if (commandToApply.type === "play") {
        return {
          ...state,
          current: commandToApply.media,
          status: "loading",
          error: null,
          lastCommand: commandToApply,
        };
      }

      return {
        ...state,
        lastCommand: commandToApply,
      };
    });
  }

  return {
    subscribe,

    requestPlay(media: PlayerMedia) {
      issue({ type: "play", media });
    },

    requestPause() {
      issue({ type: "pause" });
    },

    requestToggle(media?: PlayerMedia) {
      issue({ type: "toggle", media });
    },

    requestSeek(time: number) {
      issue({ type: "seek", time });
    },

    requestSetVolume(volume: number) {
      issue({ type: "setVolume", volume });
    },

    requestToggleMute() {
      issue({ type: "toggleMute" });
    },

    setLoading() {
      update((state) => ({
        ...state,
        status: "loading",
        error: null,
      }));
    },

    setPlaying() {
      update((state) => ({
        ...state,
        status: "playing",
        error: null,
      }));
    },

    setPaused() {
      update((state) => ({
        ...state,
        status: "paused",
      }));
    },

    setIdle() {
      update((state) => ({
        ...state,
        status: "idle",
      }));
    },

    setError(error: string) {
      update((state) => ({
        ...state,
        status: "error",
        error,
      }));
    },

    setProgress(currentTime: number, duration: number) {
      update((state) => ({
        ...state,
        currentTime,
        duration,
      }));
    },

    setDuration(duration: number) {
      update((state) => ({
        ...state,
        duration,
      }));
    },

    setVolumeState(volume: number, muted: boolean) {
      update((state) => ({
        ...state,
        volume,
        muted,
      }));
    },
  };
}

export const playerStore = createPlayerStore();

export function formatTime(seconds: number) {
  if (!Number.isFinite(seconds) || seconds < 0) return "0:00";

  const minutes = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);

  return `${minutes}:${secs < 10 ? "0" : ""}${secs}`;
}

const playableExtensions = [
  ".mp3",
  ".m4a",
  ".aac",
  ".ogg",
  ".wav",
  ".flac",
  ".mp4",
  ".m4v",
  ".webm",
];

export function isPlayableAttachment(attachment: {
  url?: string | null;
  mimeType?: string | null;
}) {
  if (!attachment.url) return false;

  const mimeType = attachment.mimeType?.toLowerCase() ?? "";
  if (mimeType.startsWith("audio/") || mimeType.startsWith("video/")) return true;

  const url = attachment.url.toLowerCase();
  return playableExtensions.some((extension) => url.includes(extension));
}
