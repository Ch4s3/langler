defmodule Langler.Content.ReadabilityTest do
  use ExUnit.Case, async: true

  alias Langler.Content.Readability

  test "parse returns fallback content when nif is disabled" do
    Application.put_env(:langler, Readability, use_nif: false)

    on_exit(fn ->
      Application.delete_env(:langler, Readability)
    end)

    html = "<p>Hello</p>"

    assert {:ok, result} = Readability.parse(html)
    assert result[:content] == html
    assert result[:length] == String.length(html)
  end

  test "parse returns an error for non-binary input" do
    assert {:error, :invalid_content} = Readability.parse(123, [])
  end

  test "parse surfaces nif errors when the nif is requested" do
    Application.put_env(:langler, Readability, use_nif: true)

    on_exit(fn ->
      Application.delete_env(:langler, Readability)
    end)

    assert {:error, reason} = Readability.parse("<p>Hola</p>")
    assert is_binary(reason) or match?(%ErlangError{}, reason)
  end
end
