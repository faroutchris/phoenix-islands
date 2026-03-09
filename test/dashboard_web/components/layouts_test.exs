defmodule DashboardWeb.LayoutsTest do
  use DashboardWeb.ConnCase, async: true

  import Dashboard.RSSFixtures
  import Phoenix.LiveViewTest

  alias DashboardWeb.Layouts

  test "app layout renders empty sidebar state" do
    html =
      render_component(&Layouts.app/1,
        flash: %{},
        sidebar_feeds: [],
        inner_block: [%{inner_block: fn _, _ -> "Content" end}]
      )

    assert html =~ "id=\"sidebar-feeds\""
    assert html =~ "No feeds yet. Add one to populate the sidebar."
    assert html =~ "Content"
  end

  test "app layout renders sidebar feeds" do
    feed = feed_fixture(%{title: "Layout Feed", url: "https://example.com/layout.xml"})

    html =
      render_component(&Layouts.app/1,
        flash: %{},
        sidebar_feeds: [feed],
        inner_block: [%{inner_block: fn _, _ -> "Content" end}]
      )

    assert html =~ "id=\"sidebar-feed-#{feed.id}\""
    assert html =~ feed.title
    assert html =~ ~p"/list/#{feed.id}/entries"
  end
end
