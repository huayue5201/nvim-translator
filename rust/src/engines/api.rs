use serde_json::Value;

use super::base;
use crate::Translation;

const DEFAULT_TIMEOUT_SECS: u64 = 60;

fn env(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.is_empty())
}

/// API-documentation engine.
///
/// Reuses the OpenAI-compatible LLM configuration (the same env vars as the
/// `llm` engine, set by the Lua side from `vim.g.translator_llm`), but prompts
/// the model to treat the input as a code API symbol: explain it and translate
/// the human-language descriptions.
///
/// The source language (`sl`) is repurposed as the programming-language hint
/// (e.g. "python", "rust", "javascript"), supplied by the Lua side from the
/// current buffer's filetype.
pub fn translate(
    client: &reqwest::blocking::Client,
    sl: &str,
    tl: &str,
    text: &str,
) -> Translation {
    let mut res = base("api", sl, tl, text);

    let (Some(base_url), Some(model)) =
        (env("TRANSLATOR_LLM_BASE_URL"), env("TRANSLATOR_LLM_MODEL"))
    else {
        res.paraphrase = "[api] missing LLM config (set llm in setup())".to_string();
        return res;
    };

    let api_key = env("TRANSLATOR_LLM_API_KEY").unwrap_or_default();
    let timeout = env("TRANSLATOR_LLM_TIMEOUT")
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(DEFAULT_TIMEOUT_SECS);
    let prompt = default_prompt(sl, tl);

    if let Some(content) = super::llm::call_llm(client, &base_url, &model, &api_key, &prompt, sl, tl, text, timeout)
    {
        parse_content(&content, &mut res);
    }

    // 主端点无有效结果时，尝试降级端点（与 llm 引擎一致）。
    // api 引擎始终使用自己的专用 prompt，不继承翻译 prompt。
    if res.paraphrase.is_empty() && res.explains.is_empty() {
        if let (Some(fb_url), Some(fb_model)) = (
            env("TRANSLATOR_LLM_FALLBACK_BASE_URL"),
            env("TRANSLATOR_LLM_FALLBACK_MODEL"),
        ) {
            let fb_key = env("TRANSLATOR_LLM_FALLBACK_API_KEY").unwrap_or_default();
            let fb_timeout = env("TRANSLATOR_LLM_FALLBACK_TIMEOUT")
                .and_then(|v| v.parse::<u64>().ok())
                .unwrap_or(timeout);
            let fb_prompt = simple_prompt(sl, tl);
            if let Some(content) = super::llm::call_llm(client, &fb_url, &fb_model, &fb_key, &fb_prompt, sl, tl, text, fb_timeout)
            {
                parse_content(&content, &mut res);
            }
        }
    }

    res
}

fn default_prompt(lang: &str, tl: &str) -> String {
    format!(
        "You are a programming API documentation engine. The user gives a symbol \
         (or a short snippet) from the \"{lang}\" language/framework.\n\
         Reply with ONLY a JSON object (no markdown fences, no commentary) in this exact shape:\n\
         {{\"paraphrase\":\"...\",\"explains\":[\"...\"]}}\n\
         - paraphrase: a one-sentence summary of what the API does, translated into {tl}.\n\
         - explains: an array of strings, only for the sections that apply, in this order:\n\
           1. \"签名: <signature>\" — the exact signature / call form, kept verbatim.\n\
           2. \"参数: <param> — <description translated into {tl}>\"\n\
           3. \"返回值: <description translated into {tl}>\"\n\
           4. \"示例: <code>\" — a short usage example, code kept verbatim.\n\
           5. \"备注: <notes translated into {tl}>\" — deprecation / version / caveats.\n\
         Rules:\n\
         - Keep code, signatures, identifiers and parameter names verbatim; \
           only translate human-language descriptions into {tl}.\n\
         - If the input is NOT a code API (e.g. a plain word or prose), translate \
           it normally instead: put the translation in \"paraphrase\" and use an \
           empty \"explains\" array.",
        lang = lang,
        tl = tl
    )
}

/// 简化版 prompt：供降级端点（通常是本地小模型）使用。
/// 本地 7B 模型难以稳定输出上面的 5 段结构化格式，故简化为
/// 「概述 + 若干要点」，仍要求输出合法 JSON。
fn simple_prompt(lang: &str, tl: &str) -> String {
    format!(
        "You are a programming API documentation engine. The user gives a code symbol \
         from the \"{lang}\" language/framework.\n\
         Reply with ONLY a JSON object (no markdown fences, no commentary) in this exact shape:\n\
         {{\"paraphrase\":\"...\",\"explains\":[\"...\"]}}\n\
         - \"paraphrase\": a one-sentence summary of what the symbol does, translated into {tl}.\n\
         - \"explains\": 1 to 3 short strings about the symbol, e.g. its signature, key \
           parameters, or return value. Keep code verbatim; translate human-language \
           descriptions into {tl}.\n\
         If the input is NOT a code API, translate it normally and use an empty \"explains\" array.",
        lang = lang,
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
        assert_eq!(
            strip_fences("{\"paraphrase\":\"hi\"}"),
            "{\"paraphrase\":\"hi\"}"
        );
    }

    #[test]
    fn parses_structured_api_response() {
        let mut res = base("api", "python", "zh", "str.replace");
        parse_content(
            r#"{"paraphrase":"将字符串中的指定子串替换为新值。","explains":[
                "签名: str.replace(old, new[, count])",
                "参数: old — 要被替换的旧子串",
                "返回值: 返回替换后的新字符串",
                "示例: s.replace(\"a\", \"b\")"
            ]}"#,
            &mut res,
        );

        assert_eq!(res.paraphrase, "将字符串中的指定子串替换为新值。");
        assert_eq!(res.explains.len(), 4);
        assert_eq!(res.explains[0], "签名: str.replace(old, new[, count])");
    }

    #[test]
    fn falls_back_to_plain_text() {
        let mut res = base("api", "python", "zh", "hello");
        parse_content("你好", &mut res);
        assert_eq!(res.paraphrase, "你好");
    }
}
