defmodule LanglerWeb.ChatLive.ChatHeaderTest do
  use LanglerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Langler.ChatFixtures

  alias LanglerWeb.ChatLive.ChatHeader

  defp document(html), do: LazyHTML.from_fragment(html)

  defp has_selector?(document, selector) do
    document
    |> LazyHTML.query(selector)
    |> LazyHTML.to_tree()
    |> Enum.any?()
  end

  defp text_for(document, selector) do
    document
    |> LazyHTML.query(selector)
    |> LazyHTML.text()
  end

  describe "chat_header/1" do
    test "renders header with default title when no session" do
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&ChatHeader.chat_header/1, %{
          current_session: nil,
          myself: myself
        })

      document = document(html)

      assert text_for(document, "h3") =~ "Chat Assistant"
      assert has_selector?(document, "button[aria-label='Toggle sidebar']")
      assert has_selector?(document, "button[aria-label='Close chat']")
    end

    test "renders session title when session is provided" do
      session = chat_session_fixture(%{title: "My Chat Session"})
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&ChatHeader.chat_header/1, %{
          current_session: session,
          myself: myself
        })

      document = document(html)

      assert text_for(document, "h3") =~ "My Chat Session"
    end

    test "renders 'New Chat' when session has no title" do
      session = chat_session_fixture(%{title: nil})
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&ChatHeader.chat_header/1, %{
          current_session: session,
          myself: myself
        })

      document = document(html)

      assert text_for(document, "h3") =~ "New Chat"
    end

    test "has all action buttons" do
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&ChatHeader.chat_header/1, %{
          current_session: nil,
          myself: myself
        })

      document = document(html)

      assert has_selector?(document, "button[phx-click='toggle_sidebar']")
      assert has_selector?(document, "button[phx-click='toggle_keyboard']")
      assert has_selector?(document, "button[phx-click='toggle_fullscreen']")
      assert has_selector?(document, "button[phx-click='toggle_chat']")
    end

    test "shows fullscreen icon when not in fullscreen" do
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&ChatHeader.chat_header/1, %{
          current_session: nil,
          myself: myself,
          fullscreen: false
        })

      document = document(html)

      assert has_selector?(document, "span.hero-arrows-pointing-out")
      refute has_selector?(document, "span.hero-arrows-pointing-in")
    end

    test "shows exit fullscreen icon when in fullscreen" do
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&ChatHeader.chat_header/1, %{
          current_session: nil,
          myself: myself,
          fullscreen: true
        })

      document = document(html)

      assert has_selector?(document, "span.hero-arrows-pointing-in")
      refute has_selector?(document, "span.hero-arrows-pointing-out")
    end
  end
end
