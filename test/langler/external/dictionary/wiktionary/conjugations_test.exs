defmodule Langler.External.Dictionary.Wiktionary.ConjugationsTest do
  use ExUnit.Case, async: false

  alias Langler.External.Dictionary.Wiktionary.Conjugations

  setup do
    original = Req.default_options()
    Req.default_options(plug: {Req.Test, __MODULE__})

    cache_table = :wiktionary_conjugation_cache

    if :ets.whereis(cache_table) != :undefined do
      :ets.delete_all_objects(cache_table)
    end

    on_exit(fn ->
      Req.default_options(original)
    end)

    :ok
  end

  test "fetch_conjugations/2 parses tables and non-finite forms" do
    html = """
    <html>
      <body>
        <div id="mw-content-text">
          <div class="mw-parser-output">
            <h2><span class="mw-headline" id="Spanish">Spanish</span></h2>
            <div>
              <dl>
                <dt>infinitive</dt><dd>hablar</dd>
                <dt>gerund</dt><dd>hablando</dd>
                <dt>past participle</dt><dd>hablado</dd>
              </dl>
              <table class="wikitable">
                <tr>
                  <th>tense</th>
                  <th>yo</th>
                  <th>tú</th>
                  <th>él/ella/usted</th>
                  <th>nosotros/nosotras</th>
                  <th>vosotros/vosotras</th>
                  <th>ellos/ellas/ustedes</th>
                </tr>
                <tr>
                  <td>present</td>
                  <td>hablo</td>
                  <td>hablas</td>
                  <td>habla</td>
                  <td>hablamos</td>
                  <td>habláis</td>
                  <td>hablan</td>
                </tr>
              </table>
            </div>
          </div>
        </div>
      </body>
    </html>
    """

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.html(conn, html)
    end)

    assert {:ok, conjugations} = Conjugations.fetch_conjugations("hablar", "Spanish")

    assert conjugations["indicative"]["present"]["yo"] == "hablo"
  end

  test "fetch_conjugations/2 returns not_found when no tables are present" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.html(conn, "<html><body>No conjugations here</body></html>")
    end)

    assert {:error, :not_found} = Conjugations.fetch_conjugations("xyzzy", "Spanish")
  end
end
