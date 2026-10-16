use std::collections::HashMap;

use serde_json::Value;

use super::base;
use crate::Translation;

const SUG_URL: &str = "https://fanyi.baidu.com/sug";
const API_URL: &str = "https://fanyi-api.baidu.com/api/trans/vip/translate";

/// Translate with Baidu.
///
/// When `TRANSLATOR_BAIDU_APPID` + `TRANSLATOR_BAIDU_KEY` are set (official
/// Translation API), full sentences are supported. Without credentials we fall
/// back to the free `/sug` dictionary endpoint, which is word-only.
pub fn translate(
    client: &reqwest::blocking::Client,
    sl: &str,
    tl: &str,
    text: &str,
) -> Translation {
    let res = base("baidu", sl, tl, text);

    let appid = std::env::var("TRANSLATOR_BAIDU_APPID").unwrap_or_default();
    let key = std::env::var("TRANSLATOR_BAIDU_KEY").unwrap_or_default();

    if !appid.is_empty() && !key.is_empty() {
        return translate_official(client, sl, tl, text, &appid, &key, res);
    }

    let mut res = translate_sug(client, text, res);
    if res.explains.is_empty() && res.paraphrase.is_empty() && res.error.is_none() {
        // The free /sug endpoint is word-only; full sentences always come back
        // empty here, so point at the real fix (official API credentials).
        res.error = if text.split_whitespace().count() > 1 {
            Some("no API credentials: /sug is word-only (set BAIDU_APPID/BAIDU_KEY for sentences)".to_string())
        } else {
            Some("no result from /sug".to_string())
        };
    }
    res
}

/// Official API: https://fanyi-api.baidu.com/api/trans/vip/translate
/// sign = md5(appid + q + salt + key)
fn translate_official(
    client: &reqwest::blocking::Client,
    sl: &str,
    tl: &str,
    text: &str,
    appid: &str,
    key: &str,
    mut res: Translation,
) -> Translation {
    let salt = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis().to_string())
        .unwrap_or_else(|_| "1".to_string());
    let sign = format!(
        "{:x}",
        md5::compute(format!("{}{}{}{}", appid, text, salt, key))
    );

    let from = if sl.is_empty() { "auto" } else { sl };
    let to = if tl.is_empty() { "zh" } else { tl };

    let form = [
        ("q", text),
        ("from", from),
        ("to", to),
        ("appid", appid),
        ("salt", salt.as_str()),
        ("sign", sign.as_str()),
    ];

    let resp = match client.post(API_URL).form(&form).send() {
        Ok(r) => r,
        Err(e) => {
            res.error = Some(format!("request failed: {}", e));
            return res;
        }
    };
    let status = resp.status();
    let obj = match resp.json::<Value>() {
        Ok(o) => o,
        Err(e) => {
            res.error = Some(format!("HTTP {}: {}", status.as_u16(), e));
            return res;
        }
    };

    parse_official(obj, &mut res);
    if res.paraphrase.is_empty() && res.error.is_none() {
        res.error = Some("official API returned no translation".to_string());
    }
    res
}

fn parse_official(obj: Value, res: &mut Translation) {
    if let Some(err) = obj.get("error_code").and_then(|v| v.as_str()) {
        let msg = obj
            .get("error_msg")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        res.error = Some(format!("baidu api error {}: {}", err, msg));
        return;
    }

    if let Some(items) = obj.get("trans_result").and_then(|v| v.as_array()) {
        let parts: Vec<&str> = items
            .iter()
            .filter_map(|it| it.get("dst").and_then(|v| v.as_str()))
            .filter(|s| !s.is_empty())
            .collect();
        res.paraphrase = parts.join("\n");
    }
}

/// Free dictionary endpoint (word-only fallback).
fn translate_sug(
    client: &reqwest::blocking::Client,
    text: &str,
    mut res: Translation,
) -> Translation {
    let mut form = HashMap::new();
    form.insert("kw", text);

    let resp = match client.post(SUG_URL).form(&form).send() {
        Ok(r) => r,
        Err(e) => {
            res.error = Some(format!("request failed: {}", e));
            return res;
        }
    };
    let status = resp.status();
    let obj = match resp.json::<Value>() {
        Ok(o) => o,
        Err(e) => {
            res.error = Some(format!("HTTP {}: {}", status.as_u16(), e));
            return res;
        }
    };

    parse_sug(obj, &mut res);
    res
}

fn parse_sug(obj: Value, res: &mut Translation) {
    if let Some(data) = obj.get("data").and_then(|v| v.as_array()) {
        res.explains = data
            .iter()
            .filter_map(|item| item.get("v").and_then(|v| v.as_str()))
            .filter(|s| !s.is_empty())
            .map(|s| s.to_string())
            .collect();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_baidu_sug_response() {
        let json = serde_json::json!({
            "data": [{"k": "hello", "v": "int. 你好"}, {"k": "hello", "v": "n. 问候"}]
        });

        let mut res = base("baidu", "", "", "hello");
        parse_sug(json, &mut res);

        assert_eq!(res.explains, vec!["int. 你好", "n. 问候"]);
    }

    #[test]
    fn parses_baidu_official_response() {
        let json = serde_json::json!({
            "from": "en",
            "to": "zh",
            "trans_result": [
                {"src": "how are you", "dst": "你好吗"},
                {"src": "today", "dst": "今天"}
            ]
        });

        let mut res = base("baidu", "en", "zh", "how are you today");
        parse_official(json, &mut res);

        assert_eq!(res.paraphrase, "你好吗\n今天");
    }

    #[test]
    fn official_error_leaves_result_empty() {
        let json = serde_json::json!({
            "error_code": "54001",
            "error_msg": "Invalid Sign"
        });

        let mut res = base("baidu", "en", "zh", "hello");
        parse_official(json, &mut res);

        assert!(res.paraphrase.is_empty());
        assert!(res.error.unwrap().contains("54001"));
    }
}
