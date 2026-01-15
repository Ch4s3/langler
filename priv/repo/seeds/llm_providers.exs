# Script for populating the llm_providers table.

alias Langler.Repo
alias Langler.Accounts.LlmProvider

# Seed ChatGPT provider
Repo.insert!(
  %LlmProvider{
    name: "chatgpt",
    display_name: "ChatGPT",
    adapter_module: "Langler.LLM.Adapters.ChatGPT",
    requires_api_key: true,
    api_key_label: "OpenAI API Key",
    base_url: "https://api.openai.com/v1",
    enabled: true
  },
  on_conflict: :nothing
)

IO.puts("✓ Seeded llm_providers")
