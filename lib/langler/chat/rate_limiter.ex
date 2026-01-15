defmodule Langler.Chat.RateLimiter do
  @moduledoc """
  Rate limiting for chat LLM requests.

  Uses ETS for per-node tracking with the ability to swap to Redis/DB later.

  Rate limits:
  - 20 requests per minute per user
  - 500 requests per day per user
  - 200k tokens per day per user
  - 1 concurrent in-flight request per user
  """

  use GenServer
  require Logger

  @table_name :chat_rate_limits
  @cleanup_interval :timer.minutes(5)

  # Rate limits
  @requests_per_minute 20
  @requests_per_day 500
  @tokens_per_day 200_000
  @max_concurrent 2  # Allow 2 concurrent requests per user

  @type limit_type :: :requests_per_minute | :requests_per_day | :tokens_per_day | :concurrent

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Checks if a user can make a request based on the specified limit type.

  Returns `{:ok}` if allowed, or `{:error, :rate_limit_exceeded, retry_after_seconds}` if not.
  """
  @spec check_rate_limit(integer(), limit_type()) ::
          {:ok} | {:error, :rate_limit_exceeded, integer()}
  def check_rate_limit(user_id, limit_type) when is_integer(user_id) do
    case limit_type do
      :requests_per_minute ->
        check_limit(user_id, :rpm, @requests_per_minute, 60)

      :requests_per_day ->
        check_limit(user_id, :rpd, @requests_per_day, 86_400)

      :tokens_per_day ->
        check_token_limit(user_id)

      :concurrent ->
        check_concurrent_limit(user_id)
    end
  end

  @doc """
  Records a request for rate limiting purposes.
  """
  @spec track_request(integer()) :: :ok
  def track_request(user_id) when is_integer(user_id) do
    now = System.system_time(:second)

    # Track requests per minute
    :ets.insert(@table_name, {{user_id, :rpm, now}, 1})

    # Track requests per day
    :ets.insert(@table_name, {{user_id, :rpd, now}, 1})

    :ok
  end

  @doc """
  Tracks token usage for a user.
  """
  @spec track_tokens(integer(), integer()) :: :ok
  def track_tokens(user_id, token_count) when is_integer(user_id) and is_integer(token_count) do
    now = System.system_time(:second)
    day_key = div(now, 86_400)

    case :ets.lookup(@table_name, {user_id, :tokens, day_key}) do
      [] ->
        :ets.insert(@table_name, {{user_id, :tokens, day_key}, token_count})

      [{_key, current}] ->
        :ets.update_element(@table_name, {user_id, :tokens, day_key}, {2, current + token_count})
    end

    :ok
  end

  @doc """
  Marks the start of a concurrent request for a user.
  Returns the new count.
  """
  @spec start_concurrent_request(integer()) :: integer()
  def start_concurrent_request(user_id) when is_integer(user_id) do
    case :ets.lookup(@table_name, {user_id, :concurrent}) do
      [] ->
        :ets.insert(@table_name, {{user_id, :concurrent}, 1})
        1

      [{_key, count}] when is_integer(count) ->
        new_count = count + 1
        :ets.update_element(@table_name, {user_id, :concurrent}, {2, new_count})
        new_count

      # Handle legacy boolean entries (migrate to count)
      [{_key, true}] ->
        :ets.update_element(@table_name, {user_id, :concurrent}, {2, 1})
        1

      [{_key, _value}] ->
        # Unknown format, reset to 1
        :ets.update_element(@table_name, {user_id, :concurrent}, {2, 1})
        1
    end
  end

  @doc """
  Marks the end of a concurrent request for a user.
  """
  @spec end_concurrent_request(integer()) :: :ok
  def end_concurrent_request(user_id) when is_integer(user_id) do
    case :ets.lookup(@table_name, {user_id, :concurrent}) do
      [] ->
        :ok

      [{_key, count}] when is_integer(count) and count > 1 ->
        :ets.update_element(@table_name, {user_id, :concurrent}, {2, count - 1})
        :ok

      [{_key, 1}] ->
        :ets.delete(@table_name, {user_id, :concurrent})
        :ok

      # Handle legacy boolean entries
      [{_key, true}] ->
        :ets.delete(@table_name, {user_id, :concurrent})
        :ok

      [{_key, _value}] ->
        # Unknown format, just delete it
        :ets.delete(@table_name, {user_id, :concurrent})
        :ok
    end
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    :ets.new(@table_name, [:named_table, :public, :set, {:write_concurrency, true}])
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_old_entries()
    schedule_cleanup()
    {:noreply, state}
  end

  ## Private Functions

  defp check_limit(user_id, type, max_count, window_seconds) do
    now = System.system_time(:second)
    cutoff = now - window_seconds

    # Count requests in the time window
    count =
      :ets.select_count(@table_name, [
        {{{user_id, type, :"$1"}, :_}, [{:>=, :"$1", cutoff}], [true]}
      ])

    if count >= max_count do
      # Calculate retry_after based on oldest request
      oldest_time =
        case :ets.select(@table_name, [
               {{{user_id, type, :"$1"}, :_}, [{:>=, :"$1", cutoff}], [:"$1"]}
             ]) do
          [] -> now
          times -> Enum.min(times)
        end

      retry_after = max(1, oldest_time + window_seconds - now)
      {:error, :rate_limit_exceeded, retry_after}
    else
      {:ok}
    end
  end

  defp check_token_limit(user_id) do
    now = System.system_time(:second)
    day_key = div(now, 86_400)

    tokens_used =
      case :ets.lookup(@table_name, {user_id, :tokens, day_key}) do
        [] -> 0
        [{_key, count}] -> count
      end

    if tokens_used >= @tokens_per_day do
      # Calculate seconds until next day
      next_day_start = (day_key + 1) * 86_400
      retry_after = next_day_start - now
      {:error, :rate_limit_exceeded, retry_after}
    else
      {:ok}
    end
  end

  defp check_concurrent_limit(user_id) do
    case :ets.lookup(@table_name, {user_id, :concurrent}) do
      [] ->
        {:ok}

      [{_key, count}] when is_integer(count) and count >= @max_concurrent ->
        {:error, :rate_limit_exceeded, 1}

      # Handle legacy boolean entries (treat as 1 concurrent request)
      [{_key, true}] ->
        {:ok}

      [{_key, _value}] ->
        # Unknown format, allow it (will be cleaned up on next start/end)
        {:ok}
    end
  end

  defp cleanup_old_entries do
    now = System.system_time(:second)

    # Clean up rpm entries older than 1 minute
    rpm_cutoff = now - 60

    rpm_count =
      :ets.select_delete(@table_name, [
        {{{:_, :rpm, :"$1"}, :_}, [{:<, :"$1", rpm_cutoff}], [true]}
      ])

    # Clean up rpd entries older than 1 day
    rpd_cutoff = now - 86_400

    rpd_count =
      :ets.select_delete(@table_name, [
        {{{:_, :rpd, :"$1"}, :_}, [{:<, :"$1", rpd_cutoff}], [true]}
      ])

    # Clean up token entries older than 2 days
    token_cutoff_day = div(now, 86_400) - 2

    token_count =
      :ets.select_delete(@table_name, [
        {{{:_, :tokens, :"$1"}, :_}, [{:<, :"$1", token_cutoff_day}], [true]}
      ])

    if rpm_count + rpd_count + token_count > 0 do
      Logger.debug(
        "RateLimiter cleanup: removed #{rpm_count} rpm, #{rpd_count} rpd, #{token_count} token entries"
      )
    end

    :ok
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
