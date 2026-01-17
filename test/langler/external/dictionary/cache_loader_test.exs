defmodule Langler.External.Dictionary.CacheLoaderTest do
  use Langler.DataCase, async: false

  alias Langler.External.Dictionary.{Cache, CacheLoader}

  test "warms configured persistent tables" do
    tables = Cache.persistent_tables()
    {:ok, pid} = start_supervised(CacheLoader)

    send(pid, :warm)
    Process.sleep(10)

    Enum.each(tables, fn table ->
      assert :ets.whereis(table) != :undefined
    end)
  end
end
