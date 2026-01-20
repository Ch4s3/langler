defmodule Langler.Study.LevelCache do
  @moduledoc """
  ETS-based cache for user vocabulary levels with TTL expiration.

  Caches the vocabulary level calculation per user to avoid expensive
  computations on every page load. The cache automatically expires
  after a configurable TTL (default 10 minutes).

  ## Usage

      # Get cached level (returns :miss if not cached or expired)
      case LevelCache.get_level(user_id) do
        {:ok, level} -> level
        :miss -> compute_and_cache(user_id)
      end

      # Cache a computed level
      LevelCache.put_level(user_id, %{cefr_level: "B1", numeric_level: 4.5})

      # Invalidate when user reviews words or adds items
      LevelCache.invalidate(user_id)
  """

  use GenServer

  @table :user_level_cache
  @ttl_seconds 600

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the cache GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the cached vocabulary level for a user.

  Returns `{:ok, level}` if cached and not expired, or `:miss` otherwise.
  """
  @spec get_level(integer()) :: {:ok, map()} | :miss
  def get_level(user_id) do
    ensure_table()
    now = System.system_time(:second)

    case :ets.lookup(@table, {:level, user_id}) do
      [{_, level, expires_at}] when expires_at > now ->
        {:ok, level}

      _ ->
        :miss
    end
  end

  @doc """
  Caches the vocabulary level for a user.

  Returns the level for convenient piping.
  """
  @spec put_level(integer(), map()) :: map()
  def put_level(user_id, level) do
    ensure_table()
    expires_at = System.system_time(:second) + ttl_seconds()
    :ets.insert(@table, {{:level, user_id}, level, expires_at})
    level
  end

  @doc """
  Invalidates the cached level for a user.

  Call this when the user reviews words or adds new study items.
  """
  @spec invalidate(integer()) :: :ok
  def invalidate(user_id) do
    ensure_table()
    :ets.delete(@table, {:level, user_id})
    :ok
  end

  @doc """
  Clears all cached entries. Useful for testing.
  """
  @spec clear_all() :: :ok
  def clear_all do
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  @doc """
  Returns the ETS table name. Useful for testing.
  """
  @spec table_name() :: atom()
  def table_name, do: @table

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :public, :set, {:read_concurrency, true}])
    {:ok, %{table: table}}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, {:read_concurrency, true}])

      _table ->
        :ok
    end
  end

  defp ttl_seconds do
    Application.get_env(:langler, __MODULE__, [])
    |> Keyword.get(:ttl_seconds, @ttl_seconds)
  end
end
