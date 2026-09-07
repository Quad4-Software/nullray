# Provider reference

Ids are `NULLRAY_PROVIDER` values. Bases are OpenAI Chat Completions style unless noted. Keys come from env (and `~/.config/nullray/env`). Shared fallback: `NULLRAY_API_KEY`. Override base with `NULLRAY_BASE_URL` where supported.

| Id | Env key(s) | Default base |
|----|------------|--------------|
| anthropic | `ANTHROPIC_API_KEY` | `https://api.anthropic.com/v1` |
| gemini | `GEMINI_API_KEY`, alt `GOOGLE_API_KEY` | `https://generativelanguage.googleapis.com/v1beta/openai` |
| groq | `GROQ_API_KEY` | `https://api.groq.com/openai/v1` |
| deepseek | `DEEPSEEK_API_KEY` | `https://api.deepseek.com/v1` |
| mistral | `MISTRAL_API_KEY` | `https://api.mistral.ai/v1` |
| together | `TOGETHER_API_KEY` | `https://api.together.xyz/v1` |
| fireworks | `FIREWORKS_API_KEY` | `https://api.fireworks.ai/inference/v1` |
| xai | `XAI_API_KEY` | `https://api.x.ai/v1` |
| azure | `AZURE_OPENAI_API_KEY`, alt `OPENAI_API_KEY`. Endpoint: `AZURE_OPENAI_ENDPOINT` | (empty until endpoint set) |
| openai | `OPENAI_API_KEY`. Base override: `OPENAI_BASE_URL` | `https://api.openai.com/v1` |
| openai-compat | `OPENAI_API_KEY` / `NULLRAY_API_KEY`. Base: `OPENAI_BASE_URL` or `NULLRAY_BASE_URL` | (required) |
| ollama | `OLLAMA_HOST` | `http://127.0.0.1:11434/v1` |
| lmstudio | `LM_API_TOKEN` (default `lm-studio`), host `LM_STUDIO_HOST` | `http://127.0.0.1:1234/v1` |
| openrouter | `OPENROUTER_API_KEY` | `https://openrouter.ai/api/v1` |
| opencode | `OPENCODE_API_KEY` | `https://opencode.ai/zen/v1` |
| opencode-go | `OPENCODE_API_KEY` | `https://opencode.ai/zen/go/v1` |

Aliases normalized in `normalize_provider_id`: `claude` → anthropic, `google` / `google-gemini` → gemini, `grok` → xai, `oai` → openai, `openai_compatible` / `compatible` / `custom` → openai-compat, `azure-openai` → azure.

Source of truth: `nullray/constants/constants.odin` and `nullray/provider/builtins.odin`.
