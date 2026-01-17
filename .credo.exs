%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "config/", "priv/"],
        excluded: [
          "test/",
          "deps/",
          "_build/",
          "assets/"
        ]
      },
      checks: [
        {Credo.Check.Readability.ModuleDoc, false}
      ]
    }
  ]
}
