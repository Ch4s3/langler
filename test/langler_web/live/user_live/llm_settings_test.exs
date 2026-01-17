defmodule LanglerWeb.UserLive.LlmSettingsTest do
  use LanglerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Langler.Accounts.LlmProvider
  alias Langler.Repo

  setup :register_and_log_in_user

  setup do
    provider =
      %LlmProvider{}
      |> LlmProvider.changeset(%{
        name: "openai",
        display_name: "OpenAI",
        adapter_module: "Langler.LLM.Adapters.ChatGPT",
        enabled: true
      })
      |> Repo.insert!()

    %{provider: provider}
  end

  test "creates, edits, and deletes LLM configs", %{conn: conn, provider: provider} do
    {:ok, view, _html} = live(conn, "/users/settings/llm")

    assert has_element?(view, "#llm-config-form")

    params = %{
      "provider_name" => provider.name,
      "api_key" => "secret-key-1234",
      "model" => "gpt-4o-mini",
      "temperature" => "0.7",
      "max_tokens" => "2000",
      "is_default" => "true"
    }

    view
    |> form("#llm-config-form", params)
    |> render_change()

    view
    |> form("#llm-config-form", params)
    |> render_submit()

    assert has_element?(view, "button[phx-click='edit_config']")
    assert has_element?(view, "button[phx-click='delete_config']")

    view
    |> element("button[phx-click='edit_config']")
    |> render_click()

    assert has_element?(view, "button[phx-click='cancel_edit']")

    view
    |> element("button[phx-click='cancel_edit']")
    |> render_click()

    refute has_element?(view, "button[phx-click='cancel_edit']")

    view
    |> element("button[phx-click='delete_config']")
    |> render_click()

    refute has_element?(view, "button[phx-click='delete_config']")
  end
end
