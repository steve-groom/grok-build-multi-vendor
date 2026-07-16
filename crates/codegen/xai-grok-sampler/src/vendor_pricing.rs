//! Vendor model pricing for estimated session cost (Together.ai first).
//!
//! Together's chat completions usage object reports token counts but **not**
//! USD. Their `/v1/models` catalog includes a `pricing` object with rates in
//! **USD per 1M tokens** (`input`, `output`, `cached_input`).
//!
//! We cache those rates and, when the wire omits cost ticks, estimate:
//!
//! ```text
//! cost = uncached_input/1e6 * input
//!      + cached_input/1e6  * cached_input_rate
//!      + completion/1e6    * output
//! ```
//!
//! Cost is stored in the existing `cost_usd_ticks` channel (1 USD = 1e10 ticks)
//! so headless `total_cost_usd` and the usage ledger work unchanged.
//! Estimates are labeled in logs as `estimated` — not a bill of record.

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use serde::Deserialize;
use xai_grok_sampling_types::TokenUsage;

/// Server scale: 1 USD = 10^10 ticks (matches `xai-chat-state` / headless).
pub const USD_TICKS_PER_USD: f64 = 1e10;

/// How long a Together catalog pricing snapshot is considered fresh.
const PRICING_TTL: Duration = Duration::from_secs(6 * 60 * 60);

#[derive(Debug, Clone, Copy)]
pub struct ModelRates {
    /// USD per 1M input tokens (uncached).
    pub input_per_mtok: f64,
    /// USD per 1M output / completion tokens.
    pub output_per_mtok: f64,
    /// USD per 1M cached input tokens (falls back to `input_per_mtok` if 0).
    pub cached_input_per_mtok: f64,
}

#[derive(Debug, Default)]
struct PricingCache {
    /// model id → rates
    rates: HashMap<String, ModelRates>,
    fetched_at: Option<Instant>,
    /// Last base URL we successfully fetched for (normalized).
    base_url: Option<String>,
}

static TOGETHER_PRICING: OnceLock<Mutex<PricingCache>> = OnceLock::new();

fn cache() -> &'static Mutex<PricingCache> {
    TOGETHER_PRICING.get_or_init(|| Mutex::new(PricingCache::default()))
}

/// True when `base_url` looks like Together serverless inference.
pub fn is_together_base_url(base_url: &str) -> bool {
    let u = base_url.to_ascii_lowercase();
    u.contains("together.ai") || u.contains("together.xyz")
}

/// Strip trailing `/v1` etc. so we can form `{base}/models`.
fn models_list_url(base_url: &str) -> String {
    let b = base_url.trim().trim_end_matches('/');
    // base is typically https://api.together.ai/v1
    if b.ends_with("/models") {
        b.to_string()
    } else {
        format!("{b}/models")
    }
}

#[derive(Debug, Deserialize)]
struct TogetherPricingJson {
    #[serde(default)]
    input: f64,
    #[serde(default)]
    output: f64,
    #[serde(default)]
    cached_input: f64,
}

#[derive(Debug, Deserialize)]
struct TogetherModelJson {
    id: Option<String>,
    pricing: Option<TogetherPricingJson>,
}

/// Fetch / refresh Together model pricing into the process-wide cache.
///
/// Safe to call often: no-ops when the cache is still fresh for this base URL.
/// Failures are logged and leave any previous cache intact.
pub async fn ensure_together_pricing(base_url: &str, api_key: Option<&str>) {
    if !is_together_base_url(base_url) {
        return;
    }
    {
        let guard = cache().lock().unwrap_or_else(|e| e.into_inner());
        if let (Some(at), Some(cached_base)) = (guard.fetched_at, guard.base_url.as_deref()) {
            if cached_base == base_url && at.elapsed() < PRICING_TTL && !guard.rates.is_empty() {
                return;
            }
        }
    }

    let url = models_list_url(base_url);
    let client = match reqwest::Client::builder()
        .timeout(Duration::from_secs(20))
        .build()
    {
        Ok(c) => c,
        Err(e) => {
            tracing::warn!(error = %e, "together pricing: failed to build HTTP client");
            return;
        }
    };
    let mut req = client.get(&url);
    if let Some(key) = api_key.filter(|k| !k.trim().is_empty()) {
        req = req.bearer_auth(key.trim());
    }
    let body = match req.send().await {
        Ok(resp) => {
            if !resp.status().is_success() {
                tracing::warn!(
                    status = %resp.status(),
                    url = %url,
                    "together pricing: models list non-success"
                );
                return;
            }
            match resp.bytes().await {
                Ok(b) => b,
                Err(e) => {
                    tracing::warn!(error = %e, "together pricing: read body failed");
                    return;
                }
            }
        }
        Err(e) => {
            tracing::warn!(error = %e, url = %url, "together pricing: fetch failed");
            return;
        }
    };

    // Catalog is either a bare array or `{ "data": [ ... ] }`.
    let models: Vec<TogetherModelJson> = match serde_json::from_slice::<Vec<TogetherModelJson>>(&body)
    {
        Ok(v) => v,
        Err(_) => match serde_json::from_slice::<serde_json::Value>(&body) {
            Ok(serde_json::Value::Object(map)) => map
                .get("data")
                .and_then(|d| serde_json::from_value(d.clone()).ok())
                .unwrap_or_default(),
            _ => {
                tracing::warn!("together pricing: unexpected models JSON shape");
                return;
            }
        },
    };

    let mut rates = HashMap::new();
    for m in models {
        let Some(id) = m.id.filter(|s| !s.is_empty()) else {
            continue;
        };
        let Some(p) = m.pricing else {
            continue;
        };
        if p.input <= 0.0 && p.output <= 0.0 {
            continue;
        }
        let cached = if p.cached_input > 0.0 {
            p.cached_input
        } else {
            p.input
        };
        rates.insert(
            id,
            ModelRates {
                input_per_mtok: p.input,
                output_per_mtok: p.output,
                cached_input_per_mtok: cached,
            },
        );
    }

    let count = rates.len();
    let mut guard = cache().lock().unwrap_or_else(|e| e.into_inner());
    guard.rates = rates;
    guard.fetched_at = Some(Instant::now());
    guard.base_url = Some(base_url.to_string());
    tracing::info!(models = count, url = %url, "together pricing: catalog cached");
}

/// Look up cached rates for a model id (exact match, then case-insensitive).
pub fn together_rates_for(model_id: &str) -> Option<ModelRates> {
    let guard = cache().lock().unwrap_or_else(|e| e.into_inner());
    if let Some(r) = guard.rates.get(model_id) {
        return Some(*r);
    }
    let lower = model_id.to_ascii_lowercase();
    guard
        .rates
        .iter()
        .find(|(k, _)| k.eq_ignore_ascii_case(&lower))
        .map(|(_, r)| *r)
}

/// Estimate cost in USD ticks from token usage and Together rates.
///
/// Returns `None` when rates are unknown or the estimate rounds to zero.
pub fn estimate_together_cost_ticks(model_id: &str, usage: &TokenUsage) -> Option<i64> {
    let rates = together_rates_for(model_id)?;
    let cached = u64::from(usage.cached_prompt_tokens) as f64;
    let uncached = u64::from(usage.prompt_tokens.saturating_sub(usage.cached_prompt_tokens)) as f64;
    let output = u64::from(usage.completion_tokens) as f64;
    let usd = (uncached / 1_000_000.0) * rates.input_per_mtok
        + (cached / 1_000_000.0) * rates.cached_input_per_mtok
        + (output / 1_000_000.0) * rates.output_per_mtok;
    let ticks = (usd * USD_TICKS_PER_USD).round() as i64;
    if ticks > 0 { Some(ticks) } else { None }
}

/// If wire cost is missing and this is a Together endpoint, fill an estimate.
pub fn maybe_estimate_together_cost(
    base_url: &str,
    model_id: &str,
    usage: Option<&TokenUsage>,
    wire_cost_ticks: Option<i64>,
) -> Option<i64> {
    if let Some(c) = xai_grok_sampling_types::reported_cost_ticks(wire_cost_ticks) {
        return Some(c);
    }
    if !is_together_base_url(base_url) {
        return None;
    }
    let usage = usage?;
    let ticks = estimate_together_cost_ticks(model_id, usage)?;
    tracing::info!(
        model = %model_id,
        prompt_tokens = usage.prompt_tokens,
        completion_tokens = usage.completion_tokens,
        cached_prompt_tokens = usage.cached_prompt_tokens,
        estimated_cost_usd = ticks as f64 / USD_TICKS_PER_USD,
        "together pricing: estimated turn cost (not a bill of record)"
    );
    Some(ticks)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_together_hosts() {
        assert!(is_together_base_url("https://api.together.ai/v1"));
        assert!(is_together_base_url("https://api.together.xyz/v1/"));
        assert!(!is_together_base_url("https://api.openai.com/v1"));
        assert!(!is_together_base_url("https://cli-chat-proxy.grok.com/v1"));
    }

    #[test]
    fn estimate_matches_published_minimax_rates() {
        {
            let mut g = cache().lock().unwrap();
            g.rates.insert(
                "MiniMaxAI/MiniMax-M3".into(),
                ModelRates {
                    input_per_mtok: 0.30,
                    output_per_mtok: 1.20,
                    cached_input_per_mtok: 0.06,
                },
            );
            g.fetched_at = Some(Instant::now());
        }
        // 1M uncached in + 1M out = $0.30 + $1.20 = $1.50
        let usage = TokenUsage {
            prompt_tokens: 1_000_000,
            completion_tokens: 1_000_000,
            total_tokens: 2_000_000,
            reasoning_tokens: 0,
            cached_prompt_tokens: 0,
        };
        let ticks = estimate_together_cost_ticks("MiniMaxAI/MiniMax-M3", &usage).unwrap();
        let usd = ticks as f64 / USD_TICKS_PER_USD;
        assert!((usd - 1.5).abs() < 1e-6, "usd={usd}");

        // 500k cached + 500k uncached in + 0 out
        // = 0.5*0.30 + 0.5*0.06 = 0.15 + 0.03 = 0.18
        let usage2 = TokenUsage {
            prompt_tokens: 1_000_000,
            completion_tokens: 0,
            total_tokens: 1_000_000,
            reasoning_tokens: 0,
            cached_prompt_tokens: 500_000,
        };
        let ticks2 = estimate_together_cost_ticks("MiniMaxAI/MiniMax-M3", &usage2).unwrap();
        let usd2 = ticks2 as f64 / USD_TICKS_PER_USD;
        assert!((usd2 - 0.18).abs() < 1e-6, "usd2={usd2}");
    }
}
