use regex::Regex;
use urlencoding::encode;

use super::base;
use crate::Translation;

pub fn translate(client: &reqwest::blocking::Client, text: &str) -> Translation {
    let mut res = base("haici", "", "", text);

    let url = format!("http://dict.cn/mini.php?q={}", encode(text));

    let Ok(resp) = client.get(&url).send() else {
        return res;
    };
    let Ok(body) = resp.text() else {
        return res;
    };

    let Ok(re) = Regex::new(r#"<div id="e">(.*?)</div>"#) else {
        return res;
    };

    for cap in re.captures_iter(&body) {
        if let Some(inner) = cap.get(1) {
            for part in inner.as_str().split("<br>") {
                let p = part.trim();
                if !p.is_empty() {
                    res.explains.push(p.to_string());
                }
            }
        }
    }

    res
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_haici_response() {
        let html = r#"<div id="e">n. 你好<br>int. 喂<br>   </div>"#;
        let re = Regex::new(r#"<div id="e">(.*?)</div>"#).unwrap();
        let mut res = base("haici", "", "", "hello");

        for cap in re.captures_iter(html) {
            if let Some(inner) = cap.get(1) {
                for part in inner.as_str().split("<br>") {
                    let p = part.trim();
                    if !p.is_empty() {
                        res.explains.push(p.to_string());
                    }
                }
            }
        }

        assert_eq!(res.explains, vec!["n. 你好", "int. 喂"]);
    }
}
