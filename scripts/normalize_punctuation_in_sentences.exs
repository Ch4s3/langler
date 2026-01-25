# Script to normalize punctuation spacing in existing sentence content
# Usage: mix run scripts/normalize_punctuation_in_sentences.exs [article_id]
# If article_id is provided, only normalizes that article's sentences
# Otherwise, normalizes all sentences

alias Langler.Repo
alias Langler.Content.Sentence
alias Langler.Content.ArticleImporter
import Ecto.Query

# Get article_id from command line if provided
article_id_arg = System.argv() |> List.first()

query =
  if article_id_arg do
    article_id = String.to_integer(article_id_arg)
    from s in Sentence, where: s.article_id == ^article_id
  else
    from s in Sentence
  end

sentences = Repo.all(query)

IO.puts("Found #{length(sentences)} sentences to normalize...")

updated_count =
  Enum.reduce(sentences, 0, fn sentence, acc ->
    normalized = ArticleImporter.normalize_punctuation_spacing(sentence.content || "")

    if normalized != sentence.content do
      case Repo.update(Ecto.Changeset.change(sentence, content: normalized)) do
        {:ok, _} ->
          acc + 1

        {:error, changeset} ->
          IO.puts("Error updating sentence #{sentence.id}: #{inspect(changeset.errors)}")
          acc
      end
    else
      acc
    end
  end)

IO.puts("✓ Normalized #{updated_count} sentences")