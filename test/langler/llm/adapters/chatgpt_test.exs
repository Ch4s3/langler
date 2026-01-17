defmodule Langler.LLM.Adapters.ChatGPTTest do
  use ExUnit.Case, async: false

  alias Langler.LLM.Adapters.ChatGPT

  setup do
    original = Req.default_options()
    Req.default_options(plug: {Req.Test, __MODULE__})

    on_exit(fn ->
      Req.default_options(original)
    end)

    :ok
  end

  test "validate_config/1 requires an api key" do
    assert {:error, "API key is required"} = ChatGPT.validate_config(%{})
  end

  test "validate_config/1 falls back to the default model for invalid names" do
    assert {:ok, config} =
             ChatGPT.validate_config(%{
               api_key: " key ",
               model: "banana-model"
             })

    assert config.model == "gpt-4o-mini"
    assert config.api_key == "key"
  end

  test "chat/2 parses a successful response" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"content" => "OK"}}],
        "model" => "gpt-4o-mini",
        "usage" => %{
          "prompt_tokens" => 2,
          "completion_tokens" => 3,
          "total_tokens" => 5
        }
      })
    end)

    assert {:ok, response} =
             ChatGPT.chat([%{role: "user", content: "Hi"}], %{api_key: "key"})

    assert response.content == "OK"
    assert response.model == "gpt-4o-mini"
    assert response.token_count == 5
    assert response.usage.total_tokens == 5
  end

  test "chat/2 handles invalid api keys" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn = Plug.Conn.put_status(conn, 401)
      Req.Test.json(conn, %{"error" => %{"message" => "Unauthorized"}})
    end)

    assert {:error, :invalid_api_key} =
             ChatGPT.chat([%{role: "user", content: "Hi"}], %{api_key: "bad"})
  end

  test "chat/2 handles rate limits with retry-after" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn =
        conn
        |> Plug.Conn.put_status(429)
        |> Plug.Conn.put_resp_header("retry-after", "120")

      Req.Test.json(conn, %{"error" => %{"message" => "Too many requests"}})
    end)

    assert {:error, {:rate_limit_exceeded, 120}} =
             ChatGPT.chat([%{role: "user", content: "Hi"}], %{api_key: "key"})
  end

  test "chat/2 handles unexpected responses" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"unexpected" => "shape"})
    end)

    assert {:error, :invalid_response} =
             ChatGPT.chat([%{role: "user", content: "Hi"}], %{api_key: "key"})
  end
end
