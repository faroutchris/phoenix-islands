<script lang="ts">
  import { onMount } from "svelte";
  import { fromStore } from "svelte/store";
  import { playerStore, formatTime, isPlayableAttachment } from "../player_store";

  let audio = $state<HTMLAudioElement | null>(null);
  let lastHandledCommandId = -1;
  let loadedMediaId = $state<string | null>(null);

  const player = fromStore(playerStore);

  let seekValue = $state<[number]>([0]);
  let volumeValue = $state<[number]>([1]);
  const currentSources = $derived(
    (player.current.current?.attachments ?? []).filter((attachment) => isPlayableAttachment(attachment)),
  );

  function syncFromAudio() {
    if (!audio) return;

    playerStore.setProgress(audio.currentTime, audio.duration || 0);
    playerStore.setVolumeState(audio.volume, audio.muted);

    seekValue[0] = audio.currentTime;
    volumeValue[0] = audio.muted ? 0 : audio.volume;
  }

  async function loadAndPlay() {
    if (!audio || !player.current.current) return;
    if (currentSources.length === 0) {
      playerStore.setError("No playable media found");
      return;
    }

    playerStore.setLoading();
    loadedMediaId = player.current.current.id;

    try {
      audio.pause();
      audio.currentTime = 0;
      audio.load();
      await audio.play();
      playerStore.setPlaying();
    } catch (err) {
      playerStore.setError(
        err instanceof Error ? err.message : "Playback failed",
      );
    }
  }

  async function handleCommand() {
    const command = player.current.lastCommand;
    if (!audio || !command) return;
    if (command.id === lastHandledCommandId) return;

    lastHandledCommandId = command.id;

    switch (command.type) {
      case "play": {
        await loadAndPlay();
        break;
      }

      case "pause": {
        audio.pause();
        break;
      }

      case "toggle": {
        const requestedMedia = command.media;

        if (requestedMedia && loadedMediaId !== requestedMedia.id) {
          playerStore.requestPlay(requestedMedia);
          return;
        }

        if (audio.paused) {
          try {
            await audio.play();
            playerStore.setPlaying();
          } catch (err) {
            playerStore.setError(
              err instanceof Error ? err.message : "Playback failed",
            );
          }
        } else {
          audio.pause();
        }
        break;
      }

      case "seek": {
        audio.currentTime = command.time;
        syncFromAudio();
        break;
      }

      case "setVolume": {
        audio.volume = command.volume;
        audio.muted = command.volume === 0;
        syncFromAudio();
        break;
      }

      case "toggleMute": {
        audio.muted = !audio.muted;
        syncFromAudio();
        break;
      }
    }
  }

  function onLoadedMetadata() {
    if (!audio) return;
    playerStore.setDuration(audio.duration || 0);
    syncFromAudio();
  }

  function onLoadStart() {
    if (player.current.status !== "playing") {
      playerStore.setLoading();
    }
  }

  function onPlay() {
    playerStore.setPlaying();
  }

  function onPause() {
    playerStore.setPaused();
  }

  function onTimeUpdate() {
    syncFromAudio();
  }

  function onVolumeChange() {
    syncFromAudio();
  }

  function onEnded() {
    playerStore.setPaused();
    if (audio) {
      audio.currentTime = 0;
      syncFromAudio();
    }
  }

  function onError() {
    const media = player.current.current;
    playerStore.setError(
      media ? `Audio failed to load for ${media.title}` : "Audio failed to load",
    );
  }

  function onSeekInput(value: number[]) {
    const time = value[0] ?? 0;
    playerStore.requestSeek(time);
  }

  function onVolumeInput(value: number[]) {
    const volume = value[0] ?? 0;
    playerStore.requestSetVolume(volume);
  }

  $effect(() => {
    handleCommand();
  });

  onMount(() => {
    return () => {
      audio?.pause();
    };
  });
</script>

{#if player.current.current}
  <audio
    bind:this={audio}
    onloadedmetadata={onLoadedMetadata}
    onloadstart={onLoadStart}
    onplay={onPlay}
    onpause={onPause}
    ontimeupdate={onTimeUpdate}
    onvolumechange={onVolumeChange}
    onended={onEnded}
    onerror={onError}
  >
    {#each currentSources as attachment}
      <source src={attachment.url} type={attachment.mimeType} />
    {/each}
  </audio>

  <div class="player">
    <div>
      <div>{player.current.current.title}</div>
      <div>{player.current.current.feedTitle}</div>
      {#if player.current.error}
        <div>{player.current.error}</div>
      {/if}
    </div>

    <button
      type="button"
      onclick={() =>
        player.current.status === "playing"
          ? playerStore.requestPause()
          : playerStore.requestToggle()}
    >
      {#if player.current.status === "playing"}
        Pause
      {:else}
        Play
      {/if}
    </button>

    <div>
      <input
        type="range"
        min="0"
        max={player.current.duration || 0}
        step="0.1"
        value={seekValue[0]}
        oninput={(e) =>
          onSeekInput([Number((e.currentTarget as HTMLInputElement).value)])}
      />

      <span>
        {formatTime(player.current.currentTime)} / {formatTime(
          player.current.duration,
        )}
      </span>
    </div>

    <div>
      <button type="button" onclick={() => playerStore.requestToggleMute()}>
        {player.current.muted ? "Unmute" : "Mute"}
      </button>

      <input
        type="range"
        min="0"
        max="1"
        step="0.01"
        value={volumeValue[0]}
        oninput={(e) =>
          onVolumeInput([Number((e.currentTarget as HTMLInputElement).value)])}
      />
    </div>
  </div>
{/if}
