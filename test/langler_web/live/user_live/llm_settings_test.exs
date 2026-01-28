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

  test "displays empty state when no configs exist", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/users/settings/llm")

    assert render(view) =~ "No LLM configurations yet"
    assert render(view) =~ "Add your first API key below to get started"
  end

  test "handles validate event with form params", %{conn: conn, provider: provider} do
    {:ok, view, _html} = live(conn, "/users/settings/llm")

    params = %{
      "llm_config" => %{
        "provider_name" => provider.name,
        "api_key" => "test-key",
        "temperature" => "0.8"
      }
    }

    view
    |> render_hook("validate", params)

    # Should not crash
    assert view.pid |> Process.alive?()
  end

  test "handles validate event with map params (not nested)", %{conn: conn, provider: provider} do
    {:ok, view, _html} = live(conn, "/users/settings/llm")

    params = %{
      "provider_name" => provider.name,
      "api_key" => "test-key",
      "_target" => ["provider_name"]
    }

    view
    |> render_hook("validate", params)

    # Should handle unnested params without crashing
    assert view.pid |> Process.alive?()
  end

  test "handles save_config with map params (not nested)", %{conn: conn, provider: provider} do
    {:ok, view, _html} = live(conn, "/users/settings/llm")

    params = %{
      "provider_name" => provider.name,
      "api_key" => "test-key-direct",
      "temperature" => "0.7",
      "max_tokens" => "2000"
    }

    view
    |> render_hook("save_config", params)

    # Should save successfully
    assert render(view) =~ "Configuration saved successfully"
  end

  test "provider_display_name returns correct display name", %{conn: conn, provider: provider} do
    {:ok, view, _html} = live(conn, "/users/settings/llm")

    # Create a config
    params = %{
      "provider_name" => provider.name,
      "api_key" => "secret-key-1234",
      "temperature" => "0.7",
      "max_tokens" => "2000"
    }

    view
    |> form("#llm-config-form", params)
    |> render_submit()

    # Should show OpenAI as display name
    assert render(view) =~ "OpenAI"
  end
end
