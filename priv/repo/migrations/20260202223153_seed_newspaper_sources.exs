defmodule Langler.Repo.Migrations.SeedNewspaperSources do
  use Ecto.Migration

  def up do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # French sources
    execute """
    INSERT INTO source_sites (name, url, rss_url, discovery_method, language, is_active, inserted_at, updated_at)
    VALUES
      ('Le Monde', 'https://www.lemonde.fr', 'https://www.lemonde.fr/rss/une.xml', 'rss', 'fr', true, '#{now}', '#{now}'),
      ('Le Figaro', 'https://www.lefigaro.fr', 'https://www.lefigaro.fr/rss/figaro_actualites.xml', 'rss', 'fr', true, '#{now}', '#{now}'),
      ('France 24', 'https://www.france24.com', 'https://www.france24.com/fr/rss', 'rss', 'fr', true, '#{now}', '#{now}')
    ON CONFLICT (url) DO NOTHING
    """

    # Italian sources
    execute """
    INSERT INTO source_sites (name, url, rss_url, discovery_method, language, is_active, inserted_at, updated_at)
    VALUES
      ('La Repubblica', 'https://www.repubblica.it', 'https://www.repubblica.it/rss/homepage/rss2.0.xml', 'rss', 'it', true, '#{now}', '#{now}'),
      ('Corriere della Sera', 'https://www.corriere.it', 'https://www.corriere.it/rss/homepage.xml', 'rss', 'it', true, '#{now}', '#{now}'),
      ('ANSA', 'https://www.ansa.it', 'https://www.ansa.it/sito/ansait_rss.xml', 'rss', 'it', true, '#{now}', '#{now}')
    ON CONFLICT (url) DO NOTHING
    """

    # Portuguese (Portugal) sources
    execute """
    INSERT INTO source_sites (name, url, rss_url, discovery_method, language, is_active, inserted_at, updated_at)
    VALUES
      ('Público', 'https://www.publico.pt', 'https://feeds.feedburner.com/PublicoRSS', 'rss', 'pt-PT', true, '#{now}', '#{now}'),
      ('RTP Notícias', 'https://www.rtp.pt', 'https://www.rtp.pt/noticias/rss', 'rss', 'pt-PT', true, '#{now}', '#{now}')
    ON CONFLICT (url) DO NOTHING
    """

    # Portuguese (Brazil) sources
    execute """
    INSERT INTO source_sites (name, url, rss_url, discovery_method, language, is_active, inserted_at, updated_at)
    VALUES
      ('Folha de S.Paulo', 'https://www.folha.uol.com.br', 'https://feeds.folha.uol.com.br/emcimadahora/rss091.xml', 'rss', 'pt-BR', true, '#{now}', '#{now}'),
      ('G1', 'https://g1.globo.com', 'https://g1.globo.com/rss/g1/', 'rss', 'pt-BR', true, '#{now}', '#{now}')
    ON CONFLICT (url) DO NOTHING
    """

    # Romanian sources
    execute """
    INSERT INTO source_sites (name, url, rss_url, discovery_method, language, is_active, inserted_at, updated_at)
    VALUES
      ('Digi24', 'https://www.digi24.ro', 'https://www.digi24.ro/rss', 'rss', 'ro', true, '#{now}', '#{now}'),
      ('HotNews', 'https://www.hotnews.ro', 'https://www.hotnews.ro/rss', 'rss', 'ro', true, '#{now}', '#{now}')
    ON CONFLICT (url) DO NOTHING
    """

    # Catalan sources
    execute """
    INSERT INTO source_sites (name, url, rss_url, discovery_method, language, is_active, inserted_at, updated_at)
    VALUES
      ('Ara', 'https://www.ara.cat', 'https://www.ara.cat/rss/', 'rss', 'ca', true, '#{now}', '#{now}'),
      ('VilaWeb', 'https://www.vilaweb.cat', 'https://www.vilaweb.cat/feed/', 'rss', 'ca', true, '#{now}', '#{now}'),
      ('NacióDigital', 'https://www.naciodigital.cat', 'https://www.naciodigital.cat/rss', 'rss', 'ca', true, '#{now}', '#{now}')
    ON CONFLICT (url) DO NOTHING
    """
  end

  def down do
    # Remove the seeded sources
    execute """
    DELETE FROM source_sites
    WHERE url IN (
      'https://www.lemonde.fr',
      'https://www.lefigaro.fr',
      'https://www.france24.com',
      'https://www.repubblica.it',
      'https://www.corriere.it',
      'https://www.ansa.it',
      'https://www.publico.pt',
      'https://www.rtp.pt',
      'https://www.folha.uol.com.br',
      'https://g1.globo.com',
      'https://www.digi24.ro',
      'https://www.hotnews.ro',
      'https://www.ara.cat',
      'https://www.vilaweb.cat',
      'https://www.naciodigital.cat'
    )
    """
  end
end
