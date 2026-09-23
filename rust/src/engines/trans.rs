use std::process::Command;

use super::base;
use crate::Translation;

/// Shells out to the `trans` CLI (translate-shell).
pub fn translate(tl: &str, text: &str) -> Translation {
    let mut res = base("trans", "", tl, text);

    let Ok(out) = Command::new("trans")
        .args([
            "-no-ansi",
            "-no-theme",
            "-show-languages",
            "n",
            "-show-prompt-message",
            "n",
            "-show-translation-phonetics",
            "n",
            "-hl",
            tl,
            text,
        ])
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
        .filter(|l| !l.is_empty())
        .collect();

    res
}
