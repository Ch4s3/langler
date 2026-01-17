defmodule LanglerWeb.ChatLive.SessionItemTest do
  use LanglerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Langler.ChatFixtures

  alias LanglerWeb.ChatLive.SessionItem

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

  describe "session_item/1" do
    test "renders session title and date" do
      session = chat_session_fixture(%{title: "Test Chat", inserted_at: DateTime.utc_now()})
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&SessionItem.session_item/1, %{
          session: session,
          myself: myself,
          inserted_at: session.inserted_at
        })

      document = document(html)

      assert text_for(document, "p.text-sm") =~ "Test Chat"
      assert has_selector?(document, "button[phx-click='switch_session']")
      assert text_for(document, "p.text-xs") =~ "Just now"
    end

    test "shows rename form when is_renaming is true" do
      session = chat_session_fixture(%{title: "Test Chat"})
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&SessionItem.session_item/1, %{
          session: session,
          myself: myself,
          is_renaming: true,
          rename_value: "New Title"
        })

      document = document(html)

      assert has_selector?(document, "form[phx-submit='save_rename']")
      assert has_selector?(document, "input[name='title'][value='New Title']")
    end

    test "shows kebab menu when menu_open is true" do
      session = chat_session_fixture(%{title: "Test Chat"})
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&SessionItem.session_item/1, %{
          session: session,
          myself: myself,
          menu_open: true
        })

      document = document(html)

      assert has_selector?(document, "ul.menu")
      assert has_selector?(document, "button[phx-click='rename_session']")
      assert has_selector?(document, "button[phx-click='toggle_pin_session']")
      assert has_selector?(document, "button[phx-click='delete_session']")
    end

    test "shows unpin when session is pinned" do
      session = chat_session_fixture(%{title: "Test Chat", pinned: true})
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&SessionItem.session_item/1, %{
          session: session,
          myself: myself,
          menu_open: true
        })

      document = document(html)

      assert has_selector?(document, "button[phx-click='toggle_pin_session']")
      assert has_selector?(document, "span.hero-pin-slash")
    end

    test "applies current session styling when is_current is true" do
      session = chat_session_fixture(%{title: "Test Chat"})
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&SessionItem.session_item/1, %{
          session: session,
          myself: myself,
          is_current: true
        })

      document = document(html)

      classes =
        document
        |> LazyHTML.query("div")
        |> LazyHTML.attribute("class")
        |> List.first()
        |> Kernel.||("")

      assert String.contains?(classes, "border-primary/50")
      assert String.contains?(classes, "bg-primary/5")
    end

    test "truncates long titles with tooltip" do
      long_title = String.duplicate("A", 100)
      session = chat_session_fixture(%{title: long_title})
      myself = %Phoenix.LiveComponent.CID{cid: 1}

      html =
        render_component(&SessionItem.session_item/1, %{
          session: session,
          myself: myself
        })

      document = document(html)

      titles =
        document
        |> LazyHTML.query("p.truncate")
        |> LazyHTML.attribute("title")

      assert titles == [long_title]
    end
  end
end
