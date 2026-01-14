# Script to refresh an article and apply punctuation spacing fix
alias Langler.Repo
alias Langler.Content.Article
alias Langler.Content.ArticleImporter
alias Langler.Accounts

article_id = System.argv() |> List.first() |> String.to_integer()

# Get article
article = Repo.get(Article, article_id)

if article do
  IO.puts("Article #{article_id}:")
  IO.puts("  Title: #{article.title}")
  IO.puts("  URL: #{article.url}")

  # Check for spacing issues before refresh
  if article.content do
    issues_before = Regex.scan(~r/[^\s]+\s+[,\.;:!?]/, article.content)
    |> Enum.take(5)

    IO.puts("\nBefore refresh - Found #{length(issues_before)} examples of spacing issues:")
    Enum.each(issues_before, fn [match] ->
      IO.puts("  '#{match}'")
    end)
  end

  # Get a user to refresh the article
  user = Repo.one(from u in Langler.Accounts.User, limit: 1)

  if user do
    IO.puts("\nRefreshing article to apply punctuation spacing fix...")
    case ArticleImporter.import_from_url(user, article.url) do
      {:ok, refreshed, _status} ->
        IO.puts("✓ Article refreshed successfully")

        # Check if spacing issues are fixed
        if refreshed.content do
          issues_after = Regex.scan(~r/[^\s]+\s+[,\.;:!?]/, refreshed.content)
          |> Enum.take(5)

          IO.puts("\nAfter refresh - Found #{length(issues_after)} examples of spacing issues:")
          if length(issues_after) > 0 do
            Enum.each(issues_after, fn [match] ->
              IO.puts("  '#{match}'")
            end)
          else
            IO.puts("  (none found - fix applied successfully!)")
          end

          # Show a sample of the fixed content
          IO.puts("\nSample of fixed content (first 300 chars):")
          IO.puts(String.slice(refreshed.content, 0, 300))
        end
      {:error, reason} ->
        IO.puts("✗ Error refreshing: #{inspect(reason)}")
    end
  else
    IO.puts("\nNo user found to refresh article")
  end
else
  IO.puts("Article #{article_id} not found")
end
