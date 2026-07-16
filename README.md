# Grok Build — multi-vendor fork

**Grok Build** is [xAI / SpaceXAI’s](https://github.com/xai-org/grok-build) terminal coding agent, forked here with small patches so you can:

1. **Use your Grok account** (browser / `grok login`) for xAI-hosted models — the stock default experience.
2. **Bring your own vendor** via OpenAI-compatible APIs (e.g. **Together.ai**), with per-model API keys.
3. Load keys from a **file** (`api_key_file`) as well as env vars / inline config.
4. Self-identify correctly: *“You are Grok Build running the **&lt;model&gt;** model…”*

Upstream source: [xai-org/grok-build](https://github.com/xai-org/grok-build) (Apache-2.0).  
This fork does **not** replace the official binary’s auto-update channel; install as `grok-local` by default so stock `grok` stays untouched.

---

## Quick install (from source zip or git clone)

```bash
# After unzip or: git clone <this-repo>.git && cd <this-repo>
chmod +x install.sh
./install.sh
# optional: append Together model blocks to ~/.grok/config.toml
./install.sh --with-together-config
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
| `api_key_file` | `[model.*] api_key_file = "~/secret.txt"` loads a trimmed key at config apply time |
| Identity prompt | *Grok Build running the &lt;model&gt; model* (not silent “I am Grok 4.5” when on a vendor) |
| Docs | Together / MiniMax / Kimi examples in the custom-models guide |
| Installer | `install.sh` + `config.example.toml` |

Credential order for each model:

1. `api_key`
2. `api_key_file`
3. `env_key` (string or array)
4. Grok session token (`grok login`)
5. `XAI_API_KEY`

---

## Configure Together.ai (optional)

1. Get an API key from [Together](https://api.together.ai/).
2. Save it (never commit this file):

```bash
echo 'YOUR_TOGETHER_KEY' > ~/together_api_key.txt
chmod 600 ~/together_api_key.txt
```

3. Merge example models:

```bash
./install.sh --with-together-config
# or manually: copy blocks from config.example.toml into ~/.grok/config.toml
```

4. Run:

```bash
grok-local models
grok-local -m together-glm -p "Say hello"
grok-local -m together-minimax   # MiniMax-M3, 524K context
grok-local -m together-kimi      # Kimi-K2.7-Code
```

| Config id | Together model | Context (Together serverless) |
|-----------|----------------|--------------------------------|
| `together-glm` | `zai-org/GLM-5.2` | 256K |
| `together-minimax` | `MiniMaxAI/MiniMax-M3` | **524K** |
| `together-kimi` | `moonshotai/Kimi-K2.7-Code` | 256K |

Grok account models still work when selected (and when a model has no vendor key of its own).

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
