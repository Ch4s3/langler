defmodule Langler.Chat.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Langler.Chat.RateLimiter

  setup do
    if :ets.whereis(:chat_rate_limits) == :undefined do
      {:ok, _pid} = RateLimiter.start_link([])
    end

    :ets.delete_all_objects(:chat_rate_limits)
    :ok
  end

  test "enforces request and token limits" do
    user_id = 1

    assert RateLimiter.check_rate_limit(user_id, :requests_per_minute) == {:ok}

    RateLimiter.track_request(user_id)

    now = System.system_time(:second)

    Enum.each(0..19, fn offset ->
      :ets.insert(:chat_rate_limits, {{user_id, :rpm, now - offset}, 1})
    end)

    assert {:error, :rate_limit_exceeded, _} =
             RateLimiter.check_rate_limit(user_id, :requests_per_minute)

    assert RateLimiter.check_rate_limit(user_id, :requests_per_day) == {:ok}

    RateLimiter.track_tokens(user_id, 199_000)
    assert RateLimiter.check_rate_limit(user_id, :tokens_per_day) == {:ok}

    RateLimiter.track_tokens(user_id, 1_000)

    assert {:error, :rate_limit_exceeded, _} =
             RateLimiter.check_rate_limit(user_id, :tokens_per_day)
  end

  test "tracks concurrent requests and handles legacy entries" do
    user_id = 2

    assert RateLimiter.check_rate_limit(user_id, :concurrent) == {:ok}
    assert RateLimiter.start_concurrent_request(user_id) == 1
    assert RateLimiter.start_concurrent_request(user_id) == 2

    assert {:error, :rate_limit_exceeded, _} =
             RateLimiter.check_rate_limit(user_id, :concurrent)

    RateLimiter.end_concurrent_request(user_id)
    assert RateLimiter.check_rate_limit(user_id, :concurrent) == {:ok}

    legacy_user = 3
    :ets.insert(:chat_rate_limits, {{legacy_user, :concurrent}, true})

    assert RateLimiter.start_concurrent_request(legacy_user) == 1
    RateLimiter.end_concurrent_request(legacy_user)
    assert RateLimiter.check_rate_limit(legacy_user, :concurrent) == {:ok}
  end
end
