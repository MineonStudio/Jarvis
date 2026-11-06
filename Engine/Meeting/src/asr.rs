//! Paraformer-large int8, Silero VAD, CT-Transformer and CAM++ via sherpa-onnx.
//! Adapted from Tingo e5a5bba, MIT; no alternative recognizers are exposed.
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use sherpa_onnx::{OfflinePunctuation, OfflinePunctuationConfig, OfflinePunctuationModelConfig,
    OfflineRecognizer, OfflineRecognizerConfig, SpeakerEmbeddingExtractor,
    SpeakerEmbeddingExtractorConfig, VadModelConfig, VoiceActivityDetector};

pub const SR: usize = 16000;
pub struct ModelPaths { pub dir: PathBuf }
impl ModelPaths {
    pub fn new(dir: impl Into<PathBuf>) -> Self { Self { dir: dir.into() } }
    pub fn paraformer(&self) -> PathBuf { self.dir.join("paraformer/model.int8.onnx") }
    pub fn tokens(&self) -> PathBuf { self.dir.join("paraformer/tokens.txt") }
    pub fn vad(&self) -> PathBuf { self.dir.join("silero_vad.onnx") }
    pub fn punct(&self) -> PathBuf { self.dir.join("punct/model.int8.onnx") }
    pub fn speaker(&self) -> PathBuf { self.dir.join("campplus_zh.onnx") }
    pub fn base(&self) -> [PathBuf; 3] { [self.vad(), self.punct(), self.speaker()] }
    pub fn ready(&self) -> bool { self.base().iter().chain([self.paraformer(),self.tokens()].iter()).all(|p|p.is_file()) }
}
#[derive(Clone, Debug)]
pub struct Segment { pub start_ms: u64, pub end_ms: u64, pub text: String, pub embeddings: Vec<Vec<f32>> }
pub struct Engine {
    rec: OfflineRecognizer,
    punct: OfflinePunctuation,
    spk: SpeakerEmbeddingExtractor,
    vad: VadModelConfig,
    lock: Mutex<()>,
}
// All native handles are used exclusively under the engine lock.
unsafe impl Sync for Engine {}
unsafe impl Send for Engine {}
fn path(p: &Path) -> Option<String> { Some(p.to_string_lossy().into_owned()) }
impl Engine {
    pub fn load(models: &ModelPaths, threads: i32) -> Result<Self, String> {
        if !models.ready() { return Err("识别资源不完整，请先在设置中下载 Paraformer-large".into()); }
        let mut cfg = OfflineRecognizerConfig::default();
        cfg.model_config.num_threads = threads;
        cfg.model_config.paraformer.model = path(&models.paraformer());
        cfg.model_config.tokens = path(&models.tokens());
        let rec = OfflineRecognizer::create(&cfg).ok_or("Paraformer-large 加载失败")?;
        let punct = OfflinePunctuation::create(&OfflinePunctuationConfig {
            model: OfflinePunctuationModelConfig {
                ct_transformer: path(&models.punct()), num_threads: 2,
                ..Default::default()
            }, ..Default::default()
        }).ok_or("标点模型加载失败")?;
        let spk = SpeakerEmbeddingExtractor::create(&SpeakerEmbeddingExtractorConfig {
            model: path(&models.speaker()), num_threads: 2, ..Default::default()
        }).ok_or("CAM++ 声纹模型加载失败")?;
        let mut vad = VadModelConfig::default();
        vad.silero_vad.model = path(&models.vad());
        vad.silero_vad.threshold = 0.5;
        vad.silero_vad.window_size = 512;
        vad.silero_vad.min_silence_duration = 0.3;
        vad.silero_vad.min_speech_duration = 0.25;
        vad.silero_vad.max_speech_duration = 10.0;
        vad.sample_rate = SR as i32;
        vad.num_threads = 1;
        Ok(Self { rec, punct, spk, vad, lock: Mutex::new(()) })
    }
    pub fn transcribe(&self, samples: &[f32], offset_ms: u64) -> Result<Vec<Segment>, String> {
        let _guard = self.lock.lock().unwrap();
        let vad = VoiceActivityDetector::create(&self.vad, 120.0).ok_or("语音检测模型加载失败")?;
        for chunk in samples.chunks(512) { vad.accept_waveform(chunk); }
        vad.flush();
        let mut out = Vec::new();
        while let Some(seg) = vad.front() {
            let audio = seg.samples();
            let start = offset_ms + seg.start() as u64 * 1000 / SR as u64;
            let end = start + audio.len() as u64 * 1000 / SR as u64;
            let stream = self.rec.create_stream();
            stream.accept_waveform(SR as i32, audio);
            self.rec.decode(&stream);
            let text = stream.get_result().map(|r|r.text).unwrap_or_default();
            let text = text.trim();
            if !text.is_empty() {
                let text = self.punct.add_punctuation(text).unwrap_or_else(||text.to_string());
                let embeddings = windows(audio.len()).filter_map(|(a,b)|self.embed(&audio[a..b])).collect();
                out.push(Segment { start_ms:start, end_ms:end, text, embeddings });
            }
            vad.pop();
        }
        Ok(out)
    }
    fn embed(&self, audio: &[f32]) -> Option<Vec<f32>> {
        let stream = self.spk.create_stream()?;
        stream.accept_waveform(SR as i32, audio); stream.input_finished();
        if !self.spk.is_ready(&stream) { return None; }
        self.spk.compute(&stream).filter(|e|!e.is_empty())
    }
}
pub fn windows(len: usize) -> impl Iterator<Item = (usize, usize)> {
    let win = SR * 3 / 2;
    let shift = SR * 3 / 4;
    let mut st = 0;
    let mut done = false;
    std::iter::from_fn(move || {
        if done || len == 0 { return None; }
        let end = (st + win).min(len);
        let start = end.saturating_sub(win);
        done = end == len; st += shift;
        Some((start,end))
    })
}
