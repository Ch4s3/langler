# Test the normalization function
alias Langler.Content.ArticleImporter

test_cases = [
  {"hello , world", "hello, world"},
  {"text \" , more", "text\", more"},
  {"\" text", "\"text"},
  {"text \" ,", "text\","},
]

IO.puts("Testing normalization function:\n")

Enum.each(test_cases, fn {input, expected} ->
  result = ArticleImporter.normalize_punctuation_spacing(input)
  status = if result == expected, do: "✓", else: "✗"
  IO.puts("#{status} Input:    #{inspect(input)}")
  IO.puts("  Expected: #{inspect(expected)}")
  IO.puts("  Got:      #{inspect(result)}")
  if result != expected do
    IO.puts("  DIFFERENT!")
  end
  IO.puts("")
end)
