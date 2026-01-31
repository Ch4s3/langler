defmodule Langler.Repo.Migrations.AddIdiomDetection do
  use Ecto.Migration

  def change do
    alter table(:words) do
      add :is_idiom, :boolean, null: false, default: false
    end

    create table(:idiom_occurrences) do
      add :start_position, :integer, null: false
      add :end_position, :integer, null: false
      add :word_id, references(:words, on_delete: :delete_all), null: false
      add :sentence_id, references(:sentences, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:idiom_occurrences, [:sentence_id])
    create index(:idiom_occurrences, [:word_id])

    create unique_index(
             :idiom_occurrences,
             [:sentence_id, :word_id, :start_position, :end_position],
             name: :idiom_occurrences_sentence_word_span_index
           )

    alter table(:user_preferences) do
      add :auto_detect_idioms, :boolean, null: false, default: false
    end
  end
end
