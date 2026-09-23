use std::process::Command;

use super::base;
use crate::Translation;

/// Shells out to the `sdcv` CLI (StarDict console version).
pub fn translate(text: &str) -> Translation {
    let mut res = base("sdcv", "", "", text);

    let Ok(out) = Command::new("sdcv")
        .args(["-u", "朗道英汉字典5.0", text])
        .output()
    else {
        return res;
    };

    if !out.status.success() {
        return res;
    }

    let stdout = String::from_utf8_lossy(&out.stdout);
    res.explains = stdout
        .lines()
        .map(|l| l.trim().to_string())
        .filter(|l| !l.is_empty() && !l.starts_with("-->") && !l.starts_with('*'))
        .collect();

    res
}
