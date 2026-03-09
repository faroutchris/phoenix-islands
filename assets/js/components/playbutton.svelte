<script lang="ts">
  import { fromStore } from "svelte/store";
  import {
    isPlayableAttachment,
    playerStore,
    type PlayerMedia,
  } from "../player_store";

  type Props = {
    media: PlayerMedia;
    class?: string;
  };

  let { media, class: className = "" }: Props = $props();

  const player = fromStore(playerStore);
  const playerState = $derived(player.current);

  const isCurrent = $derived(playerState.current?.id === media.id);
  const isPlayingCurrent = $derived(
    playerState.current?.id === media.id && playerState.status === "playing",
  );
  const isLoadingCurrent = $derived(
    playerState.current?.id === media.id && playerState.status === "loading",
  );
  const hasPlayableAttachment = $derived(
    media.attachments.some((attachment) => isPlayableAttachment(attachment)),
  );

  function onClick() {
    if (!hasPlayableAttachment) return;
    if (isLoadingCurrent) return;
    playerStore.requestToggle(media);
  }
</script>

{#if hasPlayableAttachment}
  <button
    type="button"
    class={className}
    onclick={onClick}
    aria-pressed={isPlayingCurrent}
    disabled={!hasPlayableAttachment}
  >
    {#if isPlayingCurrent}
      Pause
    {:else if isLoadingCurrent}
      Loading...
    {:else}
      Play
    {/if}
  </button>
{/if}
