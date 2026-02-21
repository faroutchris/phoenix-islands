defmodule SelfServiceWeb.IslandComponentTest do
  use SelfServiceWeb.ConnCase

  import Phoenix.LiveViewTest
  import SelfServiceWeb.IslandComponent

  test "renders a island web component with module and props" do
    html = render_component(&island/1, module: "CartTotal", props: %{total: 123, currency: "SEK"}, lazy: true)

    assert html =~ "<island-root"
    assert html =~ "data-module=\"CartTotal\""
    assert html =~ "data-props=\"{&quot;total&quot;:123,&quot;currency&quot;:&quot;SEK&quot;}\""
    assert html =~ "data-lazy"
    assert html =~ "</island-root>"
  end
end
