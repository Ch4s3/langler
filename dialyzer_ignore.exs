# dialyzer_ignore.exs
[
  ~r/^test\/.*/,
  # Mix tasks: Mix.Task/Mix.shell not in PLT
  %{file: "lib/mix/tasks/langler.gettext.seed.ex"},
  %{file: "lib/mix/tasks/langler.backfill_default_deck.ex"}
]
