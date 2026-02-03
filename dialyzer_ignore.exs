# dialyzer_ignore.exs
[
  ~r/^test\/.*/,
  # Mix task: Mix.Task/Mix.shell not in PLT
  %{file: "lib/mix/tasks/langler.gettext.seed.ex"}
]
