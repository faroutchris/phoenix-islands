defmodule Dashboard.RSS.EntryStore do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Dashboard.Repo
  alias Ecto.Multi

  alias Dashboard.RSS.EntryNormalizer
  alias Dashboard.RSS.Feed
  alias Dashboard.RSS.FeedEntry
  alias Dashboard.RSS.FeedEntryEnclosure

  def upsert_feed_with_entries(%Feed{} = feed, feed_attrs, entries) when is_list(entries) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Multi.new()
    |> Multi.update(:feed, Feed.changeset(feed, feed_attrs))
    |> Multi.run(:entries, fn repo, _changes ->
      upsert_feed_entries(repo, feed.id, entries, now)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{feed: updated_feed, entries: stats}} ->
        :telemetry.execute(
          [:dashboard, :rss, :entries_persist],
          %{
            entries_inserted: stats.entries_inserted,
            entries_updated: stats.entries_updated,
            entries_deduped_in_batch: stats.entries_deduped_in_batch,
            entries_skipped_low_confidence: stats.entries_skipped_low_confidence,
            enclosures_upserted: stats.enclosures_upserted,
            enclosures_deleted: stats.enclosures_deleted
          },
          %{feed_id: updated_feed.id}
        )

        {:ok, updated_feed}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  defp upsert_feed_entries(repo, feed_id, entries, now) do
    normalization =
      Enum.reduce(entries, %{rows: [], seen: MapSet.new(), skipped: 0, deduped: 0}, fn entry,
                                                                                       acc ->
        case EntryNormalizer.normalize(feed_id, entry, now) do
          :skip ->
            %{acc | skipped: acc.skipped + 1}

          {:ok, normalized} ->
            if MapSet.member?(acc.seen, normalized.identity_hash) do
              %{acc | deduped: acc.deduped + 1}
            else
              %{
                acc
                | rows: [normalized | acc.rows],
                  seen: MapSet.put(acc.seen, normalized.identity_hash)
              }
            end
        end
      end)

    normalized_entries = Enum.reverse(normalization.rows)

    if normalized_entries == [] do
      {:ok,
       %{
         entries_inserted: 0,
         entries_updated: 0,
         entries_deduped_in_batch: normalization.deduped,
         entries_skipped_low_confidence: normalization.skipped,
         enclosures_upserted: 0,
         enclosures_deleted: 0
       }}
    else
      hashes = Enum.map(normalized_entries, & &1.identity_hash)

      existing_hashes =
        from(e in FeedEntry,
          where: e.feed_id == ^feed_id and e.identity_hash in ^hashes,
          select: e.identity_hash
        )
        |> repo.all()
        |> MapSet.new()

      insert_rows =
        Enum.map(normalized_entries, fn row ->
          row
          |> Map.put(:feed_id, feed_id)
          |> Map.take(feed_entry_insert_fields())
        end)

      {_, returned_entries} =
        repo.insert_all(
          FeedEntry,
          insert_rows,
          on_conflict: {:replace, feed_entry_update_fields()},
          conflict_target: [:feed_id, :identity_hash],
          returning: [:id, :identity_hash]
        )

      enclosure_map =
        Map.new(normalized_entries, fn row -> {row.identity_hash, row.enclosures} end)

      enclosure_stats =
        Enum.reduce(returned_entries, %{upserted: 0, deleted: 0}, fn row, acc ->
          stats =
            replace_enclosures(repo, row.id, Map.get(enclosure_map, row.identity_hash, []), now)

          %{upserted: acc.upserted + stats.upserted, deleted: acc.deleted + stats.deleted}
        end)

      entries_total = length(normalized_entries)
      entries_updated = Enum.count(hashes, &MapSet.member?(existing_hashes, &1))
      entries_inserted = entries_total - entries_updated

      {:ok,
       %{
         entries_inserted: entries_inserted,
         entries_updated: entries_updated,
         entries_deduped_in_batch: normalization.deduped,
         entries_skipped_low_confidence: normalization.skipped,
         enclosures_upserted: enclosure_stats.upserted,
         enclosures_deleted: enclosure_stats.deleted
       }}
    end
  end

  defp replace_enclosures(repo, entry_id, enclosures, now) do
    urls = Enum.map(enclosures, & &1.url)

    delete_query =
      if urls == [] do
        from(e in FeedEntryEnclosure, where: e.feed_entry_id == ^entry_id)
      else
        from(e in FeedEntryEnclosure,
          where: e.feed_entry_id == ^entry_id and e.url not in ^urls
        )
      end

    {deleted_count, _} = repo.delete_all(delete_query)

    if enclosures == [] do
      %{deleted: deleted_count, upserted: 0}
    else
      rows =
        Enum.map(enclosures, fn enclosure ->
          %{
            feed_entry_id: entry_id,
            url: enclosure.url,
            media_type: enclosure.media_type,
            length_bytes: enclosure.length_bytes,
            inserted_at: now,
            updated_at: now
          }
        end)

      {upserted_count, _} =
        repo.insert_all(
          FeedEntryEnclosure,
          rows,
          on_conflict: {:replace, [:media_type, :length_bytes, :updated_at]},
          conflict_target: [:feed_entry_id, :url]
        )

      %{deleted: deleted_count, upserted: upserted_count}
    end
  end

  defp feed_entry_insert_fields do
    [
      :feed_id,
      :identity_source,
      :identity_key,
      :identity_hash,
      :guid,
      :link,
      :title,
      :author,
      :summary,
      :content,
      :published_at,
      :updated_at_feed,
      :first_seen_at,
      :last_seen_at,
      :inserted_at,
      :updated_at
    ]
  end

  defp feed_entry_update_fields do
    [
      :title,
      :author,
      :summary,
      :content,
      :published_at,
      :updated_at_feed,
      :last_seen_at,
      :updated_at
    ]
  end
end
