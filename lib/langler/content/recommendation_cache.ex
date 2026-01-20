defmodule Langler.Content.RecommendationCache do
  @moduledoc """
  ETS-based cache for recommendation counts with TTL expiration.

  Caches the count of recommended articles per user to avoid expensive
  scoring computations on every page load. The cache automatically expires
  after a configurable TTL (default 5 minutes).

  ## Usage

      # Get cached count (returns :miss if not cached or expired)
      case RecommendationCache.get_count(user_id) do
        {:ok, count} -> count
        :miss -> compute_and_cache(user_id)
      end

      # Cache a computed count
      RecommendationCache.put_count(user_id, 42)

      # Invalidate when articles change
      RecommendationCache.invalidate(user_id)
  """

  use GenServer

  @table :recommendation_cache
  @ttl_seconds 300

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
  Gets the cached recommendation count for a user.

  Returns `{:ok, count}` if cached and not expired, or `:miss` otherwise.
  """
  @spec get_count(integer()) :: {:ok, non_neg_integer()} | :miss
  def get_count(user_id) do
    ensure_table()
    now = System.system_time(:second)

    case :ets.lookup(@table, {:count, user_id}) do
      [{_, count, expires_at}] when expires_at > now ->
        {:ok, count}

      _ ->
        :miss
    end
  end

  @doc """
  Caches the recommendation count for a user.

  Returns the count for convenient piping.
  """
  @spec put_count(integer(), non_neg_integer()) :: non_neg_integer()
  def put_count(user_id, count) do
    ensure_table()
    expires_at = System.system_time(:second) + ttl_seconds()
    :ets.insert(@table, {{:count, user_id}, count, expires_at})
    count
  end

  @doc """
  Invalidates the cached count for a user.

  Call this when the user imports, deletes, or otherwise modifies their articles.
  """
  @spec invalidate(integer()) :: :ok
  def invalidate(user_id) do
    ensure_table()
    :ets.delete(@table, {:count, user_id})
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
