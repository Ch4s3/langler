defmodule LanglerWeb.Admin.SourceSitesLiveTest do
  use LanglerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Langler.Content

  setup :register_and_log_in_user

  defp source_site_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Example Site",
        "url" => "https://example.test",
        "language" => "spanish",
        "discovery_method" => "rss",
        "rss_url" => "https://example.test/rss.xml",
        "scraping_config_json" => "{}",
        "check_interval_hours" => "24",
        "is_active" => "true"
      },
      overrides
    )
  end

  test "lists source sites and toggles active state", %{conn: conn} do
    {:ok, site} =
      Content.create_source_site(%{
        name: "Site",
        url: "https://example.test",
        discovery_method: "rss",
        language: "spanish"
      })

    {:ok, view, _html} = live(conn, "/admin/source-sites")

    assert has_element?(view, "#source-sites-table")
    assert has_element?(view, "#toggle-active-#{site.id}")

    view
    |> element("#toggle-active-#{site.id}")
    |> render_click()

    refute Content.get_source_site!(site.id).is_active

    view
    |> element("#run-discovery-#{site.id}")
    |> render_click()
  end

  test "creates and edits a source site", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/source-sites/new")

    assert has_element?(view, "#source-site-form")

    params = source_site_attrs()

    view
    |> form("#source-site-form", source_site: params)
    |> render_change()

    view
    |> form("#source-site-form", source_site: params)
    |> render_submit()

    assert_redirect(view, "/admin/source-sites")

    {:ok, site} =
      Content.create_source_site(%{
        name: "Edit Me",
        url: "https://edit.test",
        discovery_method: "rss",
        language: "spanish"
      })

    {:ok, edit_view, _html} = live(conn, "/admin/source-sites/#{site.id}/edit")

    edit_params =
      source_site_attrs(%{
        "name" => "Updated Name",
        "url" => "https://edit.test"
      })

    edit_view
    |> form("#source-site-form", source_site: edit_params)
    |> render_submit()

    assert_redirect(edit_view, "/admin/source-sites")

    assert Content.get_source_site!(site.id).name == "Updated Name"
  end
end
