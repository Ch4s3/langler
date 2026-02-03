defmodule Langler.Repo.Migrations.MigrateLanguageCodes do
  use Ecto.Migration

  def up do
    # Map of old language names to new codes
    language_map = %{
      "spanish" => "es",
      "english" => "en",
      "french" => "fr",
      "italian" => "it",
      "romanian" => "ro",
      "catalan" => "ca",
      "portuguese" => "pt-PT"
    }

    # user_preferences.target_language and native_language
    for {old_name, new_code} <- language_map do
      execute """
      UPDATE user_preferences
      SET target_language = '#{new_code}'
      WHERE target_language = '#{old_name}'
      """

      execute """
      UPDATE user_preferences
      SET native_language = '#{new_code}'
      WHERE native_language = '#{old_name}'
      """
    end

    # chat_sessions.target_language and native_language
    for {old_name, new_code} <- language_map do
      execute """
      UPDATE chat_sessions
      SET target_language = '#{new_code}'
      WHERE target_language = '#{old_name}'
      """

      execute """
      UPDATE chat_sessions
      SET native_language = '#{new_code}'
      WHERE native_language = '#{old_name}'
      """
    end

    # articles.language
    for {old_name, new_code} <- language_map do
      execute """
      UPDATE articles
      SET language = '#{new_code}'
      WHERE language = '#{old_name}'
      """
    end

    # words.language
    for {old_name, new_code} <- language_map do
      execute """
      UPDATE words
      SET language = '#{new_code}'
      WHERE language = '#{old_name}'
      """
    end

    # article_topics.language
    for {old_name, new_code} <- language_map do
      execute """
      UPDATE article_topics
      SET language = '#{new_code}'
      WHERE language = '#{old_name}'
      """
    end

    # user_interest_tags.language
    for {old_name, new_code} <- language_map do
      execute """
      UPDATE user_interest_tags
      SET language = '#{new_code}'
      WHERE language = '#{old_name}'
      """
    end

    # source_sites.language
    for {old_name, new_code} <- language_map do
      execute """
      UPDATE source_sites
      SET language = '#{new_code}'
      WHERE language = '#{old_name}'
      """
    end

    # discovered_articles.language (nullable)
    for {old_name, new_code} <- language_map do
      execute """
      UPDATE discovered_articles
      SET language = '#{new_code}'
      WHERE language = '#{old_name}'
      """
    end
  end

  def down do
    # Reverse map of codes to old names
    reverse_map = %{
      "es" => "spanish",
      "en" => "english",
      "fr" => "french",
      "it" => "italian",
      "ro" => "romanian",
      "ca" => "catalan",
      "pt-PT" => "portuguese",
      "pt-BR" => "portuguese"
    }

    # Reverse all the updates
    for {new_code, old_name} <- reverse_map do
      execute """
      UPDATE user_preferences
      SET target_language = '#{old_name}'
      WHERE target_language = '#{new_code}'
      """

      execute """
      UPDATE user_preferences
      SET native_language = '#{old_name}'
      WHERE native_language = '#{new_code}'
      """

      execute """
      UPDATE chat_sessions
      SET target_language = '#{old_name}'
      WHERE target_language = '#{new_code}'
      """

      execute """
      UPDATE chat_sessions
      SET native_language = '#{old_name}'
      WHERE native_language = '#{new_code}'
      """

      execute """
      UPDATE articles
      SET language = '#{old_name}'
      WHERE language = '#{new_code}'
      """

      execute """
      UPDATE words
      SET language = '#{old_name}'
      WHERE language = '#{new_code}'
      """

      execute """
      UPDATE article_topics
      SET language = '#{old_name}'
      WHERE language = '#{new_code}'
      """

      execute """
      UPDATE user_interest_tags
      SET language = '#{old_name}'
      WHERE language = '#{new_code}'
      """

      execute """
      UPDATE source_sites
      SET language = '#{old_name}'
      WHERE language = '#{new_code}'
      """

      execute """
      UPDATE discovered_articles
      SET language = '#{old_name}'
      WHERE language = '#{new_code}'
      """
    end
  end
end
