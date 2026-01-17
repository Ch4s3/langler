defmodule Langler.External.Dictionary.CacheLoader do
  @moduledoc """
  GenServer for loading dictionary cache entries from the database.
  """

  use GenServer
  require Logger

  alias Langler.External.Dictionary.{Cache, PersistentCache}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    state = %{auto_warm?: Keyword.get(opts, :auto_warm, true)}

    if state.auto_warm? do
      Process.send_after(self(), :warm, 0)
    end

    {:ok, state}
  end

  def warm(pid \\ __MODULE__) do
    GenServer.call(pid, :warm)
  end

  @impl true
  def handle_info(:warm, state) do
    warm_all_tables()
    {:noreply, state}
  end

  @impl true
  def handle_call(:warm, _from, state) do
    warm_all_tables()
    {:reply, :ok, state}
  end

  defp warm_all_tables do
    Enum.each(Cache.persistent_tables(), &warm_table/1)
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
