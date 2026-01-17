defmodule Langler.ReleaseTest do
  use ExUnit.Case, async: false

  test "migrate returns an empty list when no repos are configured" do
    original_repos = Application.fetch_env!(:langler, :ecto_repos)
    Application.put_env(:langler, :ecto_repos, [])

    on_exit(fn ->
      Application.put_env(:langler, :ecto_repos, original_repos)
    end)

    assert [] = Langler.Release.migrate()
  end
end
