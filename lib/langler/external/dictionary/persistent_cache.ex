defmodule Langler.External.Dictionary.PersistentCache do
  @moduledoc false

  import Ecto.Query
  alias Langler.Repo
  alias Langler.External.Dictionary.CacheEntry

  def fetch(table, key) do
    table_name = table |> to_string()
    key_bin = :erlang.term_to_binary(key)
    key_hash = key_hash(key_bin)
    now = DateTime.utc_now()

    query =
      from e in CacheEntry,
        where: e.table_name == ^table_name,
        where: e.key_hash == ^key_hash,
        where: e.expires_at > ^now,
        limit: 1

    case Repo.one(query) do
      nil ->
        :miss

      %CacheEntry{} = entry ->
        {:ok,
         %{
           value: decode(entry.value),
           expires_at_ms: datetime_to_ms(entry.expires_at)
         }}
    end
  end

  def store(table, key, value, expires_at_ms) do
    table_name = table |> to_string()
    key_bin = :erlang.term_to_binary(key)
    value_bin = :erlang.term_to_binary(value)
    key_hash = key_hash(key_bin)
    expires_at = ms_to_datetime(expires_at_ms)
    now = DateTime.utc_now()

    params = %{
      table_name: table_name,
      key: key_bin,
      key_hash: key_hash,
      value: value_bin,
      expires_at: expires_at,
      inserted_at: now,
      updated_at: now
    }

    Repo.insert(
      %CacheEntry{} |> CacheEntry.changeset(params),
      on_conflict: [
        set: [value: value_bin, expires_at: expires_at, key: key_bin, updated_at: now]
      ],
      conflict_target: [:table_name, :key_hash]
    )
  end

  def stream_active_entries(table, fun) when is_function(fun, 1) do
    table_name = table |> to_string()
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      CacheEntry
      |> where(table_name: ^table_name)
      |> where([e], e.expires_at > ^now)
      |> Repo.stream()
      |> Enum.each(fn entry ->
        fun.({decode(entry.key), decode(entry.value), datetime_to_ms(entry.expires_at)})
      end)
    end)
  end

  defp decode(binary) do
    :erlang.binary_to_term(binary)
  end

  defp key_hash(key_bin), do: :erlang.phash2(key_bin)

  defp datetime_to_ms(datetime) do
    DateTime.to_unix(datetime, :millisecond)
  end

  defp ms_to_datetime(ms) do
    DateTime.from_unix!(ms, :millisecond)
  end
end
