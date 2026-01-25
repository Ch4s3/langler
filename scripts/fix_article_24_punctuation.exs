# Script to fix punctuation spacing in article 24
alias Langler.Repo
alias Langler.Content.Sentence
alias Langler.Content.Article
alias Langler.Content.ArticleImporter
import Ecto.Query

article_id = 24

IO.puts("Fixing punctuation spacing for article #{article_id}...")

# Get all sentences for this article
sentences = Repo.all(from s in Sentence, where: s.article_id == ^article_id, order_by: s.position)

IO.puts("Found #{length(sentences)} sentences")

updated_count =
  Enum.reduce(sentences, 0, fn sentence, acc ->
    # Normalize the content
    normalized = ArticleImporter.normalize_punctuation_spacing(sentence.content || "")

    if normalized != sentence.content do
      case Repo.update(Ecto.Changeset.change(sentence, content: normalized)) do
        {:ok, _} ->
          IO.puts("  Updated sentence #{sentence.id} (position #{sentence.position})")
          acc + 1

        {:error, changeset} ->
          IO.puts("  Error updating sentence #{sentence.id}: #{inspect(changeset.errors)}")
          acc
      end
    else
      acc
    end
  end)

# Also update the article content itself
article = Repo.get(Article, article_id)
if article do
  normalized_content = ArticleImporter.normalize_punctuation_spacing(article.content || "")

  if normalized_content != article.content do
    case Repo.update(Ecto.Changeset.change(article, content: normalized_content)) do
      {:ok, _} ->
        IO.puts("  Updated article content")
      {:error, changeset} ->
        IO.puts("  Error updating article: #{inspect(changeset.errors)}")
    end
  end
end

IO.puts("✓ Fixed #{updated_count} sentences")
