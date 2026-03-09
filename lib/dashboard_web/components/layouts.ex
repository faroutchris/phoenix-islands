defmodule DashboardWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use DashboardWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :sidebar_feeds, :list,
    default: [],
    doc: "feeds rendered in the global sidebar"

  attr :sidebar_entries, :list,
    default: [],
    doc: "entries rendered in the feed entries sidebar"

  attr :selected_feed_id, :string, default: nil, doc: "currently selected feed id"
  attr :selected_entry_id, :string, default: nil, doc: "currently selected entry id"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="mx-auto grid w-full max-w-[120rem] grid-cols-1 gap-4 px-4 py-4 lg:grid-cols-[18rem_22rem_minmax(0,1fr)]">
      <aside
        id="sidebar-feeds"
        class="rounded-2xl border border-base-300 bg-base-100/95 shadow-sm backdrop-blur lg:sticky lg:top-4 lg:h-[calc(100vh-2rem)] lg:overflow-y-auto"
      >
        <div class="flex items-center justify-between border-b border-base-300 px-4 py-3">
          <a href={~p"/list"} class="flex items-center gap-2 text-sm font-semibold tracking-wide">
            <img src={~p"/images/logo.svg"} width="28" />
            <span>Feeds</span>
          </a>
          <.theme_toggle />
        </div>

        <nav aria-label="Subscribed feeds" class="space-y-1 px-2 py-2">
          <%= for feed <- @sidebar_feeds do %>
            <a
              id={"sidebar-feed-#{feed.id}"}
              href={~p"/list/#{feed.id}/entries"}
              class={[
                "block rounded-lg px-3 py-2 text-sm font-medium transition-colors",
                if(@selected_feed_id == feed.id,
                  do: "bg-base-content text-base-100",
                  else: "text-base-content/80 hover:bg-base-200 hover:text-base-content"
                )
              ]}
            >
              {feed.title}
            </a>
          <% end %>
          <%= if @sidebar_feeds == [] do %>
            <p class="rounded-lg border border-dashed border-base-300 px-3 py-4 text-sm text-base-content/60 mt-2">
              No feeds yet. Add one to populate the sidebar.
            </p>
          <% end %>
        </nav>

        <div class="border-t border-base-300 px-4 py-3 text-xs text-base-content/60">
          Phoenix v{Application.spec(:phoenix, :vsn)}
        </div>
      </aside>

      <aside
        id="sidebar-entries"
        class="rounded-2xl border border-base-300 bg-base-100/95 shadow-sm backdrop-blur lg:sticky lg:top-4 lg:h-[calc(100vh-2rem)] lg:overflow-y-auto"
      >
        <div class="border-b border-base-300 px-4 py-3">
          <p class="text-xs uppercase tracking-wide text-base-content/60">Episodes</p>
          <p class="mt-1 text-sm font-semibold text-base-content">
            <%= if @selected_feed_id do %>
              Feed entries
            <% else %>
              Select a feed
            <% end %>
          </p>
        </div>
        <div class="space-y-1 px-2 py-2">
          <%= if @selected_feed_id && @sidebar_entries == [] do %>
            <p class="rounded-lg border border-dashed border-base-300 px-3 py-4 text-sm text-base-content/60">
              No episodes on this page.
            </p>
          <% end %>
          <%= if !@selected_feed_id do %>
            <p class="rounded-lg border border-dashed border-base-300 px-3 py-4 text-sm text-base-content/60">
              Choose a feed in the left sidebar.
            </p>
          <% end %>
          <%= for entry <- @sidebar_entries do %>
            <% feed = Enum.find(@sidebar_feeds, &(&1.id == entry.feed_id)) %>
            <a
              id={"sidebar-entry-#{entry.id}"}
              href={~p"/list/#{entry.feed_id}/entries/#{entry.id}"}
              class={[
                "block rounded-lg px-3 py-2 text-sm transition-colors",
                if(@selected_entry_id == entry.id,
                  do: "bg-base-content text-base-100",
                  else: "text-base-content/80 hover:bg-base-200 hover:text-base-content"
                )
              ]}
            >
              <div class="flex items-start gap-3">
                <.island
                  module="playbutton"
                  props={
                    %{
                      media: %{
                        id: entry.id,
                        feedId: entry.feed_id,
                        title: entry.title || "(untitled)",
                        feedTitle: if(feed, do: feed.title, else: "Unknown feed"),
                        image: if(feed, do: feed.favicon, else: nil),
                        attachments:
                          Enum.map(entry.enclosures, fn enclosure ->
                            %{url: enclosure.url, mimeType: enclosure.media_type}
                          end)
                      }
                    }
                  }
                />
                <div class="min-w-0">
                  <p class="font-medium leading-tight">{entry.title || "(untitled)"}</p>
                  <p class="mt-1 text-xs opacity-70">
                    <%= if entry.published_at do %>
                      {Calendar.strftime(entry.published_at, "%Y-%m-%d %H:%M")}
                    <% else %>
                      Unknown date
                    <% end %>
                  </p>
                </div>
              </div>
            </a>
          <% end %>
        </div>
      </aside>

      <main class="min-w-0 rounded-2xl border border-base-300 bg-base-100 shadow-sm lg:h-[calc(100vh-2rem)] lg:overflow-y-auto">
        <div class="border-b border-base-300 px-4 py-3 sm:px-6">
          <div class="flex items-center justify-end gap-2 text-xs sm:text-sm">
            <a href="https://phoenixframework.org/" class="btn btn-ghost btn-sm">Website</a>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost btn-sm">
              GitHub
            </a>
            <a href="https://hexdocs.pm/phoenix/overview.html" class="btn btn-primary btn-sm">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </div>
        </div>
        <div class="p-4 sm:p-6">
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <.island module="themetoggle" />
    """
  end
end
