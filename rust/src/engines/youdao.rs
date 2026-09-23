use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::Value;

use super::base;
use crate::Translation;

pub fn translate(
    client: &reqwest::blocking::Client,
    sl: &str,
    tl: &str,
    text: &str,
) -> Translation {
    let mut res = base("youdao", sl, tl, text);

    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    let salt = format!("{}{}", millis, millis % 11);

    let sign_input = format!("fanyideskweb{}{}{}", text, salt, "97_3(jkMYg@T[KZQmqjTK");
    let sign = format!("{:x}", md5::compute(sign_input.as_bytes()));

    let mut form = HashMap::new();
    form.insert("i", text);
    form.insert("from", sl);
    form.insert("to", tl);
    form.insert("smartresult", "dict");
    form.insert("client", "fanyideskweb");
    form.insert("salt", &salt);
    form.insert("sign", &sign);
    form.insert("doctype", "json");
    form.insert("version", "2.1");
    form.insert("action", "FY_BY_CL1CKBUTTON");

    let Ok(resp) = client
        .post("https://fanyi.youdao.com/translate_o")
        .header("Referer", "http://fanyi.youdao.com/")
        .header("Cookie", "OUTFOX_SEARCH_USER_ID=-2022895048@10.168.8.76;")
        .form(&form)
        .send()
    else {
        return res;
    };
    let Ok(obj) = resp.json::<Value>() else {
        return res;
    };

    parse(obj, &mut res);
    res
}

fn parse(obj: Value, res: &mut Translation) {
    // translateResult: [[{tgt: ...}, ...], ...]
    if let Some(tr) = obj.get("translateResult").and_then(|v| v.as_array()) {
        let mut parts = Vec::new();
        for n in tr {
            if let Some(arr) = n.as_array() {
                for m in arr {
                    if let Some(tgt) = m.get("tgt").and_then(|v| v.as_str()) {
                        parts.push(tgt.to_string());
                    }
                }
            }
        }
        res.paraphrase = parts.join(", ");
    }

    if let Some(entries) = obj.pointer("/smartResult/entries").and_then(|v| v.as_array()) {
        res.explains = entries
            .iter()
            .filter_map(|e| e.as_str())
            .map(|s| s.replace('\r', "").replace('\n', ""))
            .filter(|s| !s.trim().is_empty())
            .map(|s| s.to_string())
            .collect();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_youdao_response() {
        let json = serde_json::json!({
            "translateResult": [[{"tgt": "你好"}, {"tgt": "世界"}]],
            "smartResult": {"entries": ["你好", "您好"]}
        });

        let mut res = base("youdao", "en", "zh", "hello");
        parse(json, &mut res);

        assert_eq!(res.paraphrase, "你好, 世界");
        assert_eq!(res.explains, vec!["你好", "您好"]);
    }
}
