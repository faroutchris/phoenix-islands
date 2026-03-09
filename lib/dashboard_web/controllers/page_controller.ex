defmodule DashboardWeb.PageController do
  use DashboardWeb, :controller

  alias Dashboard.RSS
  alias Dashboard.RSS.Feed

  def home(conn, _params) do
    render(conn, :home)
  end

  def list(conn, _params) do
    render(conn, :list, list_assigns())
  end

  def create_feed(conn, %{"feed" => feed_params}) do
    url = Map.get(feed_params, "url", "")

    case RSS.subscribe(url) do
      {:ok, _feed} ->
        conn
        |> put_flash(:info, "Feed added")
        |> redirect(to: ~p"/list")

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:list, list_assigns(changeset))

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not subscribe to feed")
        |> redirect(to: ~p"/list")
    end
  end

  def entries(conn, %{"feed_id" => feed_id}) do
    page = parse_page_param(conn.params["page"])
    page_size = 20
    feed = RSS.get_feed!(feed_id)
    entries = RSS.list_feed_entries(feed_id, page: page, page_size: page_size)
    has_next_page? = RSS.list_feed_entries(feed_id, page: page + 1, page_size: 1) != []

    render(conn, :entries,
      feed: feed,
      entries: entries,
      page: page,
      has_previous_page?: page > 1,
      has_next_page?: has_next_page?
    )
  end

  def entry(conn, %{"feed_id" => feed_id, "entry_id" => entry_id}) do
    page = parse_page_param(conn.params["page"])
    page_size = 20
    feed = RSS.get_feed!(feed_id)
    entry = RSS.get_feed_entry!(feed_id, entry_id)
    entries = RSS.list_feed_entries(feed_id, page: page, page_size: page_size)
    has_next_page? = RSS.list_feed_entries(feed_id, page: page + 1, page_size: 1) != []

    render(conn, :entry,
      feed: feed,
      entry: entry,
      entries: entries,
      page: page,
      has_previous_page?: page > 1,
      has_next_page?: has_next_page?
    )
  end

  defp parse_page_param(nil), do: 1
  defp parse_page_param(""), do: 1

  defp parse_page_param(page_param) when is_binary(page_param) do
    case Integer.parse(page_param) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp list_assigns(changeset \\ RSS.change_feed(%Feed{})) do
    [changeset: changeset]
  end
end
