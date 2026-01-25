defmodule LanglerWeb.UserLive.GoogleTranslateSettingsTest do
  use LanglerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "creates, edits, and deletes Google Translate configs", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/users/settings/google-translate")

    assert has_element?(view, "#google-translate-config-form")

    # Initial params (flat, will be nested after validation)
    initial_params = %{
      "api_key" => "secret-key-1234",
      "is_default" => "true",
      "enabled" => "true"
    }

    # After render_change, form uses nested structure
    view
    |> form("#google-translate-config-form", initial_params)
    |> render_change()

    # Submit with nested params (as the form expects after validation)
    nested_params = %{
      "google_translate_config" => %{
        "api_key" => "secret-key-1234",
        "is_default" => "true",
        "enabled" => "true"
      }
    }

    view
    |> form("#google-translate-config-form", nested_params)
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
    {:ok, view, html} = live(conn, "/users/settings/google-translate")

    assert html =~ "No Google Translate configuration yet"
    assert has_element?(view, "#google-translate-config-form")
  end

  test "validates form before submission", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/users/settings/google-translate")

    view
    |> form("#google-translate-config-form", %{"api_key" => ""})
    |> render_change()

    # Form should still be visible (validation happens on submit)
    assert has_element?(view, "#google-translate-config-form")
  end
end
