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
    let mut res = base("bing", sl, tl, text);

    let url = format!(
        "https://www.bing.com/ttranslatev3?from={}&to={}&text={}",
        encode(sl),
        encode(tl),
        encode(text)
    );

    let Ok(resp) = client.get(&url).send() else {
        return res;
    };
    let Ok(obj) = resp.json::<Value>() else {
        return res;
    };

    if let Some(t) = obj
        .as_array()
        .and_then(|arr| arr.first())
        .and_then(|v| v.get("translations"))
        .and_then(|v| v.as_array())
        .and_then(|arr| arr.first())
        .and_then(|v| v.get("text"))
        .and_then(|v| v.as_str())
    {
        res.paraphrase = t.to_string();
    }

    res
}
