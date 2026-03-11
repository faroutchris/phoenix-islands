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
  attr :entries_page, :integer, default: 1, doc: "current entries page"
  attr :entries_has_previous_page?, :boolean, default: false, doc: "entries has previous page"
  attr :entries_has_next_page?, :boolean, default: false, doc: "entries has next page"

  attr :entries_pagination_base_path, :string,
    default: nil,
    doc: "base path used to build entries pagination links"

  attr :feed_modal_open, :boolean, default: false, doc: "whether add-feed modal is open"
  attr :feed_modal_changeset, :any, default: nil, doc: "changeset used in add-feed modal form"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="mx-auto grid h-full w-full max-w-[120rem] grid-cols-1 gap-4 px-4 py-4 lg:grid-cols-[18rem_22rem_minmax(0,1fr)]">
      <aside
        id="sidebar-feeds"
        class="hidden h-full overflow-y-auto rounded-2xl border border-base-300 bg-base-100/95 shadow-sm backdrop-blur lg:block"
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
        class="hidden h-full overflow-y-auto rounded-2xl border border-base-300 bg-base-100/95 shadow-sm backdrop-blur lg:block"
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

        <%= if @entries_pagination_base_path do %>
          <div
            id="sidebar-entries-pagination"
            class="hidden lg:flex items-center justify-between border-t border-base-300 bg-base-100 px-3 py-3 text-xs"
          >
            <%= if @entries_has_previous_page? do %>
              <a
                id="sidebar-entries-prev"
                href={"#{@entries_pagination_base_path}?page=#{@entries_page - 1}"}
                class="rounded-lg border border-base-300 px-2.5 py-1.5 font-medium text-base-content/80 transition-colors hover:bg-base-200"
              >
                Previous
              </a>
            <% else %>
              <span class="rounded-lg border border-base-300 px-2.5 py-1.5 text-base-content/40">
                Previous
              </span>
            <% end %>

            <span class="text-base-content/70">Page {@entries_page}</span>

            <%= if @entries_has_next_page? do %>
              <a
                id="sidebar-entries-next"
                href={"#{@entries_pagination_base_path}?page=#{@entries_page + 1}"}
                class="rounded-lg border border-base-300 px-2.5 py-1.5 font-medium text-base-content/80 transition-colors hover:bg-base-200"
              >
                Next
              </a>
            <% else %>
              <span class="rounded-lg border border-base-300 px-2.5 py-1.5 text-base-content/40">
                Next
              </span>
            <% end %>
          </div>
        <% end %>
      </aside>

      <main class="min-h-0 min-w-0 overflow-y-auto rounded-2xl border border-base-300 bg-base-100 shadow-sm">
        <div class="border-b border-base-300 px-4 py-3 sm:px-6">
          <div class="flex items-center justify-end gap-2 text-xs sm:text-sm">
            <a href="https://phoenixframework.org/" class="btn btn-ghost btn-sm">Website</a>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost btn-sm">
              GitHub
            </a>
            <a href={~p"/feeds/new"} class="btn btn-primary btn-sm">
              Add New Feed
            </a>
          </div>
        </div>
        <div class="p-4 sm:p-6">
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>

    <%= if @feed_modal_open && @feed_modal_changeset do %>
      <dialog id="feed-modal" open class="modal modal-open">
        <div class="modal-box max-w-lg border border-base-300 bg-base-100">
          <div class="mb-4 flex items-center justify-between">
            <h2 class="text-lg font-semibold text-base-content">Add new feed</h2>
            <a
              href={~p"/list"}
              data-swup-link-to-fragment="#swup"
              class="rounded-md border border-base-300 px-2 py-1 text-xs font-medium text-base-content/70 transition-colors hover:bg-base-200"
            >
              Close
            </a>
          </div>

          <% form = to_form(@feed_modal_changeset) %>
          <.form
            for={form}
            id="feed-modal-form"
            action={~p"/feeds/new"}
            method="post"
            data-swup-form
            class="space-y-4"
            data-no-swup
          >
            <.input
              field={form[:url]}
              label="Feed URL"
              placeholder="https://example.com/feed.xml"
              type="url"
              required
            />
            <div class="flex items-center justify-end gap-2">
              <a
                href={~p"/list"}
                data-swup-link-to-fragment="#swup"
                class="rounded-lg border border-base-300 px-3 py-2 text-sm font-medium text-base-content/80 transition-colors hover:bg-base-200"
              >
                Cancel
              </a>
              <button
                type="submit"
                class="rounded-lg bg-base-content px-4 py-2 text-sm font-medium text-base-100 transition-opacity hover:opacity-90"
              >
                Add feed
              </button>
            </div>
          </.form>
        </div>
      </dialog>
    <% else %>
      <template id="feed-modal"></template>
    <% end %>

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
