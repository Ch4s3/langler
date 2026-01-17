defmodule Langler.External.Dictionary.Cache do
  @moduledoc """
  ETS-backed cache with optional persistent storage for dictionary lookups.

  Provides high-performance caching for dictionary entries using ETS tables
  with the ability to persist cache entries to the database for durability.
  """

  alias Langler.External.Dictionary.PersistentCache
  require Logger

  @default_ttl :timer.hours(12)
  @config Application.compile_env(:langler, __MODULE__, [])
  @persistent_tables Keyword.get(@config, :persistent_tables, [])

  @doc """
  Returns {:ok, value} if the cache contains a non-expired entry for `key`.
  """
  @spec get(atom(), term()) :: {:ok, term()} | :miss
  def get(table, key) when is_atom(table) do
    ensure_table(table)
    now = current_time()

    case :ets.lookup(table, key) do
      [{^key, value, expires_at}] when expires_at > now ->
        {:ok, value}

      [{^key, _value, _expires_at}] ->
        :ets.delete(table, key)
        fetch_from_store(table, key, now)

      _ ->
        fetch_from_store(table, key, now)
    end
  end

  @doc """
  Inserts `value` into the cache for `key`, respecting the provided TTL (defaults to 12h).
  """
  @spec put(atom(), term(), term(), keyword()) :: :ok
  def put(table, key, value, opts \\ []) when is_atom(table) do
    ensure_table(table)
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    persist? = Keyword.get(opts, :persist, true)
    expires_at = current_time() + ttl
    :ets.insert(table, {key, value, expires_at})

    if persist? && persistent?(table) do
      persist_entry(table, key, value, expires_at)
    end

    :ok
  end

  @doc """
  Fetches an entry from cache or computes/stores it via `fun`.
  """
  @spec get_or_store(atom(), term(), keyword(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def get_or_store(table, key, opts \\ [], fun) when is_function(fun, 0) do
    case get(table, key) do
      {:ok, value} ->
        {:ok, value}

      :miss ->
        case fun.() do
          {:ok, value} = ok ->
            put(table, key, value, opts)
            ok

          error ->
            error
        end
    end
  end

  @doc """
  Returns the list of tables configured to use persistent storage.
  """
  def persistent_tables, do: @persistent_tables

  defp fetch_from_store(table, key, now) do
    if persistent?(table) do
      case PersistentCache.fetch(table, key) do
        {:ok, %{value: value, expires_at_ms: expires_at}} when expires_at > now ->
          ttl = expires_at - now
          put(table, key, value, ttl: ttl, persist: false)
          {:ok, value}

        _ ->
          :miss
      end
    else
      :miss
    end
  end

  defp persistent?(table), do: table in @persistent_tables

  defp persist_entry(table, key, value, expires_at) do
    case PersistentCache.store(table, key, value, expires_at) do
      {:error, reason} ->
        Logger.warning("Dictionary cache persistence failed: #{inspect(reason)}")

      _ ->
        :ok
    end
  end

  defp ensure_table(table) do
    case :ets.whereis(table) do
      :undefined ->
        :ets.new(table, [
          :named_table,
          :set,
          :public,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ ->
        :ok
    end
  end

  defp current_time, do: System.system_time(:millisecond)
end
