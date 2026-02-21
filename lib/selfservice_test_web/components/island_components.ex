defmodule SelfServiceWeb.IslandComponent do
  use Phoenix.Component

  attr :module, :string, doc: "the module you want to render"
  attr :props, :map, default: %{}, doc: "properties to pass into the component"
  attr :lazy, :boolean, default: false, doc: "lazy loads component when its in view"
  attr :media, :string, default: nil, doc: "the media query to decide if this component should be rendered"
  def island(assigns) do
    json = Jason.encode!(assigns.props)
    assigns = assigns |> assign(:json, json)

    ~H"""
    <island-root
      data-module={@module}
      data-props={@json}
      data-lazy={@lazy}
      data-media={@media}
    ></island-root>
    """
  end
end
