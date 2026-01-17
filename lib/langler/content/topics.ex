defmodule Langler.Content.Topics do
  @moduledoc """
  Topic taxonomy and keyword dictionaries for article classification.

  Organized by language, with each topic containing keywords and weights
  used for rule-based topic classification of articles.
  """

  @topics %{
    spanish: %{
      ciencia: %{
        name: "Ciencia",
        keywords: [
          "ciencia",
          "científico",
          "científica",
          "investigación",
          "investigador",
          "investigadora",
          "estudio",
          "tecnología",
          "descubrimiento",
          "laboratorio",
          "experimento",
          "hipótesis",
          "teoría",
          "análisis",
          "datos",
          "investigación científica",
          "publicación científica",
          "revista científica"
        ],
        weight: 1.0
      },
      política: %{
        name: "Política",
        keywords: [
          "gobierno",
          "presidente",
          "presidenta",
          "elecciones",
          "congreso",
          "política",
          "político",
          "política",
          "partido",
          "votación",
          "democracia",
          "parlamento",
          "senado",
          "diputado",
          "ministro",
          "ministra",
          "ley",
          "legislación",
          "decreto",
          "coalición",
          "oposición"
        ],
        weight: 1.0
      },
      economía: %{
        name: "Economía",
        keywords: [
          "economía",
          "económico",
          "económica",
          "mercado",
          "inversión",
          "banco",
          "financiero",
          "financiera",
          "bolsa",
          "empresa",
          "negocio",
          "comercio",
          "exportación",
          "importación",
          "inflación",
          "desempleo",
          "empleo",
          "salario",
          "precio",
          "consumo",
          "pib",
          "crecimiento económico"
        ],
        weight: 1.0
      },
      cultura: %{
        name: "Cultura",
        keywords: [
          "cultura",
          "cultural",
          "arte",
          "artístico",
          "música",
          "literatura",
          "cine",
          "película",
          "teatro",
          "museo",
          "exposición",
          "artista",
          "escritor",
          "escritora",
          "novela",
          "libro",
          "poesía",
          "pintura",
          "escultura",
          "festival"
        ],
        weight: 1.0
      },
      deportes: %{
        name: "Deportes",
        keywords: [
          "deporte",
          "deportivo",
          "fútbol",
          "futbol",
          "equipo",
          "partido",
          "atleta",
          "deportista",
          "competición",
          "campeonato",
          "liga",
          "torneo",
          "juego",
          "jugador",
          "jugadora",
          "entrenador",
          "entrenadora",
          "gol",
          "punto",
          "victoria",
          "derrota",
          "olímpico",
          "olímpicos"
        ],
        weight: 1.0
      },
      salud: %{
        name: "Salud",
        keywords: [
          "salud",
          "médico",
          "médica",
          "enfermedad",
          "hospital",
          "tratamiento",
          "paciente",
          "medicina",
          "medicamento",
          "doctor",
          "doctora",
          "cirugía",
          "diagnóstico",
          "síntoma",
          "cura",
          "vacuna",
          "epidemia",
          "pandemia",
          "virus",
          "bacteria",
          "salud pública",
          "sanidad"
        ],
        weight: 1.0
      },
      tecnología: %{
        name: "Tecnología",
        keywords: [
          "tecnología",
          "tecnológico",
          "tecnológica",
          "digital",
          "software",
          "internet",
          "app",
          "aplicación",
          "ordenador",
          "computadora",
          "smartphone",
          "teléfono",
          "red",
          "redes sociales",
          "plataforma",
          "sistema",
          "programa",
          "programación",
          "código",
          "algoritmo",
          "inteligencia artificial",
          "ia",
          "robot",
          "robótica"
        ],
        weight: 1.0
      },
      internacional: %{
        name: "Internacional",
        keywords: [
          "mundial",
          "país",
          "países",
          "internacional",
          "global",
          "nación",
          "nacional",
          "estado",
          "gobierno",
          "relaciones internacionales",
          "diplomacia",
          "embajada",
          "consulado",
          "onu",
          "naciones unidas",
          "ue",
          "unión europea",
          "conflicto",
          "guerra",
          "paz",
          "tratado",
          "acuerdo internacional"
        ],
        weight: 1.0
      },
      sociedad: %{
        name: "Sociedad",
        keywords: [
          "sociedad",
          "social",
          "comunidad",
          "personas",
          "vida",
          "gente",
          "población",
          "ciudadano",
          "ciudadana",
          "derechos",
          "justicia",
          "igualdad",
          "diversidad",
          "inclusión",
          "educación",
          "escuela",
          "universidad",
          "estudiante",
          "profesor",
          "profesora",
          "familia",
          "niño",
          "niña",
          "joven",
          "adulto",
          "adulta",
          "mayor",
          "vejez"
        ],
        weight: 1.0
      }
    },
    english: %{
      science: %{
        name: "Science",
        keywords: [
          "science",
          "scientific",
          "research",
          "researcher",
          "study",
          "technology",
          "discovery",
          "laboratory",
          "experiment",
          "hypothesis",
          "theory",
          "analysis",
          "data",
          "publication",
          "journal"
        ],
        weight: 1.0
      },
      politics: %{
        name: "Politics",
        keywords: [
          "government",
          "president",
          "election",
          "congress",
          "politics",
          "political",
          "party",
          "vote",
          "voting",
          "democracy",
          "parliament",
          "senate",
          "representative",
          "minister",
          "law",
          "legislation",
          "decree",
          "coalition",
          "opposition"
        ],
        weight: 1.0
      },
      economy: %{
        name: "Economy",
        keywords: [
          "economy",
          "economic",
          "market",
          "investment",
          "bank",
          "financial",
          "stock",
          "company",
          "business",
          "trade",
          "export",
          "import",
          "inflation",
          "unemployment",
          "employment",
          "salary",
          "price",
          "consumption",
          "gdp",
          "economic growth"
        ],
        weight: 1.0
      },
      culture: %{
        name: "Culture",
        keywords: [
          "culture",
          "cultural",
          "art",
          "artistic",
          "music",
          "literature",
          "cinema",
          "film",
          "movie",
          "theater",
          "museum",
          "exhibition",
          "artist",
          "writer",
          "novel",
          "book",
          "poetry",
          "painting",
          "sculpture",
          "festival"
        ],
        weight: 1.0
      },
      sports: %{
        name: "Sports",
        keywords: [
          "sport",
          "sports",
          "football",
          "soccer",
          "team",
          "match",
          "game",
          "athlete",
          "competition",
          "championship",
          "league",
          "tournament",
          "player",
          "coach",
          "goal",
          "point",
          "victory",
          "defeat",
          "olympic",
          "olympics"
        ],
        weight: 1.0
      },
      health: %{
        name: "Health",
        keywords: [
          "health",
          "medical",
          "doctor",
          "disease",
          "hospital",
          "treatment",
          "patient",
          "medicine",
          "medication",
          "surgery",
          "diagnosis",
          "symptom",
          "cure",
          "vaccine",
          "epidemic",
          "pandemic",
          "virus",
          "bacteria",
          "public health"
        ],
        weight: 1.0
      },
      technology: %{
        name: "Technology",
        keywords: [
          "technology",
          "technological",
          "digital",
          "software",
          "internet",
          "app",
          "application",
          "computer",
          "smartphone",
          "phone",
          "network",
          "social media",
          "platform",
          "system",
          "program",
          "programming",
          "code",
          "algorithm",
          "artificial intelligence",
          "ai",
          "robot",
          "robotics"
        ],
        weight: 1.0
      },
      international: %{
        name: "International",
        keywords: [
          "world",
          "worldwide",
          "country",
          "countries",
          "international",
          "global",
          "nation",
          "national",
          "state",
          "government",
          "international relations",
          "diplomacy",
          "embassy",
          "consulate",
          "un",
          "united nations",
          "eu",
          "european union",
          "conflict",
          "war",
          "peace",
          "treaty",
          "international agreement"
        ],
        weight: 1.0
      },
      society: %{
        name: "Society",
        keywords: [
          "society",
          "social",
          "community",
          "people",
          "life",
          "population",
          "citizen",
          "rights",
          "justice",
          "equality",
          "diversity",
          "inclusion",
          "education",
          "school",
          "university",
          "student",
          "teacher",
          "family",
          "child",
          "children",
          "young",
          "adult",
          "elderly",
          "age"
        ],
        weight: 1.0
      }
    }
  }

  def topics, do: @topics

  def topics_for_language(language) when is_atom(language) do
    Map.get(@topics, language, %{})
  end

  def topics_for_language(language) when is_binary(language) do
    language_atom =
      case language do
        "spanish" -> :spanish
        "english" -> :english
        _ -> :spanish
      end

    Map.get(@topics, language_atom, %{})
  end

  def topic_ids_for_language(language) do
    language
    |> topics_for_language()
    |> Map.keys()
    |> Enum.map(&to_string/1)
  end

  def topic_name(language, topic_id) do
    language
    |> topics_for_language()
    |> Map.get(String.to_existing_atom(topic_id))
    |> case do
      nil -> topic_id
      topic -> topic.name
    end
  rescue
    ArgumentError -> topic_id
  end
end
