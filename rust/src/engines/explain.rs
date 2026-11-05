use super::base;
use crate::Translation;

const DEFAULT_TIMEOUT_SECS: u64 = 60;

fn env(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.is_empty())
}

/// Code-explanation engine (`:TranslateExplain`).
///
/// Reuses the OpenAI-compatible LLM configuration of the `llm` engine, but
/// prompts the model to *explain* a code snippet so the reader can quickly
/// understand unfamiliar code. The source language (`sl`) is the programming
/// language from the buffer's filetype; the answer is written in `tl`.
pub fn translate(
    client: &reqwest::blocking::Client,
    sl: &str,
    tl: &str,
    text: &str,
) -> Translation {
    let mut res = base("explain", sl, tl, text);

    let (Some(base_url), Some(model)) =
        (env("TRANSLATOR_LLM_BASE_URL"), env("TRANSLATOR_LLM_MODEL"))
    else {
        res.error = Some("[explain] missing LLM config (set llm in setup())".to_string());
        return res;
    };

    let api_key = env("TRANSLATOR_LLM_API_KEY").unwrap_or_default();
    let timeout = env("TRANSLATOR_LLM_TIMEOUT")
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(DEFAULT_TIMEOUT_SECS);
    let prompt = default_prompt(sl, tl);

    let mut reasons: Vec<String> = Vec::new();

    match super::llm::call_llm(client, &base_url, &model, &api_key, &prompt, sl, tl, text, timeout) {
        Ok(content) => super::api::parse_content(&content, &mut res),
        Err(e) => reasons.push(format!("primary: {}", e)),
    }

    // Same fallback behaviour as the `api` engine: retry the fallback endpoint
    // with a simpler prompt that small local models can follow reliably.
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
            match super::llm::call_llm(
                client, &fb_url, &fb_model, &fb_key, &fb_prompt, sl, tl, text, fb_timeout,
            ) {
                Ok(content) => super::api::parse_content(&content, &mut res),
                Err(e) => reasons.push(format!("fallback: {}", e)),
            }
        }
    }

    if res.paraphrase.is_empty()
        && res.explains.is_empty()
        && res.error.is_none()
        && !reasons.is_empty()
    {
        res.error = Some(reasons.join("; "));
    }

    res
}

fn default_prompt(lang: &str, tl: &str) -> String {
    format!(
        "You are a senior software engineer helping a teammate understand an \
         unfamiliar codebase. The user gives a code snippet from the \"{lang}\" \
         language/framework, copied from its source file.\n\
         Explain what the code does and why it exists — do NOT translate it line by line.\n\
         Reply with ONLY a JSON object (no markdown fences, no commentary) in this exact shape:\n\
         {{\"paraphrase\":\"...\",\"explains\":[\"...\"]}}\n\
         - paraphrase: ONE sentence in {tl} saying what this code does and why it exists.\n\
         - explains: 2 to 6 self-contained strings in {tl}, each covering one of these \
           points (skip any that do not apply), in this order:\n\
           1. \"作用: ...\" — what it does, its inputs/outputs and side effects.\n\
           2. \"流程: ...\" — the key steps of the implementation, in execution order.\n\
           3. \"关键点: ...\" — non-obvious logic, invariants, edge cases, error handling.\n\
           4. \"注意: ...\" — pitfalls, complexity, concurrency, performance or security concerns.\n\
           5. \"相关: ...\" — related symbols/files worth reading next, kept verbatim.\n\
         Rules:\n\
         - Explain, do not restate the code.\n\
         - Keep identifiers, function names, file paths and code fragments verbatim; \
           write the prose in {tl}.\n\
         - Be concrete and concise. If the snippet is too short or ambiguous to explain, \
           say exactly what additional context is needed.",
        lang = lang,
        tl = tl
    )
}

/// Simplified prompt for the fallback endpoint (usually a small local model).
fn simple_prompt(lang: &str, tl: &str) -> String {
    format!(
        "You are a senior software engineer. The user gives a code snippet from the \
         \"{lang}\" language/framework. Explain what it does in {tl}.\n\
         Reply with ONLY a JSON object (no markdown fences, no commentary) in this exact shape:\n\
         {{\"paraphrase\":\"...\",\"explains\":[\"...\"]}}\n\
         - \"paraphrase\": one sentence in {tl} summarizing what the code does.\n\
         - \"explains\": 1 to 3 short strings in {tl} about its key logic, inputs/outputs, \
           or pitfalls. Keep identifiers and code verbatim.\n\
         Explain, do not translate the code line by line.",
        lang = lang,
        tl = tl
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prompt_mentions_language_and_target() {
        let p = default_prompt("rust", "zh");
        assert!(p.contains("rust"));
        assert!(p.contains("zh"));
        assert!(p.contains("paraphrase"));
        assert!(p.contains("explains"));
    }
}
