use serde_json::Value;
use urlencoding::encode;

use super::base;
use crate::Translation;

pub fn translate(
    client: &reqwest::blocking::Client,
    sl: &str,
    tl: &str,
    text: &str,
) -> Translation {
    let mut res = base("google", sl, tl, text);

    let url = format!(
        "https://translate.googleapis.com/translate_a/single?client=gtx&sl={}&tl={}&dt=t&dt=bd&dt=ex&q={}",
        encode(sl),
        encode(tl),
        encode(text)
    );

    let resp = match client.get(&url).send() {
        Ok(r) => r,
        Err(e) => {
            res.error = Some(format!("request failed: {}", e));
            return res;
        }
    };
    let status = resp.status();
    let body = match resp.text() {
        Ok(b) => b,
        Err(e) => {
            res.error = Some(format!("failed to read response: {}", e));
            return res;
        }
    };
    let obj = match serde_json::from_str::<Value>(&body) {
        Ok(o) => o,
        Err(_) => {
            res.error = Some(format!("HTTP {}: {}", status.as_u16(), short(&body)));
            return res;
        }
    };

    parse(obj, &mut res);
    if res.paraphrase.is_empty() && res.explains.is_empty() && res.phonetic.is_empty() {
        res.error = Some(format!("empty response (HTTP {})", status.as_u16()));
    }
    res
}

/// Shorten a response body for error messages.
fn short(s: &str) -> String {
    let t = s.trim();
    if t.chars().count() <= 160 {
        t.to_string()
    } else {
        let mut out: String = t.chars().take(160).collect();
        out.push('…');
        out
    }
}

/// Mirror of Python's `v[0]`: first element for arrays, whole value for strings.
/// (Python's `s[0]` on a string returns only the first char, which was a latent
/// bug for the part-of-speech field; using the whole string is strictly better.)
fn first_of(v: &Value) -> Option<String> {
    match v {
        Value::Array(a) => a.first().and_then(|x| x.as_str()).map(|s| s.to_string()),
        Value::String(s) => Some(s.clone()),
        _ => None,
    }
}

fn parse(obj: Value, res: &mut Translation) {
    // obj[0]: translation segments [[translated, original, ...], ...]
    if let Some(segments) = obj.get(0).and_then(|v| v.as_array()) {
        let mut paraphrase = String::new();
        for seg in segments {
            if let Some(s) = seg.get(0).and_then(|v| v.as_str()) {
                paraphrase.push_str(s);
            }
            if res.phonetic.is_empty() {
                if let Some(phon) = seg.get(3).and_then(|v| v.as_str()) {
                    if !phon.is_empty() {
                        res.phonetic = phon.to_string();
                    }
                }
            }
        }
        res.paraphrase = paraphrase;
    }

    // obj[1]: dictionary entries [[pos, [terms], [[mean, ...], ...]], ...]
    if let Some(dict) = obj.get(1).and_then(|v| v.as_array()) {
        for entry in dict {
            let pos = entry.get(0).and_then(first_of);
            let means = entry.get(2).and_then(|v| v.as_array());
            if let (Some(pos), Some(means)) = (pos, means) {
                let parts: Vec<String> = means
                    .iter()
                    .filter_map(first_of)
                    .filter(|s| !s.is_empty())
                    .collect();
                if !parts.is_empty() {
                    res.explains.push(format!("[{}] {}", pos, parts.join(";")));
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_google_response() {
        let json = serde_json::json!([
            [
                ["你好", "hello", null, null],
                ["，世界", ", world", null, "həˈloʊ"]
            ],
            [
                [["感叹词"], ["hello"], [["你好"], ["喂"]]]
            ],
            null,
            null,
            null
        ]);

        let mut res = base("google", "en", "zh", "hello world");
        parse(json, &mut res);

        assert_eq!(res.paraphrase, "你好，世界");
        assert_eq!(res.phonetic, "həˈloʊ");
        assert_eq!(res.explains, vec!["[感叹词] 你好;喂"]);
    }
}
