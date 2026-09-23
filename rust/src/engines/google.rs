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

    let Ok(resp) = client.get(&url).send() else {
        return res;
    };
    let Ok(body) = resp.text() else {
        return res;
    };
    let Ok(obj) = serde_json::from_str::<Value>(&body) else {
        return res;
    };

    parse(obj, &mut res);
    res
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

    // obj[5]: alternatives
    if let Some(alts) = obj.get(5).and_then(|v| v.as_array()) {
        let base_paraphrase = res.paraphrase.clone();
        for alt in alts {
            if let Some(means) = alt.get(2).and_then(|v| v.as_array()) {
                for m in means {
                    if let Some(s) = first_of(m) {
                        if !s.is_empty() && s != base_paraphrase {
                            res.alternative.push(format!("* {}", s));
                        }
                    }
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
            null,
            [
                [["感叹词"], ["hello"], [["你好"], ["您好"]]]
            ]
        ]);

        let mut res = base("google", "en", "zh", "hello world");
        parse(json, &mut res);

        assert_eq!(res.paraphrase, "你好，世界");
        assert_eq!(res.phonetic, "həˈloʊ");
        assert_eq!(res.explains, vec!["[感叹词] 你好;喂"]);
        assert_eq!(res.alternative, vec!["* 你好", "* 您好"]);
    }
}
