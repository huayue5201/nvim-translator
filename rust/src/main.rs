use std::io::{Read, Write};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;

use clap::{Args, Parser, Subcommand};
use serde::Serialize;

mod engines;
mod tts;

/// Backend for nvim-translator.
#[derive(Parser)]
#[command(name = "translator", version, about)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Translate text using one or more engines; writes JSON to stdout.
    Translate(TranslateArgs),
    /// Speak text using a local or online TTS engine.
    Speak(SpeakArgs),
}

#[derive(Args)]
#[command(rename_all = "snake_case")]
struct TranslateArgs {
    /// Comma-separated engine names: google,youdao,baidu,bing,baicizhan,haici,iciba,llm,api,explain,trans,sdcv
    #[arg(long, value_delimiter = ',', default_value = "google")]
    engines: Vec<String>,

    /// Target language (e.g. zh, en)
    #[arg(long, default_value = "zh")]
    target_lang: String,

    /// Source language (e.g. auto, en)
    #[arg(long, default_value = "en")]
    source_lang: String,

    /// Optional proxy URL (http://, socks5://, ...)
    #[arg(long)]
    proxy: Option<String>,

    /// Stream one JSON result per engine (NDJSON) as each completes, instead
    /// of emitting a single combined JSON object at the end.
    #[arg(long)]
    stream: bool,

    /// Read the text from stdin instead of argv (avoids leaking it into `ps`
    /// and the ARG_MAX limit for long selections).
    #[arg(long)]
    stdin: bool,

    /// Batch mode: stdin holds one text per line; one JSON object per text is
    /// printed, carrying its 0-based line index as `id`.
    #[arg(long)]
    batch: bool,

    /// Number of concurrent texts in batch mode.
    #[arg(long, default_value_t = 8)]
    concurrency: usize,

    /// Text to translate. May contain spaces.
    #[arg(value_name = "TEXT", allow_hyphen_values = true)]
    text: Option<String>,
}

#[derive(Args)]
#[command(rename_all = "snake_case")]
struct SpeakArgs {
    /// Text to speak.
    #[arg(long, allow_hyphen_values = true)]
    text: String,

    /// Language of the text (e.g. en, zh).
    #[arg(long, default_value = "en")]
    lang: String,

    /// TTS engine: "local" (OpenAI-compatible HTTP service), "say" (OS built-in)
    /// or "google" (online, legacy).
    #[arg(long, default_value = "local")]
    engine: String,

    /// Voice id, e.g. `af_heart` (Kokoro). Defaults to a per-language voice.
    #[arg(long)]
    voice: Option<String>,

    /// Playback speed multiplier.
    #[arg(long, default_value_t = 1.0)]
    speed: f32,

    /// Base URL of the local TTS service.
    #[arg(long, default_value = "http://127.0.0.1:8880")]
    tts_url: String,

    /// Model id sent to the local TTS service.
    #[arg(long, default_value = "mlx-community/Kokoro-82M-4bit")]
    tts_model: String,

    /// Fall back to the OS voice when the local service is unreachable.
    #[arg(long, default_value_t = true, action = clap::ArgAction::Set)]
    fallback: bool,
}

#[derive(Serialize, Clone, Default)]
pub struct Translation {
    pub engine: String,
    pub sl: String,
    pub tl: String,
    pub text: String,
    pub phonetic: String,
    pub paraphrase: String,
    pub explains: Vec<String>,
    /// Failure reason for this engine; omitted when the engine succeeded.
    /// Lets the frontend show *why* an engine came back empty instead of a
    /// generic "Translation failed".
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Serialize)]
struct Output {
    text: String,
    status: u8,
    results: Vec<Translation>,
}

#[derive(Serialize)]
struct BatchOutput {
    id: usize,
    text: String,
    results: Vec<Translation>,
}

fn read_stdin() -> String {
    let mut buf = String::new();
    if std::io::stdin().read_to_string(&mut buf).is_err() {
        return String::new();
    }
    buf
}

fn build_client(proxy: Option<&str>) -> reqwest::blocking::Client {
    let mut builder = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(5))
        .user_agent("Mozilla/5.0");

    if let Some(p) = proxy {
        match reqwest::Proxy::all(p) {
            Ok(px) => {
                builder = builder.proxy(px);
            }
            Err(e) => eprintln!("invalid proxy '{}': {}", p, e),
        }
    }

    match builder.build() {
        Ok(client) => client,
        Err(e) => {
            eprintln!("client build error: {}", e);
            reqwest::blocking::Client::new()
        }
    }
}

/// Run every configured engine in parallel and collect the results.
fn translate_all(
    client: &Arc<reqwest::blocking::Client>,
    args: &TranslateArgs,
    text: &str,
) -> Vec<Translation> {
    let handles: Vec<_> = args
        .engines
        .iter()
        .map(|engine| {
            let engine = engine.clone();
            let client = Arc::clone(client);
            let sl = args.source_lang.clone();
            let tl = args.target_lang.clone();
            let text = text.to_string();
            thread::spawn(move || engines::translate(&client, &engine, &sl, &tl, &text))
        })
        .collect();

    handles
        .into_iter()
        .map(|handle| handle.join().unwrap_or_default())
        .collect()
}

fn run_translate(args: TranslateArgs) {
    let client = Arc::new(build_client(args.proxy.as_deref()));

    if args.batch {
        return run_batch(&args, client);
    }

    let text = match args
        .text
        .clone()
        .or_else(|| args.stdin.then(read_stdin))
        .map(|t| t.trim().to_string())
    {
        Some(t) if !t.is_empty() => t,
        _ => {
            eprintln!("no text to translate (pass TEXT, --stdin or --batch)");
            std::process::exit(2);
        }
    };

    if args.stream {
        return run_translate_stream(&args, client, text);
    }

    let results = translate_all(&client, &args, &text);
    let output = Output {
        text,
        status: 1,
        results,
    };

    println!("{}", serde_json::to_string(&output).unwrap());
}

/// Streaming mode: print one Translation JSON per line as each engine finishes,
/// then a final `{"done":true}` sentinel. Order of lines is completion order.
fn run_translate_stream(args: &TranslateArgs, client: Arc<reqwest::blocking::Client>, text: String) {
    let (tx, rx) = std::sync::mpsc::channel::<Translation>();

    let mut spawned = 0usize;
    for engine in &args.engines {
        let engine = engine.clone();
        let client = Arc::clone(&client);
        let sl = args.source_lang.clone();
        let tl = args.target_lang.clone();
        let text = text.clone();
        let tx = tx.clone();
        thread::spawn(move || {
            let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                engines::translate(&client, &engine, &sl, &tl, &text)
            }))
            .unwrap_or_else(|_| engines::base(&engine, &sl, &tl, &text));
            let _ = tx.send(result);
        });
        spawned += 1;
    }
    drop(tx);

    let stdout = std::io::stdout();
    let mut lock = stdout.lock();
    for _ in 0..spawned {
        match rx.recv() {
            Ok(t) => {
                if let Ok(line) = serde_json::to_string(&t) {
                    let _ = writeln!(lock, "{}", line);
                    let _ = lock.flush();
                }
            }
            Err(_) => break,
        }
    }
    let _ = writeln!(lock, "{{\"done\":true}}");
    let _ = lock.flush();
}

/// Batch mode: one text per stdin line, one JSON object per text on stdout.
/// `id` is the 0-based line index, so the caller can map results back even
/// though they arrive out of order.
fn run_batch(args: &TranslateArgs, client: Arc<reqwest::blocking::Client>) {
    let input = read_stdin();
    let texts: Vec<String> = input
        .split('\n')
        .map(|line| line.trim_end_matches('\r').trim().to_string())
        .collect();
    let total = texts.len();
    if total == 0 {
        return;
    }

    let next = AtomicUsize::new(0);
    let stdout = Mutex::new(std::io::stdout());
    let workers = args.concurrency.clamp(1, total);

    std::thread::scope(|scope| {
        for _ in 0..workers {
            scope.spawn(|| loop {
                let i = next.fetch_add(1, Ordering::SeqCst);
                if i >= total {
                    break;
                }
                if texts[i].is_empty() {
                    continue;
                }
                let out = BatchOutput {
                    id: i,
                    text: texts[i].clone(),
                    results: translate_all(&client, args, &texts[i]),
                };
                if let Ok(line) = serde_json::to_string(&out) {
                    let mut lock = stdout.lock().unwrap();
                    let _ = writeln!(lock, "{}", line);
                    let _ = lock.flush();
                }
            });
        }
    });
}

fn main() {
    let cli = Cli::parse();
    match cli.command {
        Command::Translate(args) => run_translate(args),
        Command::Speak(args) => {
            let opts = tts::Options {
                engine: args.engine,
                voice: args.voice,
                speed: args.speed,
                url: args.tts_url,
                model: args.tts_model,
                fallback: args.fallback,
            };
            tts::speak(&args.text, &args.lang, &opts);
        }
    }
}
