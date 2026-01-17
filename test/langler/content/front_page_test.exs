defmodule Langler.Content.FrontPageTest do
  use ExUnit.Case, async: false

  import Req.Test, only: [set_req_test_from_context: 1]

  alias Langler.Content.FrontPage

  @front_page_req Langler.Content.FrontPageReq

  setup :set_req_test_from_context
  setup {Req.Test, :verify_on_exit!}

  setup do
    Application.put_env(:langler, Langler.Content.FrontPage,
      req_options: [plug: {Req.Test, @front_page_req}]
    )

    on_exit(fn -> Application.delete_env(:langler, Langler.Content.FrontPage) end)

    %{front_page: @front_page_req}
  end

  test "returns a matching article link", %{front_page: front_page} do
    Req.Test.expect(front_page, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/index"

      html = """
      <html>
        <body>
          <a href="/posts/123">Post</a>
          <a href="mailto:news@example.com">Email</a>
        </body>
      </html>
      """

      Req.Test.html(conn, html)
    end)

    source = %{
      front_page: "https://front-page.test/index",
      article_pattern: ~r{/posts/\d+},
      label: "Example"
    }

    assert {:ok, url} = FrontPage.random_article(source)
    assert url == "https://front-page.test/posts/123"
  end

  test "returns an error when no links match", %{front_page: front_page} do
    Req.Test.expect(front_page, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/index"

      html = """
      <html>
        <body>
          <a href="/about">About</a>
        </body>
      </html>
      """

      Req.Test.html(conn, html)
    end)

    source = %{
      front_page: "https://front-page.test/index",
      article_pattern: ~r{/posts/\d+},
      label: "Example"
    }

    assert {:error, :no_links} = FrontPage.random_article(source)
  end
end
