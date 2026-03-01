defmodule DashboardWeb.IslandComponentTest do
  use DashboardWeb.ConnCase

  import Phoenix.LiveViewTest
  import DashboardWeb.IslandComponent

  test "renders a island web component with module and props" do
    html = render_component(&island/1, module: "CartTotal", props: %{total: 123, currency: "SEK"}, lazy: true)

    assert html =~ "<island-root"
    assert html =~ "data-module=\"CartTotal\""
    assert html =~ "data-props=\"{&quot;total&quot;:123,&quot;currency&quot;:&quot;SEK&quot;}\""
    assert html =~ "data-lazy"
    assert html =~ "</island-root>"
  end

  test "lazy rendering is turned off by default" do
    html = render_component(&island/1, module: "CartTotal")
    refute html =~ "data-lazy"
  end

  test "media query is turned off by default" do
    html = render_component(&island/1, module: "CartTotal")
    refute html =~ "data-media"
  end

  test "escapes json" do
    html = render_component(&island/1, module: "CartTotal", props: %{danger: "</island-root><script>alert(1)</script>"})

    refute html =~ "<script>alert(1)</script>"
    # Escaped data is passed along
    assert html =~ "data-props=\"{&quot;danger&quot;:&quot;&lt;/island-root&gt;&lt;script&gt;alert(1)&lt;/script&gt;&quot;}\""
  end
end
