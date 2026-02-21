defmodule SelfServiceWeb.PageController do
  use SelfServiceWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
