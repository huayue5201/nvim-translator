use std::sync::Arc;
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
    /// Comma-separated engine names: google,youdao,baidu,bing,baicizhan,haici,iciba,llm,trans,sdcv
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

    /// Text to translate. Passed as a single argv element, may contain spaces.
    #[arg(value_name = "TEXT", allow_hyphen_values = true)]
    text: String,
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

    /// TTS engine: "say" (local) or "google" (online).
    #[arg(long, default_value = "say")]
    engine: String,
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
    pub alternative: Vec<String>,
}

#[derive(Serialize)]
struct Output {
    text: String,
    status: u8,
    results: Vec<Translation>,
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

fn run_translate(args: TranslateArgs) {
    let client = Arc::new(build_client(args.proxy.as_deref()));
    let text = args.text.trim().to_string();

    let handles: Vec<_> = args
        .engines
        .iter()
        .map(|engine| {
            let engine = engine.clone();
            let client = Arc::clone(&client);
            let sl = args.source_lang.clone();
            let tl = args.target_lang.clone();
            let text = text.clone();
            thread::spawn(move || engines::translate(&client, &engine, &sl, &tl, &text))
        })
        .collect();

    let mut results: Vec<Translation> = Vec::with_capacity(handles.len());
    for handle in handles {
        match handle.join() {
            Ok(t) => results.push(t),
            Err(_) => results.push(Translation::default()),
        }
    }

    let output = Output {
        text,
        status: 1,
        results,
    };

    println!("{}", serde_json::to_string(&output).unwrap());
}

fn main() {
    let cli = Cli::parse();
    match cli.command {
        Command::Translate(args) => run_translate(args),
        Command::Speak(args) => tts::speak(&args.text, &args.lang, &args.engine),
    }
}
