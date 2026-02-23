defmodule SelfServiceWeb.IslandComponent do
  use Phoenix.Component
  require Logger

  attr :module, :string, doc: "the module you want to render"
  attr :props, :map, default: %{}, doc: "properties to pass into the component"
  attr :lazy, :boolean, default: false, doc: "lazy loads component when its in view"
  attr :media, :string, default: nil, doc: "the media query to decide if this component should be rendered"

  def island(assigns) do
    json = Jason.encode!(assigns.props)
    ssr_html = ssr_render(assigns.module, assigns.props)
    assigns = assigns |> assign(:json, json) |> assign(:ssr_html, ssr_html)

    ~H"""
    <island-root
      data-module={@module}
      data-lazy={@lazy}
      data-media={@media}
      data-props={@json}
    >{@ssr_html}</island-root>
    """
  end

  defp ssr_render(module, props) do
    case SelfServiceWeb.IslandSsrWorker.render(module, props) do
      {:ok, %{"html" => html}} ->
        Phoenix.HTML.raw(html)

      {:error, reason} ->
        Logger.warning("SSR render failed for #{module}: #{inspect(reason)}")
        ""
    end
  end
end
