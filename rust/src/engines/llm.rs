use std::time::Duration;

use serde_json::{json, Value};

use super::base;
use crate::Translation;

const DEFAULT_TIMEOUT_SECS: u64 = 60;

fn env(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.is_empty())
}

/// Generic OpenAI-compatible LLM engine. Configuration is passed via
/// environment variables (set by the Lua side through `jobstart`), never via
/// argv, so the API key cannot leak into logs or the process list.
///
/// Env vars:
///   TRANSLATOR_LLM_BASE_URL  (required)
///   TRANSLATOR_LLM_MODEL     (required)
///   TRANSLATOR_LLM_API_KEY   (optional; omitted for local endpoints like ollama)
///   TRANSLATOR_LLM_PROMPT    (optional; supports {sl} and {tl} placeholders)
///   TRANSLATOR_LLM_TIMEOUT   (optional; seconds, default 60)
pub fn translate(
    client: &reqwest::blocking::Client,
    sl: &str,
    tl: &str,
    text: &str,
) -> Translation {
    let mut res = base("llm", sl, tl, text);

    let (Some(base_url), Some(model)) =
        (env("TRANSLATOR_LLM_BASE_URL"), env("TRANSLATOR_LLM_MODEL"))
    else {
        res.paraphrase = "[llm] missing base_url/model config".to_string();
        return res;
    };

    let api_key = env("TRANSLATOR_LLM_API_KEY").unwrap_or_default();
    let timeout = env("TRANSLATOR_LLM_TIMEOUT")
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(DEFAULT_TIMEOUT_SECS);

    let system_prompt = match env("TRANSLATOR_LLM_PROMPT") {
        Some(p) => p.replace("{sl}", sl).replace("{tl}", tl),
        None => default_prompt(sl, tl),
    };

    let url = format!("{}/chat/completions", base_url.trim_end_matches('/'));

    let body = json!({
        "model": model,
        "stream": false,
        "temperature": 0.2,
        "messages": [
            { "role": "system", "content": system_prompt },
            { "role": "user", "content": text },
        ],
    });

    let mut req = client
        .post(&url)
        .timeout(Duration::from_secs(timeout));

    if !api_key.is_empty() {
        req = req.header("Authorization", format!("Bearer {}", api_key));
    }

    let Ok(resp) = req.json(&body).send() else {
        return res;
    };
    let Ok(obj) = resp.json::<Value>() else {
        return res;
    };

    let content = obj
        .pointer("/choices/0/message/content")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    parse_content(content, &mut res);
    res
}

fn default_prompt(sl: &str, tl: &str) -> String {
    format!(
        "You are a professional translation engine. Translate the user's text from {sl} to {tl}.\n\
         Reply with ONLY a JSON object (no markdown fences, no extra commentary) in this exact shape:\n\
         {{\"paraphrase\":\"...\",\"explains\":[\"...\"],\"phonetic\":\"...\"}}\n\
         - paraphrase: the translation\n\
         - explains: dictionary-style explanations as an array of strings (use [] if not applicable)\n\
         - phonetic: pronunciation guide (use \"\" if not applicable)",
        sl = sl,
        tl = tl
    )
}

/// Strip ```json ... ``` fences that many models add despite instructions.
fn strip_fences(content: &str) -> String {
    let s = content.trim();
    if s.starts_with("```") {
        let body = s.find('\n').map(|i| &s[i + 1..]).unwrap_or("");
        let body = match body.rfind("```") {
            Some(i) => &body[..i],
            None => body,
        };
        body.trim().to_string()
    } else {
        s.to_string()
    }
}

fn parse_content(content: &str, res: &mut Translation) {
    let text = strip_fences(content);

    match serde_json::from_str::<Value>(&text) {
        Ok(obj) => {
            if let Some(p) = obj.get("paraphrase").and_then(|v| v.as_str()) {
                res.paraphrase = p.to_string();
            }
            if let Some(arr) = obj.get("explains").and_then(|v| v.as_array()) {
                res.explains = arr
                    .iter()
                    .filter_map(|v| v.as_str())
                    .filter(|s| !s.is_empty())
                    .map(|s| s.to_string())
                    .collect();
            }
            if let Some(ph) = obj.get("phonetic").and_then(|v| v.as_str()) {
                res.phonetic = ph.to_string();
            }

            // JSON parsed but produced nothing useful: fall back to raw text.
            if res.paraphrase.is_empty() && res.explains.is_empty() {
                if let Some(s) = obj.as_str() {
                    res.paraphrase = s.to_string();
                } else {
                    res.paraphrase = text;
                }
            }
        }
        Err(_) => {
            // Not JSON at all: treat the whole response as the translation.
            if !text.is_empty() {
                res.paraphrase = text;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_markdown_fences() {
        assert_eq!(
            strip_fences("```json\n{\"paraphrase\":\"hi\"}\n```"),
            "{\"paraphrase\":\"hi\"}"
        );
        assert_eq!(strip_fences("{\"paraphrase\":\"hi\"}"), "{\"paraphrase\":\"hi\"}");
    }

    #[test]
    fn parses_structured_json() {
        let mut res = base("llm", "en", "zh", "hello");
        parse_content(
            r#"{"paraphrase":"你好","explains":["int. 你好"],"phonetic":"həˈloʊ"}"#,
            &mut res,
        );
        assert_eq!(res.paraphrase, "你好");
        assert_eq!(res.explains, vec!["int. 你好"]);
        assert_eq!(res.phonetic, "həˈloʊ");
    }

    #[test]
    fn falls_back_to_plain_text() {
        let mut res = base("llm", "en", "zh", "hello");
        parse_content("你好", &mut res);
        assert_eq!(res.paraphrase, "你好");

        let mut res2 = base("llm", "en", "zh", "hello");
        parse_content("```\n你好\n```", &mut res2);
        assert_eq!(res2.paraphrase, "你好");
    }
}
