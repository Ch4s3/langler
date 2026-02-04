defmodule Langler.Vocabulary.Decks do
  @moduledoc """
  Context for deck management operations.

  Handles deck CRUD, following, sharing, copying, and deck membership
  (both words and custom cards).
  """

  import Ecto.Query, warn: false
  alias Langler.Repo

  alias Langler.Vocabulary.{
    CustomCard,
    Deck,
    DeckCustomCard,
    DeckFollow,
    DeckShare,
    DeckWord
  }

  ## Deck CRUD

  @doc """
  Gets a deck with preloaded words and custom cards.
  """
  def get_deck_with_contents(deck_id, viewer_user_id) do
    case get_deck_for_viewer(deck_id, viewer_user_id) do
      nil ->
        nil

      deck ->
        deck
        |> Repo.preload([:words, :custom_cards])
    end
  end

  @doc """
  Lists all decks for a user with preloaded words count.
  """
  def list_decks_with_words(user_id) do
    from(d in Deck,
      where: d.user_id == ^user_id,
      left_join: dw in DeckWord,
      on: dw.deck_id == d.id,
      group_by: d.id,
      select: %{
        id: d.id,
        name: d.name,
        description: d.description,
        visibility: d.visibility,
        language: d.language,
        is_default: d.is_default,
        user_id: d.user_id,
        inserted_at: d.inserted_at,
        updated_at: d.updated_at,
        word_count: count(dw.id)
      },
      order_by: [desc: d.is_default, asc: d.name]
    )
    |> Repo.all()
  end

  @doc """
  Lists public decks with pagination and search.

  ## Options
  - `:search` - search query for deck name/description
  - `:language` - filter by language
  - `:limit` - max results (default: 50)
  - `:offset` - pagination offset (default: 0)
  - `:sort` - :popular (follower count), :recent, :name (default: :popular)
  """
  def list_public_decks(opts \\ []) do
    search = Keyword.get(opts, :search)
    language = Keyword.get(opts, :language)
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    sort = Keyword.get(opts, :sort, :popular)

    query =
      from(d in Deck,
        where: d.visibility == "public",
        left_join: df in DeckFollow,
        on: df.deck_id == d.id,
        left_join: u in assoc(d, :user),
        group_by: [d.id, u.id],
        select: %{
          deck: d,
          owner: u,
          follower_count: count(df.id)
        }
      )

    query =
      if search && String.trim(search) != "" do
        search_term = "%#{search}%"
        where(query, [d], ilike(d.name, ^search_term) or ilike(d.description, ^search_term))
      else
        query
      end

    query =
      if language do
        where(query, [d], d.language == ^language)
      else
        query
      end

    query =
      case sort do
        :popular -> order_by(query, [d, u, df], desc: count(df.id), asc: d.name)
        :recent -> order_by(query, [d], desc: d.inserted_at)
        :name -> order_by(query, [d], asc: d.name)
        _ -> order_by(query, [d, u, df], desc: count(df.id), asc: d.name)
      end

    query
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Lists decks that a user is following.
  """
  def list_followed_decks(user_id) do
    from(df in DeckFollow,
      where: df.user_id == ^user_id,
      join: d in assoc(df, :deck),
      join: u in assoc(d, :user),
      left_join: dfc in DeckFollow,
      on: dfc.deck_id == d.id,
      group_by: [d.id, u.id, df.id],
      select: %{
        deck: d,
        owner: u,
        follower_count: count(dfc.id),
        followed_at: df.inserted_at
      },
      order_by: [desc: df.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Lists decks explicitly shared with a user.
  """
  def list_shared_decks_for_user(user_id) do
    from(ds in DeckShare,
      where: ds.shared_with_user_id == ^user_id,
      join: d in assoc(ds, :deck),
      join: u in assoc(d, :user),
      select: %{
        deck: d,
        owner: u,
        permission: ds.permission,
        shared_at: ds.inserted_at
      },
      order_by: [desc: ds.inserted_at]
    )
    |> Repo.all()
  end

  ## Following

  @doc """
  Follows a public deck. Idempotent.
  """
  def follow_deck(deck_id, user_id) do
    deck = Repo.get(Deck, deck_id)

    cond do
      is_nil(deck) ->
        {:error, :deck_not_found}

      deck.visibility != "public" ->
        {:error, :deck_not_public}

      deck.user_id == user_id ->
        {:error, :cannot_follow_own_deck}

      true ->
        %DeckFollow{}
        |> DeckFollow.changeset(%{deck_id: deck_id, user_id: user_id})
        |> Repo.insert(on_conflict: :nothing)
        |> case do
          {:ok, follow} -> {:ok, follow}
          _ -> {:ok, :already_following}
        end
    end
  end

  @doc """
  Unfollows a deck.
  """
  def unfollow_deck(deck_id, user_id) do
    case Repo.get_by(DeckFollow, deck_id: deck_id, user_id: user_id) do
      nil -> {:error, :not_following}
      follow -> Repo.delete(follow)
    end
  end

  @doc """
  Checks if a user is following a deck.
  """
  def following_deck?(deck_id, user_id) do
    Repo.exists?(from df in DeckFollow, where: df.deck_id == ^deck_id and df.user_id == ^user_id)
  end

  @doc """
  Converts a followed deck into a personal copy (freeze/snapshot).
  Removes the follow and creates a new deck owned by the user.
  """
  def freeze_followed_deck(deck_id, user_id) do
    Repo.transaction(fn ->
      follow = Repo.get_by(DeckFollow, deck_id: deck_id, user_id: user_id)

      if is_nil(follow) do
        Repo.rollback(:not_following)
      else
        perform_freeze(deck_id, user_id, follow)
      end
    end)
  end

  defp perform_freeze(deck_id, user_id, follow) do
    case copy_deck_to_user(deck_id, user_id) do
      {:ok, new_deck} ->
        Repo.delete!(follow)
        new_deck

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  ## Sharing

  @doc """
  Shares a deck with a specific user.
  """
  def share_deck(deck_id, owner_id, target_user_id, permission \\ "view") do
    deck = Repo.get_by(Deck, id: deck_id, user_id: owner_id)

    cond do
      is_nil(deck) ->
        {:error, :deck_not_found}

      owner_id == target_user_id ->
        {:error, :cannot_share_with_self}

      true ->
        %DeckShare{}
        |> DeckShare.changeset(%{
          deck_id: deck_id,
          shared_with_user_id: target_user_id,
          permission: permission
        })
        |> Repo.insert()
    end
  end

  @doc """
  Removes a share.
  """
  def unshare_deck(deck_id, shared_with_user_id) do
    case Repo.get_by(DeckShare, deck_id: deck_id, shared_with_user_id: shared_with_user_id) do
      nil -> {:error, :share_not_found}
      share -> Repo.delete(share)
    end
  end

  @doc """
  Updates share permission.
  """
  def update_share_permission(deck_id, shared_with_user_id, permission) do
    case Repo.get_by(DeckShare, deck_id: deck_id, shared_with_user_id: shared_with_user_id) do
      nil ->
        {:error, :share_not_found}

      share ->
        share
        |> DeckShare.changeset(%{permission: permission})
        |> Repo.update()
    end
  end

  ## Copying

  @doc """
  Copies a deck (and its words/custom cards) to a user's own collection.
  Creates a new deck with new join table entries pointing to the same
  Word and CustomCard records.
  """
  def copy_deck_to_user(deck_id, user_id) do
    Repo.transaction(fn ->
      source_deck = Repo.get(Deck, deck_id) |> Repo.preload([:words, :custom_cards])

      if is_nil(source_deck) do
        Repo.rollback(:deck_not_found)
      else
        perform_deck_copy(source_deck, user_id)
      end
    end)
  end

  defp perform_deck_copy(source_deck, user_id) do
    new_deck_attrs = %{
      name: "#{source_deck.name} (Copy)",
      description: source_deck.description,
      visibility: "private",
      language: source_deck.language,
      user_id: user_id
    }

    case Repo.insert(Deck.changeset(%Deck{}, new_deck_attrs)) do
      {:ok, new_deck} ->
        copy_deck_associations(new_deck, source_deck)
        new_deck

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp copy_deck_associations(new_deck, source_deck) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Copy word associations
    word_entries =
      Enum.map(source_deck.words, fn word ->
        %{deck_id: new_deck.id, word_id: word.id, inserted_at: now, updated_at: now}
      end)

    if word_entries != [], do: Repo.insert_all(DeckWord, word_entries)

    # Copy custom card associations
    custom_card_entries =
      Enum.map(source_deck.custom_cards, fn card ->
        %{deck_id: new_deck.id, custom_card_id: card.id, inserted_at: now, updated_at: now}
      end)

    if custom_card_entries != [], do: Repo.insert_all(DeckCustomCard, custom_card_entries)
  end

  ## Word Management

  @doc """
  Moves a word from one deck to another (drag and drop).
  """
  def move_word_between_decks(word_id, from_deck_id, to_deck_id, user_id) do
    Repo.transaction(fn ->
      # Verify ownership of both decks
      from_deck = Repo.get_by(Deck, id: from_deck_id, user_id: user_id)
      to_deck = Repo.get_by(Deck, id: to_deck_id, user_id: user_id)

      cond do
        is_nil(from_deck) ->
          Repo.rollback(:from_deck_not_found)

        is_nil(to_deck) ->
          Repo.rollback(:to_deck_not_found)

        true ->
          # Remove from source deck
          Repo.delete_all(
            from dw in DeckWord,
              where: dw.deck_id == ^from_deck_id and dw.word_id == ^word_id
          )

          # Add to target deck (idempotent)
          %DeckWord{}
          |> DeckWord.changeset(%{deck_id: to_deck_id, word_id: word_id})
          |> Repo.insert(on_conflict: :nothing)

          :ok
      end
    end)
  end

  @doc """
  Bulk adds words to a deck.
  """
  def bulk_add_words_to_deck(deck_id, word_ids, user_id) when is_list(word_ids) do
    deck = Repo.get_by(Deck, id: deck_id, user_id: user_id)

    if is_nil(deck) do
      {:error, :deck_not_found}
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      entries =
        Enum.map(word_ids, fn word_id ->
          %{
            deck_id: deck_id,
            word_id: word_id,
            inserted_at: now,
            updated_at: now
          }
        end)

      {count, _} = Repo.insert_all(DeckWord, entries, on_conflict: :nothing)
      {:ok, count}
    end
  end

  ## Deck Contents

  @doc """
  Lists words in a deck with access check.
  """
  def list_deck_words(deck_id, viewer_user_id) do
    if can_view_deck?(deck_id, viewer_user_id) do
      from(dw in DeckWord,
        where: dw.deck_id == ^deck_id,
        join: w in assoc(dw, :word),
        select: w,
        order_by: [asc: w.normalized_form]
      )
      |> Repo.all()
    else
      []
    end
  end

  @doc """
  Lists custom cards in a deck with access check.
  """
  def list_deck_custom_cards(deck_id, viewer_user_id) do
    if can_view_deck?(deck_id, viewer_user_id) do
      from(dcc in DeckCustomCard,
        where: dcc.deck_id == ^deck_id,
        join: cc in assoc(dcc, :custom_card),
        select: cc,
        order_by: [desc: cc.inserted_at]
      )
      |> Repo.all()
    else
      []
    end
  end

  @doc """
  Adds a custom card to a deck.
  """
  def add_custom_card_to_deck(deck_id, custom_card_id, user_id) do
    deck = Repo.get_by(Deck, id: deck_id, user_id: user_id)
    custom_card = Repo.get(CustomCard, custom_card_id)

    cond do
      is_nil(deck) ->
        {:error, :deck_not_found}

      is_nil(custom_card) ->
        {:error, :custom_card_not_found}

      custom_card.user_id != user_id ->
        {:error, :not_card_owner}

      true ->
        %DeckCustomCard{}
        |> DeckCustomCard.changeset(%{deck_id: deck_id, custom_card_id: custom_card_id})
        |> Repo.insert(on_conflict: :nothing)
    end
  end

  @doc """
  Removes a custom card from a deck.
  """
  def remove_custom_card_from_deck(deck_id, custom_card_id, user_id) do
    deck = Repo.get_by(Deck, id: deck_id, user_id: user_id)

    if is_nil(deck) do
      {:error, :deck_not_found}
    else
      {count, _} =
        Repo.delete_all(
          from dcc in DeckCustomCard,
            where: dcc.deck_id == ^deck_id and dcc.custom_card_id == ^custom_card_id
        )

      if count > 0 do
        {:ok, :removed}
      else
        {:error, :not_in_deck}
      end
    end
  end

  ## Custom Cards

  @doc """
  Creates a custom card.
  """
  def create_custom_card(user_id, attrs) do
    attrs = Map.put(attrs, :user_id, user_id)

    %CustomCard{}
    |> CustomCard.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a custom card with ownership check.
  """
  def update_custom_card(custom_card_id, user_id, attrs) do
    case Repo.get_by(CustomCard, id: custom_card_id, user_id: user_id) do
      nil ->
        {:error, :not_found}

      custom_card ->
        custom_card
        |> CustomCard.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Deletes a custom card with ownership check.
  """
  def delete_custom_card(custom_card_id, user_id) do
    case Repo.get_by(CustomCard, id: custom_card_id, user_id: user_id) do
      nil ->
        {:error, :not_found}

      custom_card ->
        Repo.delete(custom_card)
    end
  end

  @doc """
  Creates a custom card and adds it to specified decks (including default).
  Convenience function for the common workflow.
  """
  def add_new_custom_card_to_decks(user_id, attrs, deck_ids) when is_list(deck_ids) do
    Repo.transaction(fn ->
      with {:ok, custom_card} <- create_custom_card(user_id, attrs),
           default_deck <- get_or_rollback_default_deck(user_id) do
        add_card_to_decks(custom_card, default_deck, deck_ids)
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp get_or_rollback_default_deck(user_id) do
    Repo.get_by(Deck, user_id: user_id, is_default: true) ||
      Repo.rollback(:no_default_deck)
  end

  defp add_card_to_decks(custom_card, default_deck, deck_ids) do
    all_deck_ids = [default_deck.id | deck_ids] |> Enum.uniq()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      Enum.map(all_deck_ids, fn deck_id ->
        %{deck_id: deck_id, custom_card_id: custom_card.id, inserted_at: now, updated_at: now}
      end)

    Repo.insert_all(DeckCustomCard, entries, on_conflict: :nothing)
    custom_card
  end

  @doc """
  Gets all study cards for a user from owned, followed, and shared decks.
  Returns both words and custom cards combined.
  """
  def list_study_cards_for_user(user_id, opts \\ []) do
    deck_filter = Keyword.get(opts, :deck_id)

    # Get all accessible deck IDs
    accessible_deck_ids = get_accessible_deck_ids(user_id, deck_filter)

    # Get words from those decks
    words =
      from(dw in DeckWord,
        where: dw.deck_id in ^accessible_deck_ids,
        join: w in assoc(dw, :word),
        distinct: w.id,
        select: %{type: "word", content: w}
      )
      |> Repo.all()

    # Get custom cards from those decks
    custom_cards =
      from(dcc in DeckCustomCard,
        where: dcc.deck_id in ^accessible_deck_ids,
        join: cc in assoc(dcc, :custom_card),
        distinct: cc.id,
        select: %{type: "custom_card", content: cc}
      )
      |> Repo.all()

    words ++ custom_cards
  end

  ## Private Helpers

  defp get_accessible_deck_ids(user_id, deck_filter) do
    # Owned decks
    owned =
      from(d in Deck,
        where: d.user_id == ^user_id,
        select: d.id
      )

    # Followed decks
    followed =
      from(df in DeckFollow,
        where: df.user_id == ^user_id,
        select: df.deck_id
      )

    # Shared decks
    shared =
      from(ds in DeckShare,
        where: ds.shared_with_user_id == ^user_id,
        select: ds.deck_id
      )

    query = union_all(owned, ^followed) |> union_all(^shared)

    deck_ids = Repo.all(query)

    if deck_filter do
      Enum.filter(deck_ids, &(&1 == deck_filter))
    else
      deck_ids
    end
  end

  defp can_view_deck?(deck_id, viewer_user_id) do
    # Check if owned
    owned = Repo.exists?(from d in Deck, where: d.id == ^deck_id and d.user_id == ^viewer_user_id)

    if owned do
      true
    else
      # Check if public
      public = Repo.exists?(from d in Deck, where: d.id == ^deck_id and d.visibility == "public")

      if public do
        true
      else
        # Check if shared
        Repo.exists?(
          from ds in DeckShare,
            where: ds.deck_id == ^deck_id and ds.shared_with_user_id == ^viewer_user_id
        )
      end
    end
  end

  defp get_deck_for_viewer(deck_id, viewer_user_id) do
    if can_view_deck?(deck_id, viewer_user_id) do
      Repo.get(Deck, deck_id)
    else
      nil
    end
  end

  @doc """
  Creates a deck with words in one transaction.
  Used when accepting LLM suggestions.
  """
  def create_deck_with_words(user_id, deck_attrs, word_ids) when is_list(word_ids) do
    Repo.transaction(fn ->
      deck_attrs = Map.put(deck_attrs, :user_id, user_id)

      case Repo.insert(Deck.changeset(%Deck{}, deck_attrs)) do
        {:ok, deck} ->
          insert_word_associations(deck.id, word_ids)
          deck

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp insert_word_associations(deck_id, word_ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      Enum.map(word_ids, fn word_id ->
        %{deck_id: deck_id, word_id: word_id, inserted_at: now, updated_at: now}
      end)

    Repo.insert_all(DeckWord, entries)
  end
end
