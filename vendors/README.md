# Vendor presets

Drop-in `[model.*]` blocks for common OpenAI-compatible (and Anthropic) APIs.

## Key file convention

For a vendor id `VENDOR` (e.g. `together`, `openai`, `openrouter`):

| Location | Example |
|----------|---------|
| **`~/VENDOR_api_key.txt`** | `~/together_api_key.txt` |
| `~/.grok/keys/VENDOR.txt` | `~/.grok/keys/openai.txt` |
| `~/.grok/keys/VENDOR_api_key.txt` | |
| `$GROK_KEYS_DIR/VENDOR.txt` | if you set that env var |

In config you can write either:

```toml
api_key_file = "@together"                 # resolve convention paths
api_key_file = "~/together_api_key.txt"  # explicit path
env_key = "TOGETHER_API_KEY"               # environment variable
```

Never commit key files.

## Add a preset to your config

```bash
# list known presets
./scripts/add-vendor.sh list

# install key placeholder + model blocks for a preset
./scripts/add-vendor.sh install together
./scripts/add-vendor.sh install openai
./scripts/add-vendor.sh install openrouter

# custom vendor / model
./scripts/add-vendor.sh add \
  --vendor acme \
  --id acme-coder \
  --model acme-coder-v1 \
  --base-url https://api.acme.example/v1 \
  --context 131072 \
  --name "Acme Coder"
```

Then put the secret in the key file and run:

```bash
grok-local models
grok-local -m together-glm
```
