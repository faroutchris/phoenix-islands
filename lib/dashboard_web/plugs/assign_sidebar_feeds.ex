defmodule DashboardWeb.Plugs.AssignSidebarFeeds do
  @moduledoc """
  Assigns feeds used by the global sidebar for browser-rendered HTML pages.
  """

  import Plug.Conn

  alias Dashboard.RSS

  def init(opts), do: opts

  def call(conn, _opts) do
    if Phoenix.Controller.get_format(conn) == "html" do
      assign(conn, :sidebar_feeds, RSS.list_feed())
    else
      conn
    end
  end
end
