defmodule LanglerWeb.CoreComponentsTest do
  use LanglerWeb.ConnCase, async: true
  use LanglerWeb, :html

  import Phoenix.LiveViewTest

  describe "search_input/1" do
    test "renders with correct attributes" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.search_input
              id="test-search"
              value="test query"
              placeholder="Search..."
              event="search"
              clear_event="clear_search"
            />
            """
          end,
          %{}
        )

      assert html =~ ~r/id="test-search"/
      assert html =~ ~r/value="test query"/
      assert html =~ ~r/placeholder="Search..."/
      assert html =~ ~r/phx-change="search"/
      assert html =~ "hero-magnifying-glass"
    end

    test "shows clear button when value is not empty" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.search_input
              id="test-search"
              value="test"
              placeholder="Search..."
              event="search"
              clear_event="clear_search"
            />
            """
          end,
          %{}
        )

      assert html =~ ~r/phx-click="clear_search"/
      assert html =~ "hero-x-mark"
    end

    test "hides clear button when value is empty" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.search_input
              id="test-search"
              value=""
              placeholder="Search..."
              event="search"
              clear_event="clear_search"
            />
            """
          end,
          %{}
        )

      refute html =~ ~r/phx-click="clear_search"/
    end

    test "applies custom debounce value" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.search_input
              id="test-search"
              value=""
              placeholder="Search..."
              event="search"
              clear_event="clear_search"
              debounce={500}
            />
            """
          end,
          %{}
        )

      assert html =~ ~r/phx-debounce="500"/
    end

    test "applies custom class" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.search_input
              id="test-search"
              value=""
              placeholder="Search..."
              event="search"
              clear_event="clear_search"
              class="custom-class"
            />
            """
          end,
          %{}
        )

      assert html =~ "custom-class"
    end
  end

  describe "list_empty_state/1" do
    test "renders with title, description, and actions slots" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.list_empty_state id="test-empty">
              <:title>No results found</:title>
              <:description>Try adjusting your search.</:description>
              <:actions>
                <button>Clear search</button>
              </:actions>
            </.list_empty_state>
            """
          end,
          %{}
        )

      assert html =~ ~r/id="test-empty"/
      assert html =~ "No results found"
      assert html =~ "Try adjusting your search."
      assert html =~ "Clear search"
    end

    test "renders without description slot" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.list_empty_state id="test-empty">
              <:title>No results</:title>
            </.list_empty_state>
            """
          end,
          %{}
        )

      assert html =~ "No results"
      refute html =~ "Try adjusting"
    end

    test "renders without actions slot" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.list_empty_state id="test-empty">
              <:title>No results</:title>
            </.list_empty_state>
            """
          end,
          %{}
        )

      assert html =~ "No results"
    end

    test "applies correct CSS classes" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.list_empty_state id="test-empty" class="custom-class">
              <:title>No results</:title>
            </.list_empty_state>
            """
          end,
          %{}
        )

      assert html =~ "custom-class"
      assert html =~ "border-dashed"
      assert html =~ "rounded-3xl"
    end
  end

  describe "spinner/1" do
    test "renders with default size" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.spinner />
            """
          end,
          %{}
        )

      assert html =~ "loading-spinner"
      assert html =~ "loading-sm"
    end

    test "renders with custom size" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.spinner size={:lg} />
            """
          end,
          %{}
        )

      assert html =~ "loading-lg"
    end

    test "renders with optional text" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.spinner text="Loading..." />
            """
          end,
          %{}
        )

      assert html =~ "Loading..."
    end

    test "renders without text" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.spinner />
            """
          end,
          %{}
        )

      refute html =~ "Loading"
    end

    test "applies custom class" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.spinner class="custom-class" />
            """
          end,
          %{}
        )

      assert html =~ "custom-class"
    end

    test "renders xs size" do
      html = render_component(fn assigns -> ~H"<.spinner size={:xs} />" end, %{})
      assert html =~ "loading-xs"
    end

    test "renders sm size" do
      html = render_component(fn assigns -> ~H"<.spinner size={:sm} />" end, %{})
      assert html =~ "loading-sm"
    end

    test "renders md size" do
      html = render_component(fn assigns -> ~H"<.spinner size={:md} />" end, %{})
      assert html =~ "loading-md"
    end

    test "renders lg size" do
      html = render_component(fn assigns -> ~H"<.spinner size={:lg} />" end, %{})
      assert html =~ "loading-lg"
    end
  end

  describe "settings_page/1" do
    test "renders title, subtitle, back link, and inner content" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.settings_page
              title="Test Settings"
              subtitle="Configure something."
              back_path={~p"/users/settings"}
            >
              <div id="settings-content">Inner content</div>
            </.settings_page>
            """
          end,
          %{}
        )

      assert html =~ "Test Settings"
      assert html =~ "Configure something."
      assert html =~ "Back to Settings"
      assert html =~ ~r/href="[^"]*\/users\/settings"/
      assert html =~ "hero-arrow-left"
      assert html =~ "Inner content"
      assert html =~ ~r/id="settings-content"/
    end
  end

  describe "config_list_card/1" do
    test "renders empty state when configs is empty" do
      html =
        render_component(
          fn assigns ->
            ~H"""
            <.config_list_card
              title="Your Configurations"
              empty_icon="hero-cog"
              empty_title="No configurations yet."
              empty_hint="Add one below."
              configs={[]}
            >
              <:item>never shown</:item>
            </.config_list_card>
            """
          end,
          %{}
        )

      assert html =~ "Your Configurations"
      assert html =~ "No configurations yet."
      assert html =~ "Add one below."
      assert html =~ "hero-cog"
      refute html =~ "never shown"
    end

    test "renders list of configs and passes each to item slot" do
      configs = [%{id: 1, name: "First"}, %{id: 2, name: "Second"}]

      html =
        render_component(
          fn assigns ->
            ~H"""
            <.config_list_card
              title="Your Configurations"
              empty_icon="hero-cog"
              empty_title="Empty"
              empty_hint="Hint"
              configs={@configs}
            >
              <:item :let={config}>
                <span id={"config-#{config.id}"}>{config.name}</span>
              </:item>
            </.config_list_card>
            """
          end,
          %{configs: configs}
        )

      assert html =~ "Your Configurations"
      refute html =~ "Empty"
      assert html =~ "First"
      assert html =~ "Second"
      assert html =~ ~r/id="config-1"/
      assert html =~ ~r/id="config-2"/
    end
  end
end
