defmodule Dashboard.RSSFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Dashboard.RSS` context.
  """

  @doc """
  Generate a feed.
  """
  def feed_fixture(attrs \\ %{}) do
    {:ok, feed} =
      attrs
      |> Enum.into(%{
        author: "some author",
        description: "some description",
        etag: "some etag",
        favicon: "some favicon",
        last_modified: "some last_modified",
        next_fetch: ~N[2026-02-28 18:10:00],
        title: "some title"
      })
      |> Dashboard.RSS.create_feed()

    feed
  end
end
