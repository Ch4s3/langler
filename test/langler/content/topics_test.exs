defmodule Langler.Content.TopicsTest do
  use ExUnit.Case, async: true

  alias Langler.Content.Topics

  test "topics/0 returns all topics" do
    topics = Topics.topics()
    assert is_map(topics)
    assert Map.has_key?(topics, :spanish)
    assert Map.has_key?(topics, :english)
  end

  test "topics_for_language/1 with atom" do
    spanish_topics = Topics.topics_for_language(:spanish)
    assert is_map(spanish_topics)
    assert Map.has_key?(spanish_topics, :ciencia)

    english_topics = Topics.topics_for_language(:english)
    assert is_map(english_topics)
    assert Map.has_key?(english_topics, :science)
  end

  test "topics_for_language/1 with binary" do
    spanish_topics = Topics.topics_for_language("spanish")
    assert is_map(spanish_topics)
    assert Map.has_key?(spanish_topics, :ciencia)

    english_topics = Topics.topics_for_language("english")
    assert is_map(english_topics)
    assert Map.has_key?(english_topics, :science)
  end

  test "topics_for_language/1 with unknown language defaults to spanish" do
    topics = Topics.topics_for_language("unknown")
    assert is_map(topics)
    assert Map.has_key?(topics, :ciencia)
  end

  test "topic_ids_for_language/1 returns list of topic IDs" do
    spanish_ids = Topics.topic_ids_for_language("spanish")
    assert is_list(spanish_ids)
    assert "ciencia" in spanish_ids
    assert "política" in spanish_ids

    english_ids = Topics.topic_ids_for_language("english")
    assert is_list(english_ids)
    assert "science" in english_ids
  end

  test "topic_name/2 returns topic name" do
    assert Topics.topic_name("spanish", "ciencia") == "Ciencia"
    assert Topics.topic_name("english", "science") == "Science"
  end

  test "topic_name/2 returns topic_id when topic not found" do
    assert Topics.topic_name("spanish", "unknown_topic") == "unknown_topic"
  end

  test "topic_name/2 handles invalid atom conversion" do
    # This should not raise
    result = Topics.topic_name("spanish", "invalid_atom_name_123")
    assert is_binary(result)
  end
end
