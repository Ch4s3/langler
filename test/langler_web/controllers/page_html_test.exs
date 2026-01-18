defmodule LanglerWeb.PageHTMLTest do
  use LanglerWeb.ConnCase, async: true

  import Phoenix.Template, only: [render_to_string: 4]

  test "renders the home template" do
    html = render_to_string(LanglerWeb.PageHTML, "home", "html", %{flash: %{}})

    assert html =~ "Phoenix Framework"
    assert html =~ "Guides &amp; Docs"
  end
end
