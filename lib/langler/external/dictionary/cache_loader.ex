defmodule Langler.External.Dictionary.CacheLoader do
  @moduledoc """
  GenServer for loading dictionary cache entries from the database.
  """

  use GenServer
  require Logger

  alias Langler.External.Dictionary.{Cache, PersistentCache}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    Process.send_after(self(), :warm, 0)
    {:ok, state}
  end

  @impl true
  def handle_info(:warm, state) do
    Enum.each(Cache.persistent_tables(), &warm_table/1)
    {:noreply, state}
  end

  defp warm_table(table) do
    Logger.debug("Dictionary cache loader: warming #{table}")
    Cache.put(table, :__cache_loader_probe__, :probe, ttl: 1, persist: false)
    :ets.delete(table, :__cache_loader_probe__)

    PersistentCache.stream_active_entries(table, fn {key, value, expires_at_ms} ->
      ttl = expires_at_ms - System.system_time(:millisecond)

      if ttl > 0 do
        Cache.put(table, key, value, ttl: ttl, persist: false)
      end
    end)

    loaded =
      case :ets.whereis(table) do
        :undefined -> 0
        tid -> :ets.info(tid, :size)
      end

    Logger.debug("Dictionary cache loader: #{table} warm complete (#{loaded} entries)")
  end
end
