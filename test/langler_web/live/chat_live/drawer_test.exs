defmodule LanglerWeb.ChatLive.DrawerTest do
  use LanglerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Langler.AccountsFixtures

  alias Langler.Accounts.LlmConfig
  alias Langler.Chat.Session

  defp create_default_config(user) do
    LlmConfig.create_config(user, %{
      provider_name: "openai",
      api_key: "secret-key-1234",
      model: "gpt-4o-mini"
    })
  end

  describe "chat drawer" do
    test "opens drawer and toggles sidebar", %{conn: conn} do
      user = user_fixture()
      assert {:ok, _config} = create_default_config(user)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/articles")

      refute has_element?(view, "#chat-drawer-container.chat-open")

      view
      |> element("button[aria-label='Open chat']")
      |> render_click()

      assert has_element?(view, "#chat-drawer-container.chat-open")
      assert has_element?(view, "#chat-drawer-sidebar.w-0")

      view
      |> element("button[aria-label='Toggle sidebar']")
      |> render_click()

      assert has_element?(view, "#chat-drawer-sidebar.w-64")
    end

    test "updates input and toggles keyboard for an active session", %{conn: conn} do
      user = user_fixture()
      assert {:ok, _config} = create_default_config(user)
      assert {:ok, _session} = Session.create_session(user, %{})

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/articles")

      view
      |> element("button[aria-label='Open chat']")
      |> render_click()

      view
      |> element("input[name='message']")
      |> render_change(%{"message" => "Hola"})

      assert has_element?(view, "input[name='message'][value='Hola']")

      view
      |> element("button[aria-label='Show keyboard']")
      |> render_click()

      assert has_element?(view, "#chat-keyboard")
    end
  end
end
