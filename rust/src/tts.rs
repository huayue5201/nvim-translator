use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// Runtime options for the `speak` subcommand.
pub struct Options {
    /// "local" (OpenAI-compatible HTTP TTS), "say" (OS built-in) or "google".
    pub engine: String,
    /// Voice id, e.g. `af_heart`. Empty = pick from `lang`.
    pub voice: Option<String>,
    /// Playback speed multiplier (0.5 - 2.0).
    pub speed: f32,
    /// Base URL of the local TTS service.
    pub url: String,
    /// Model id sent to the local service.
    pub model: String,
    /// Fall back to the OS voice when the local service is unreachable.
    pub fallback: bool,
}

/// Speak `text`. Long text is split into sentences so playback can start
/// after the first chunk instead of waiting for the whole utterance.
pub fn speak(text: &str, lang: &str, opts: &Options) {
    stop_previous();

    match opts.engine.as_str() {
        "say" => speak_local(text, lang),
        "google" => speak_google(text, lang),
        "local" => match speak_http(text, lang, opts) {
            Ok(()) => {}
            Err(err) => {
                if opts.fallback {
                    eprintln!("tts: local engine failed ({err}); falling back to `say`");
                    speak_local(text, lang);
                } else {
                    eprintln!("tts: {err}");
                }
            }
        },
        other => {
            eprintln!("tts: unknown engine `{other}`");
            speak_local(text, lang);
        }
    }
}

/// Pick a reasonable default voice for common languages.
fn default_voice(lang: &str) -> &'static str {
    if lang.starts_with("zh") {
        "zf_xiaobei"
    } else if lang.starts_with("en") {
        "af_heart"
    } else {
        "af_heart"
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

// ---------------------------------------------------------------------------
// Local HTTP engine (OpenAI-compatible /v1/audio/speech)
// ---------------------------------------------------------------------------

fn speak_http(text: &str, lang: &str, opts: &Options) -> Result<(), String> {
    let chunks = split_batches(text, BATCH_CHARS);
    if chunks.is_empty() {
        return Ok(());
    }

    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(120))
        .build()
        .map_err(|e| format!("client: {e}"))?;

    let voice = opts
        .voice
        .as_deref()
        .filter(|v| !v.is_empty())
        .unwrap_or_else(|| default_voice(lang))
        .to_string();
    let endpoint = format!(
        "{}/v1/audio/speech",
        opts.url.trim().trim_end_matches('/')
    );
    let model = opts.model.clone();
    let speed = opts.speed;

    // Prefetch the next batch while the current one is playing.
    let (tx, rx) = mpsc::sync_channel::<Result<Vec<u8>, String>>(1);
    let producer = std::thread::spawn(move || {
        for chunk in chunks {
            let body = serde_json::json!({
                "model": model,
                "input": chunk,
                "voice": voice,
                "speed": speed,
                "response_format": "wav",
            });
            let result = client
                .post(&endpoint)
                .json(&body)
                .send()
                .map_err(|e| format!("request failed: {e}"))
                .and_then(|resp| {
                    let status = resp.status();
                    if !status.is_success() {
                        return Err(format!("http {status}"));
                    }
                    resp.bytes()
                        .map(|b| b.to_vec())
                        .map_err(|e| format!("read failed: {e}"))
                });
            if tx.send(result).is_err() {
                break;
            }
        }
    });

    let mut played = 0usize;
    let mut error: Option<String> = None;
    for result in rx {
        match result {
            Ok(bytes) if bytes.len() > 44 => {
                play_bytes(&bytes)?;
                played += 1;
            }
            Ok(_) => {}
            Err(err) => {
                // Report the failure; if nothing has played yet the caller can
                // still fall back to the OS voice.
                error = Some(err);
                break;
            }
        }
    }
    let _ = producer.join();

    match error {
        Some(err) if played == 0 => Err(err),
        Some(err) => {
            eprintln!("tts: {err}");
            Ok(())
        }
        None => Ok(()),
    }
}

/// How many characters are generated before playback starts. Larger batches
/// mean fewer gaps between `afplay` invocations, smaller ones mean a shorter
/// wait for the first sound.
const BATCH_CHARS: usize = 400;

/// Group sentences into batches of at most `max` characters.
fn split_batches(text: &str, max: usize) -> Vec<String> {
    let mut batches: Vec<String> = Vec::new();
    let mut cur = String::new();
    for sentence in split_sentences(text) {
        if sentence.chars().count() > max {
            if !cur.trim().is_empty() {
                batches.push(cur.trim().to_string());
                cur.clear();
            }
            // Hard-wrap an over-long sentence at whitespace.
            let mut rest = sentence.as_str();
            while rest.chars().count() > max {
                let cut = rest
                    .char_indices()
                    .take_while(|(pos, _)| *pos < max)
                    .filter(|(_, ch)| *ch == ' ' || *ch == ',' || *ch == '，')
                    .map(|(pos, ch)| pos + ch.len_utf8())
                    .last()
                    .unwrap_or(max);
                batches.push(rest[..cut].trim().to_string());
                rest = rest[cut..].trim_start();
            }
            if !rest.is_empty() {
                cur.push_str(rest);
            }
            continue;
        }
        if !cur.is_empty() && cur.chars().count() + sentence.chars().count() + 1 > max {
            batches.push(cur.trim().to_string());
            cur.clear();
        }
        if !cur.is_empty() {
            cur.push(' ');
        }
        cur.push_str(&sentence);
    }
    if !cur.trim().is_empty() {
        batches.push(cur.trim().to_string());
    }
    batches
}

/// Split text into sentence-sized chunks.
fn split_sentences(text: &str) -> Vec<String> {
    const HARD: &[char] = &['.', '!', '?', '。', '！', '？', '…', ';', '；', '\n'];
    const SOFT: &[char] = &[',', '，', '、', ':', '：', '—', '-'];
    const MIN: usize = 4;
    const MAX: usize = 220;

    let chars: Vec<char> = text.chars().collect();
    let mut chunks: Vec<String> = Vec::new();
    let mut cur = String::new();

    for (i, &c) in chars.iter().enumerate() {
        cur.push(c);
        let next = chars.get(i + 1).copied();
        // CJK punctuation is not followed by a space, so it always ends a sentence.
        let cjk = matches!(c, '。' | '！' | '？' | '；' | '…');
        let boundary = if cjk {
            true
        } else {
            HARD.contains(&c)
                && match next {
                    None => true,
                    Some(n) => {
                        n.is_whitespace()
                            || n == '"'
                            || n == '\''
                            || n == '”'
                            || n == '’'
                            || n == ')'
                            || n == '）'
                            || n == '】'
                    }
                }
        };
        let len = cur.trim().chars().count();

        if boundary && len >= MIN {
            chunks.push(cur.trim().to_string());
            cur.clear();
        } else if len >= MAX {
            // Break at the last soft delimiter, else at a space.
            let cut = cur
                .char_indices()
                .rev()
                .find(|(pos, ch)| SOFT.contains(ch) && *pos > MAX / 3)
                .map(|(pos, ch)| pos + ch.len_utf8())
                .or_else(|| cur.rfind(' ').filter(|p| *p > MAX / 3));
            match cut {
                Some(pos) => {
                    chunks.push(cur[..pos].trim().to_string());
                    cur = cur[pos..].trim_start().to_string();
                }
                None => {
                    let rest = cur.split_off(MAX);
                    chunks.push(cur.trim().to_string());
                    cur = rest;
                }
            }
        }
    }

    if cur.trim().chars().count() >= 2 {
        chunks.push(cur.trim().to_string());
    }

    // Merge fragments that are too short to stand on their own; a fragment that
    // already ends a sentence is kept as is.
    let mut merged: Vec<String> = Vec::new();
    for chunk in chunks {
        let finished = chunk
            .chars()
            .last()
            .map(|c| HARD.contains(&c) || c == '"' || c == '”')
            .unwrap_or(false);
        if let Some(last) = merged.last_mut() {
            if !finished
                && chunk.chars().count() < 12
                && last.chars().count() + chunk.chars().count() <= MAX
            {
                last.push(' ');
                last.push_str(&chunk);
                continue;
            }
        }
        merged.push(chunk);
    }
    merged
}

fn play_bytes(bytes: &[u8]) -> Result<(), String> {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let path = std::env::temp_dir().join(format!(
        "translator_tts_{}_{}.wav",
        std::process::id(),
        nanos
    ));
    std::fs::write(&path, bytes).map_err(|e| format!("write temp file: {e}"))?;
    let result = play_audio(&path);
    let _ = std::fs::remove_file(&path);
    result
}

fn play_audio(path: &std::path::Path) -> Result<(), String> {
    if cfg!(target_os = "macos") {
        return run_player("afplay", &[path.as_os_str()]);
    }

    if cfg!(target_os = "linux") {
        for prog in ["mpv", "ffplay", "paplay", "aplay"] {
            if run_player(prog, &[path.as_os_str()]).is_ok() {
                return Ok(());
            }
        }
        return Err("no audio player found (mpv/ffplay/paplay/aplay)".into());
    }

    if cfg!(target_os = "windows") {
        let script = format!(
            "(New-Object Media.SoundPlayer '{}').PlaySync()",
            path.display()
        );
        let _ = Command::new("powershell")
            .args(["-NoProfile", "-Command", &script])
            .status();
        return Ok(());
    }

    Err("unsupported platform".into())
}

/// Spawn an audio player, record its pid (so a later speak can stop it) and wait.
fn run_player(prog: &str, args: &[&std::ffi::OsStr]) -> Result<(), String> {
    let mut child = Command::new(prog)
        .args(args)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("spawn {prog}: {e}"))?;
    let _ = std::fs::write(player_pid_file(), child.id().to_string());
    child
        .wait()
        .map_err(|e| format!("wait {prog}: {e}"))?;
    let _ = std::fs::remove_file(player_pid_file());
    Ok(())
}

fn player_pid_file() -> std::path::PathBuf {
    std::env::temp_dir().join("nvim-translator-tts.pid")
}

/// Stop audio started by a previous `speak` invocation.
fn stop_previous() {
    let path = player_pid_file();
    let Ok(meta) = std::fs::metadata(&path) else {
        return;
    };
    // Ignore stale pid files so a recycled pid can never kill an unrelated process.
    let fresh = meta
        .modified()
        .ok()
        .and_then(|t| SystemTime::now().duration_since(t).ok())
        .map(|age| age < Duration::from_secs(300))
        .unwrap_or(false);
    if fresh {
        if let Ok(raw) = std::fs::read_to_string(&path) {
            if let Ok(pid) = raw.trim().parse::<u32>() {
                let _ = Command::new("kill").arg(pid.to_string()).status();
            }
        }
    }
    let _ = std::fs::remove_file(&path);
}

// ---------------------------------------------------------------------------
// OS built-in engine
// ---------------------------------------------------------------------------

fn speak_local(text: &str, lang: &str) {
    if cfg!(target_os = "macos") {
        let mut cmd = Command::new("say");
        if let Some(voice) = voice_for(lang) {
            cmd.args(["-v", voice]);
        }
        if let Ok(mut child) = cmd
            .arg(text)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
        {
            let _ = std::fs::write(player_pid_file(), child.id().to_string());
            let _ = child.wait();
            let _ = std::fs::remove_file(player_pid_file());
        }
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

// ---------------------------------------------------------------------------
// Google Translate engine (online, legacy)
// ---------------------------------------------------------------------------

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

    if let Err(err) = play_bytes(&bytes) {
        eprintln!("google tts: {err}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_on_sentence_end() {
        let chunks = split_sentences("One sentence here. Another sentence there!");
        assert_eq!(chunks, vec!["One sentence here.", "Another sentence there!"]);
    }

    #[test]
    fn keeps_abbreviations_together() {
        let chunks = split_sentences("Mr. Smith went to Washington to meet the team.");
        assert_eq!(chunks.len(), 1);
    }

    #[test]
    fn does_not_split_decimals() {
        let chunks = split_sentences("Pi is 3.14 approximately and that is fine.");
        assert_eq!(chunks.len(), 1);
    }

    #[test]
    fn batches_respect_the_limit() {
        let text = "A fairly long sentence that should be grouped sensibly. ".repeat(12);
        let batches = split_batches(&text, 400);
        assert!(batches.len() > 1);
        for batch in &batches {
            assert!(batch.chars().count() <= 400, "batch too long: {}", batch.len());
        }
        assert_eq!(batches.concat().replace(' ', "").len(), text.replace(' ', "").len());
    }

    #[test]
    fn hard_wraps_a_single_huge_sentence() {
        let text = "word ".repeat(500);
        let batches = split_batches(&text, 400);
        assert!(batches.len() >= 2);
        for batch in &batches {
            assert!(batch.chars().count() <= 400);
        }
    }

    #[test]
    fn handles_cjk_punctuation() {
        let chunks = split_sentences("这是第一句。这是第二句！");
        assert_eq!(chunks.len(), 2);
    }

    #[test]
    fn picks_default_voices() {
        assert_eq!(default_voice("en"), "af_heart");
        assert_eq!(default_voice("zh"), "zf_xiaobei");
    }
}
