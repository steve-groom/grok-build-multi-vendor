# Grok Build — multi-vendor fork

**Grok Build** is [xAI / SpaceXAI’s](https://github.com/xai-org/grok-build) terminal coding agent, forked here with small patches so you can:

1. **Use your Grok account** (browser / `grok login`) for xAI-hosted models — the stock default experience.
2. **Bring your own vendor(s)** via OpenAI-compatible APIs (Together, OpenAI, OpenRouter, Groq, …).
3. Keys from **`~/VENDOR_api_key.txt`**, `~/.grok/keys/`, env vars, or inline config.
4. Self-identify correctly: *“You are Grok Build running the **&lt;model&gt;** model…”*

Upstream source: [xai-org/grok-build](https://github.com/xai-org/grok-build) (Apache-2.0).  
This fork does **not** replace the official binary’s auto-update channel; install as `grok-local` by default so stock `grok` stays untouched.

---

## Quick install (from source zip or git clone)

```bash
# After unzip or: git clone <this-repo>.git && cd <this-repo>
chmod +x install.sh scripts/add-vendor.sh
./install.sh
# optional: install one or more vendor presets into ~/.grok/config.toml
./install.sh --with-vendor-config together openai
# ( --with-together-config  is an alias for  --with-vendor-config together )
```

Installs to `~/.local/bin/grok-local` (override with `--prefix` / `--name`).

### Requirements

| Tool | Notes |
|------|--------|
| **Rust** | [rustup](https://rustup.rs) — toolchain pin is in `rust-toolchain.toml` |
| **protoc** | Auto-fetched by `install.sh` if missing |
| **curl / unzip** | For protoc bootstrap |
| Disk / RAM | Full release build is heavy (~10–20+ min first time) |

### One-liner (after you publish a release asset)

```bash
# Example once a GitHub release zip exists:
curl -fsSL https://github.com/<you>/grok-build-multi-vendor/releases/latest/download/source.zip -o /tmp/gb.zip
unzip -q /tmp/gb.zip -d /tmp/gb && cd /tmp/gb/*
./install.sh --with-together-config
```

---

## What changed vs upstream

| Feature | Detail |
|---------|--------|
| `api_key_file` | Explicit path **or** vendor slug `@together` / `vendor:openai` |
| Key convention | `~/VENDOR_api_key.txt` and `~/.grok/keys/VENDOR.txt` |
| Identity prompt | *Grok Build running the &lt;model&gt; model* |
| Presets | `vendors/*.toml` + `scripts/add-vendor.sh` |
| Installer | `install.sh --with-vendor-config …` |

Credential order for each model:

1. `api_key`
2. `api_key_file` (path or `@vendor` convention)
3. `env_key` (string or array)
4. Grok session token (`grok login`)
5. `XAI_API_KEY`

---

## Multi-vendor keys and models

### Convention

For any vendor slug **`V`** (e.g. `together`, `openai`, `openrouter`, `acme`):

```text
~/V_api_key.txt
~/.grok/keys/V.txt
~/.grok/keys/V_api_key.txt
$GROK_KEYS_DIR/V.txt          # optional override directory
```

In `~/.grok/config.toml`:

```toml
[model.my-openai]
model = "gpt-4o"
base_url = "https://api.openai.com/v1"
name = "OpenAI GPT-4o"
api_key_file = "@openai"              # resolves the convention paths above
# api_key_file = "~/openai_api_key.txt"  # or an explicit path
# env_key = "OPENAI_API_KEY"
api_backend = "chat_completions"
context_window = 128000
```

### Helpers

```bash
./scripts/add-vendor.sh list
./scripts/add-vendor.sh install together openai openrouter groq
./scripts/add-vendor.sh keys deepseek          # create empty key files only

# Fully custom OpenAI-compatible endpoint:
./scripts/add-vendor.sh add \
  --vendor acme \
  --id acme-coder \
  --model acme-coder-v1 \
  --base-url https://api.acme.example/v1 \
  --context 131072 \
  --name "Acme Coder"
```

Then paste secrets into the key files (`chmod 600`):

```bash
echo 'YOUR_KEY' > ~/together_api_key.txt && chmod 600 ~/together_api_key.txt
echo 'YOUR_KEY' > ~/openai_api_key.txt   && chmod 600 ~/openai_api_key.txt
```

### Built-in presets (`vendors/`)

| Preset | Notes |
|--------|--------|
| `together` | GLM-5.2, MiniMax-M3 (524K), Kimi-K2.7-Code |
| `openai` | GPT-4o / mini |
| `openrouter` | openrouter/auto |
| `groq` | Llama 3.3 70B |
| `fireworks` | Llama 3.3 70B |
| `deepseek` | deepseek-chat |
| `anthropic` | Messages API |
| `ollama` | Local, no key |

```bash
grok-local models
grok-local -m together-glm
grok-local -m openai-gpt4o
grok-local -m grok-4.5          # Grok account (no vendor key)
```

Grok account models work whenever a model has no own `api_key` / `api_key_file` / `env_key`.

### Estimated cost (Together.ai)

For Together models, `grok-local` fetches catalog rates from `GET /v1/models` (`pricing.input` / `output` / `cached_input`, **USD per 1M tokens**) and estimates session cost as:

```text
cost ≈ uncached_input/1e6 × input + cached/1e6 × cached_input + completion/1e6 × output
```

- Shown in the **turn status line** as `~$0.00…` (running total)
- Headless / JSON: `total_cost_usd` when the estimate is available
- Logs: `together pricing: estimated turn cost … estimated_cost_usd=…`
- This is an **estimate**, not Together’s invoice (wire chat usage has tokens only)

Other vendors: cost is shown only if the API reports cost ticks (e.g. first-party xAI) or we add a catalog later.


---

## Manual build

```bash
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
export PROTOC="$(command -v protoc)"
cargo build -p xai-grok-pager-bin --release
# binary: target/release/xai-grok-pager
cp target/release/xai-grok-pager ~/.local/bin/grok-local
```

If you edit `crates/codegen/xai-grok-agent/templates/*.md`, regenerate encrypted templates:

```bash
cd crates/codegen/xai-grok-agent && python3 scripts/encrypt_templates.py
```

---

## Verify which model is live

Asking the agent “what model are you?” follows the system prompt. Prefer:

```bash
grok-local models          # * = default
# or logs:
RUST_LOG=info GROK_LOG_FILE=/tmp/grok.log grok-local -m together-glm -p "ping"
# look for: base_url=https://api.together.ai/v1  model=zai-org/GLM-5.2
```

---

## Security

- Do **not** commit API keys or `together_api_key.txt`.
- Prefer `api_key_file` or environment variables over inline `api_key` in tracked files.
- Official `grok` auto-update is separate; this install uses the name `grok-local` by default.

---

## License

First-party code remains under the **Apache License 2.0** (see `LICENSE` and upstream notices).  
This fork’s packaging (`install.sh`, `config.example.toml`, docs additions) is also Apache-2.0.

Upstream: https://github.com/xai-org/grok-build  
Grok Build product: https://x.ai/cli
