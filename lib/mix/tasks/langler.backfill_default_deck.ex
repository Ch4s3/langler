defmodule Mix.Tasks.Langler.BackfillDefaultDeck do
  @moduledoc """
  Ensures all study cards (fsrs_items) for a user are in their default deck.

  Inserts missing DeckWord rows so every word the user has in study is also
  in their default deck. Use this to fix legacy data where words were added
  to study before the deck system or without being added to the default deck.

  ## Usage

      # Backfill for a single user by email
      mix langler.backfill_default_deck test@example.com

      # Backfill for all users
      mix langler.backfill_default_deck
  """
  use Mix.Task

  alias Langler.Accounts
  alias Langler.Repo
  alias Langler.Vocabulary
  import Ecto.Query

  @shortdoc "Moves legacy study cards into each user's default deck"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    email = List.first(args)

    if email do
      backfill_user(email)
    else
      backfill_all_users()
    end
  end

  defp backfill_user(email) do
    case Accounts.get_user_by_email(email) do
      nil ->
        Mix.shell().error("User not found: #{email}")
        System.halt(1)

      user ->
        Mix.shell().info("Backfilling default deck for #{email} (user_id=#{user.id})...")

        case Vocabulary.backfill_default_deck_for_user(user.id) do
          {:ok, 0} ->
            Mix.shell().info("  No missing cards; default deck already up to date.")

          {:ok, count} ->
            Mix.shell().info("  Added #{count} word(s) to the default deck.")

          {:error, reason} ->
            Mix.shell().error("  Failed: #{inspect(reason)}")
            System.halt(1)
        end
    end
  end

  defp backfill_all_users do
    user_ids =
      from(u in Langler.Accounts.User, select: {u.id, u.email})
      |> Repo.all()

    Mix.shell().info("Backfilling default deck for #{length(user_ids)} user(s)...")

    results =
      Enum.map(user_ids, fn {id, email} ->
        case Vocabulary.backfill_default_deck_for_user(id) do
          {:ok, count} -> {:ok, email, count}
          {:error, reason} -> {:error, email, reason}
        end
      end)

    {oks, errs} = Enum.split_with(results, &match?({:ok, _, _}, &1))
    added = Enum.sum(Enum.map(oks, fn {:ok, _, c} -> c end))

    Enum.each(oks, fn {:ok, email, count} ->
      if count > 0, do: Mix.shell().info("  #{email}: added #{count}")
    end)

    if errs != [] do
      Mix.shell().error("  Errors:")

      Enum.each(errs, fn {:error, email, reason} ->
        Mix.shell().error("    #{email}: #{inspect(reason)}")
      end)
    end

    Mix.shell().info("Total: #{added} word(s) added across all users.")
  end
end
