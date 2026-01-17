defmodule Langler.Content.ReadabilityTest do
  use ExUnit.Case, async: true

  alias Langler.Content.Readability

  test "parse returns fallback content when nif is disabled" do
    html = "<p>Hello</p>"

    assert {:ok, result} = Readability.parse(html)
    assert result[:content] == html
    assert result[:length] == String.length(html)
  end

  test "parse returns an error for non-binary input" do
    assert {:error, :invalid_content} = Readability.parse(123, [])
  end
end
