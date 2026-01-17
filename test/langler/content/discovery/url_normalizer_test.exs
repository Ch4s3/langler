defmodule Langler.Content.Discovery.UrlNormalizerTest do
  use ExUnit.Case, async: true

  alias Langler.Content.Discovery.UrlNormalizer

  describe "normalize/2" do
    test "strips tracking parameters and keeps other query params" do
      assert {:ok, normalized} =
               UrlNormalizer.normalize(
                 "https://example.com/path?utm_source=newsletter&x=1&gclid=abc"
               )

      assert normalized == "https://example.com/path?x=1"
    end

    test "resolves relative urls against a base" do
      assert {:ok, normalized} =
               UrlNormalizer.normalize(
                 "/articles/123?utm_campaign=spring",
                 "https://example.com/base"
               )

      assert normalized == "https://example.com/articles/123"
    end

    test "rejects invalid schemes" do
      assert {:error, :invalid_scheme} = UrlNormalizer.normalize("ftp://example.com/file")
    end
  end

  describe "matches_patterns?/2" do
    test "allows when allow patterns match and deny does not" do
      config = %{"allow_patterns" => ["example.com/articles"], "deny_patterns" => ["private"]}

      assert UrlNormalizer.matches_patterns?("https://example.com/articles/123", config)
      refute UrlNormalizer.matches_patterns?("https://example.com/private/articles/123", config)
    end

    test "defaults to allow when allow list is empty" do
      config = %{"allow_patterns" => [], "deny_patterns" => ["blocked"]}

      assert UrlNormalizer.matches_patterns?("https://example.com/articles/123", config)
      refute UrlNormalizer.matches_patterns?("https://example.com/blocked/1", config)
    end
  end
end
