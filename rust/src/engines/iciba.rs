use serde_json::Value;
use urlencoding::encode;

use super::base;
use crate::Translation;

pub fn translate(client: &reqwest::blocking::Client, text: &str) -> Translation {
    let mut res = base("iciba", "", "", text);

    let url = format!(
        "http://www.iciba.com/index.php?a=getWordMean&c=search&word={}",
        encode(text)
    );

    let Ok(resp) = client.get(&url).send() else {
        return res;
    };
    let Ok(obj) = resp.json::<Value>() else {
        return res;
    };

    if let Some(sym) = obj.pointer("/baesInfo/symbols/0") {
        if let Some(parts) = sym.get("parts").and_then(|v| v.as_array()) {
            for p in parts {
                let part = p.get("part").and_then(|v| v.as_str()).unwrap_or("");
                if let Some(means) = p.get("means").and_then(|v| v.as_array()) {
                    for m in means {
                        if let Some(s) = m.as_str() {
                            res.explains.push(format!("{}: {}", part, s));
                        }
                    }
                }
            }
        }
        if let Some(ph) = sym.get("ph_en").and_then(|v| v.as_str()) {
            res.phonetic = ph.to_string();
        }
    }

    res
}
