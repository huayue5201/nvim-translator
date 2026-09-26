use crate::Translation;

pub mod api;
pub mod baicizhan;
pub mod baidu;
pub mod bing;
pub mod google;
pub mod haici;
pub mod iciba;
pub mod llm;
pub mod sdcv;
pub mod trans;
pub mod youdao;

/// Create an empty result prefilled with metadata.
pub fn base(engine: &str, sl: &str, tl: &str, text: &str) -> Translation {
    Translation {
        engine: engine.to_string(),
        sl: sl.to_string(),
        tl: tl.to_string(),
        text: text.to_string(),
        ..Default::default()
    }
}

/// Dispatch to one of the supported engines. Never panics; returns an empty
/// result on unsupported engine or request failure.
pub fn translate(
    client: &reqwest::blocking::Client,
    engine: &str,
    sl: &str,
    tl: &str,
    text: &str,
) -> Translation {
    match engine {
        "api" => api::translate(client, sl, tl, text),
        "google" => google::translate(client, sl, tl, text),
        "youdao" => youdao::translate(client, sl, tl, text),
        "baidu" => baidu::translate(client, text),
        "bing" => bing::translate(client, sl, tl, text),
        "baicizhan" => baicizhan::translate(client, text),
        "haici" => haici::translate(client, text),
        "iciba" => iciba::translate(client, text),
        "llm" => llm::translate(client, sl, tl, text),
        "trans" => trans::translate(tl, text),
        "sdcv" => sdcv::translate(text),
        _ => base(engine, sl, tl, text),
    }
}
