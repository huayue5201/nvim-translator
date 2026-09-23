use std::collections::HashMap;

use serde_json::Value;

use super::base;
use crate::Translation;

pub fn translate(client: &reqwest::blocking::Client, text: &str) -> Translation {
    let mut res = base("baidu", "", "", text);

    let mut form = HashMap::new();
    form.insert("kw", text);

    let Ok(resp) = client
        .post("https://fanyi.baidu.com/sug")
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
    fn parses_baidu_response() {
        let json = serde_json::json!({
            "data": [{"k": "hello", "v": "int. 你好"}, {"k": "hello", "v": "n. 问候"}]
        });

        let mut res = base("baidu", "", "", "hello");
        parse(json, &mut res);

        assert_eq!(res.explains, vec!["int. 你好", "n. 问候"]);
    }
}
