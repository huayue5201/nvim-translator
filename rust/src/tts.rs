use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

/// Speak text. `engine` is "say" (local) or "google" (online).
pub fn speak(text: &str, lang: &str, engine: &str) {
    match engine {
        "google" => speak_google(text, lang),
        _ => speak_local(text, lang),
    }
}

/// Pick a reasonable default macOS `say` voice for common languages.
fn voice_for(lang: &str) -> Option<&'static str> {
    if lang.starts_with("zh") {
        Some("Tingting")
    } else if lang.starts_with("en") {
        Some("Samantha")
    } else {
        None
    }
}

fn speak_local(text: &str, lang: &str) {
    if cfg!(target_os = "macos") {
        let mut cmd = Command::new("say");
        if let Some(voice) = voice_for(lang) {
            cmd.args(["-v", voice]);
        }
        let _ = cmd.arg(text).status();
        return;
    }

    if cfg!(target_os = "linux") {
        for prog in ["espeak-ng", "espeak", "spd-say"] {
            if Command::new(prog).arg(text).status().is_ok() {
                return;
            }
        }
        return;
    }

    if cfg!(target_os = "windows") {
        let script = format!(
            "Add-Type -AssemblyName System.Speech; \
             (New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak('{}')",
            text.replace('\'', "''")
        );
        let _ = Command::new("powershell")
            .args(["-NoProfile", "-Command", &script])
            .status();
    }
}

fn speak_google(text: &str, lang: &str) {
    let url = format!(
        "https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&q={}&tl={}",
        urlencoding::encode(text),
        lang
    );

    let client = reqwest::blocking::Client::new();
    let Ok(resp) = client.get(&url).send() else {
        eprintln!("google tts: download failed");
        return;
    };
    let Ok(bytes) = resp.bytes() else {
        eprintln!("google tts: read failed");
        return;
    };

    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let path = std::env::temp_dir().join(format!(
        "translator_tts_{}_{}.mp3",
        std::process::id(),
        nanos
    ));

    if std::fs::write(&path, bytes).is_err() {
        eprintln!("google tts: failed to write temp file");
        return;
    }

    play_audio(&path);
    let _ = std::fs::remove_file(&path);
}

fn play_audio(path: &std::path::Path) {
    if cfg!(target_os = "macos") {
        let _ = Command::new("afplay").arg(path).status();
        return;
    }

    if cfg!(target_os = "linux") {
        for prog in ["mpv", "ffplay", "aplay", "paplay"] {
            if Command::new(prog).arg(path).status().is_ok() {
                return;
            }
        }
        return;
    }

    if cfg!(target_os = "windows") {
        let script = format!(
            "(New-Object Media.SoundPlayer '{}').PlaySync()",
            path.display()
        );
        let _ = Command::new("powershell")
            .args(["-NoProfile", "-Command", &script])
            .status();
    }
}
