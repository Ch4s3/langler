# Test with the EXACT text the user showed
alias Langler.Content.ArticleImporter

bad_text = " \" Elegimos el comercio justo sobre los aranceles ; elegimos una asociación de largo plazo sobre el aislamiento \" , subrayó la presidenta de la Comisión Europea , Ursula Von der Leyen , ante los 800 asistentes al elegante Teatro José Asunción Flores del Banco Central de Paraguay , en Asunción ."

normalized = ArticleImporter.normalize_punctuation_spacing(bad_text)

IO.puts("INPUT:")
IO.puts(bad_text)
IO.puts("")
IO.puts("OUTPUT:")
IO.puts(normalized)
IO.puts("")
IO.puts("EXPECTED:")
IO.puts("\"Elegimos el comercio justo sobre los aranceles; elegimos una asociación de largo plazo sobre el aislamiento\", subrayó la presidenta de la Comisión Europea, Ursula Von der Leyen, ante los 800 asistentes al elegante Teatro José Asunción Flores del Banco Central de Paraguay, en Asunción.")
