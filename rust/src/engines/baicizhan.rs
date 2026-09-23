use serde_json::Value;
use urlencoding::encode;

use super::base;
use crate::Translation;

pub fn translate(client: &reqwest::blocking::Client, text: &str) -> Translation {
    let mut res = base("baicizhan", "", "", text);

    let url = format!(
        "http://mall.baicizhan.com/ws/search?w={}",
        encode(text)
    );

    let Ok(resp) = client.get(&url).send() else {
        return res;
    };
    let Ok(obj) = resp.json::<Value>() else {
        return res;
    };

    if let Some(mean) = obj.get("mean_cn").and_then(|v| v.as_str()) {
        if !mean.is_empty() {
            res.explains.push(mean.to_string());
        }
    }

    res
}
