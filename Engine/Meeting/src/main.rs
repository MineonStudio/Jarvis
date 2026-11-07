//! Jarvis transport adapter for the Tingo processing pipeline (MIT).
mod asr;
// Retain upstream audio helpers covered by compatibility tests.
#[allow(dead_code)]
mod audio;
mod chunked;
mod cluster;
// Upstream localization helpers are retained for transcript compatibility tests.
#[allow(dead_code)]
mod i18n;
mod models;
// The app consumes JSON; upstream formatting helpers remain regression-tested.
#[allow(dead_code)]
mod transcript;

use std::io::{BufRead, Write};
use std::path::Path;
use std::sync::{mpsc, Arc};
use std::time::Duration;
use serde_json::json;
use asr::{Engine, ModelPaths, SR};

fn emit(value: serde_json::Value) {
    let stdout = std::io::stdout();
    let mut out = stdout.lock();
    let _ = writeln!(out, "{value}");
    let _ = out.flush();
}

fn engine(models: &str) -> Result<Engine, String> {
    Engine::load(&ModelPaths::new(models), 4)
}

fn mixed(system: &Path, mic: &Path) -> Result<Vec<f32>, String> {
    let read = |p: &Path| audio::read_wav16k(p).unwrap_or_default();
    let sys = read(system);
    let local = read(mic);
    if sys.is_empty() && local.is_empty() { return Err("没有可用的录音，请检查输入设备和录音权限".into()); }
    Ok(if sys.is_empty() { local } else if local.is_empty() { sys } else { audio::duck_mix_default(&sys, &local) })
}

fn write_wav(path: &Path, samples: &[f32]) -> Result<(), String> {
    use std::fs::File;
    let mut f = File::create(path).map_err(|e| e.to_string())?;
    let size = u32::try_from(samples.len().saturating_mul(2)).map_err(|_| "录音超出 WAV 大小限制")?;
    let mut h = Vec::new();
    h.extend(b"RIFF"); h.extend((36u32 + size).to_le_bytes()); h.extend(b"WAVEfmt ");
    h.extend(16u32.to_le_bytes()); h.extend(1u16.to_le_bytes()); h.extend(1u16.to_le_bytes());
    h.extend((SR as u32).to_le_bytes()); h.extend((SR as u32 * 2).to_le_bytes());
    h.extend(2u16.to_le_bytes()); h.extend(16u16.to_le_bytes()); h.extend(b"data"); h.extend(size.to_le_bytes());
    f.write_all(&h).map_err(|e| e.to_string())?;
    let mut buf = Vec::with_capacity(65536);
    for chunk in samples.chunks(32768) {
        buf.clear();
        for &s in chunk { buf.extend(((s.clamp(-1.0, 1.0) * 32767.0) as i16).to_le_bytes()); }
        f.write_all(&buf).map_err(|e| e.to_string())?;
    }
    f.sync_all().map_err(|e| e.to_string())
}

fn run(a: &[String]) -> Result<(), String> {
    match a.get(1).map(String::as_str) {
        Some("prepare") if a.len() == 3 => {
            let mut last = std::time::Instant::now() - Duration::from_secs(1);
            models::ensure(&ModelPaths::new(&a[2]), |done, total| {
                if done == total || last.elapsed() >= Duration::from_millis(100) {
                    emit(json!({"type":"download", "completed":done, "total":total}));
                    last = std::time::Instant::now();
                }
            })?;
            // Verify native model loading before calling the installation ready.
            let _ = engine(&a[2])?;
            let marker = Path::new(&a[2]).join("verified.json");
            let temp = marker.with_extension("tmp");
            std::fs::write(&temp, b"{\"pipeline\":1,\"model\":\"Paraformer-large\"}").map_err(|e|e.to_string())?;
            std::fs::rename(temp, marker).map_err(|e|e.to_string())?;
            emit(json!({"type":"ready"}));
        }
        Some("transcribe") if a.len() == 4 => {
            let e = engine(&a[2])?;
            let wav = Path::new(&a[3]);
            let samples = audio::read_wav16k(wav).ok_or("无法读取 16 kHz 音频")?;
            let tr = chunked::transcribe_samples(&e, &samples, wav, |p| {
                emit(json!({"type":"progress", "progress":p}));
            })?;
            emit(json!({"type":"result", "transcript":tr}));
        }
        Some("mix") if a.len() == 5 => {
            let samples = mixed(Path::new(&a[2]), Path::new(&a[3]))?;
            write_wav(Path::new(&a[4]), &samples)?;
            emit(json!({"type":"ready"}));
        }
        Some("live") if a.len() >= 5 => {
            let e = Arc::new(engine(&a[2])?);
            let dir = Path::new(&a[3]);
            let sources = a[5..].to_vec();
            if sources.is_empty() { return Err("没有选择音频输入".into()); }
            let live = chunked::LiveTranscriber::start(e.clone(), dir, &sources);
            emit(json!({"type":"ready"}));
            let (tx, rx) = mpsc::channel();
            std::thread::spawn(move || {
                // EOF means the parent exited: stop the worker rather than leave an orphan.
                let command = std::io::stdin().lock().lines().next().and_then(Result::ok).unwrap_or_default();
                let _ = tx.send(command);
            });
            let mut count = 0;
            let command = loop {
                match rx.recv_timeout(Duration::from_millis(500)) {
                    Ok(command) => break command,
                    Err(mpsc::RecvTimeoutError::Disconnected) => break String::new(),
                    Err(mpsc::RecvTimeoutError::Timeout) => {}
                }
                let n = live.line_count();
                if n != count {
                    count = n;
                    emit(json!({"type":"partial", "lines":live.recent(200).into_iter().map(|(ms,text)| json!({"start_ms":ms,"text":text})).collect::<Vec<_>>() }));
                }
            };
            emit(json!({"type":"progress", "progress":0.9}));
            let (mut tr, _) = live.finish(&e, Path::new(&a[4]))?;
            let mut samples = mixed(&dir.join("system.wav"), &dir.join("mic.wav"))?;
            if let Some(keep) = command.split_whitespace().nth(1).and_then(|s|s.parse::<f64>().ok()).filter(|t|t.is_finite() && *t >= 0.0) {
                samples.truncate((keep * SR as f64) as usize);
                tr.duration_ms = tr.duration_ms.min((keep * 1000.0) as u64);
                tr.sentences.retain(|s|s.start_ms < tr.duration_ms);
                for s in &mut tr.sentences { s.end_ms = s.end_ms.min(tr.duration_ms); }
            }
            write_wav(Path::new(&a[4]), &samples)?;
            emit(json!({"type":"result", "transcript":tr}));
        }
        _ => return Err("用法：jarvis-meeting-engine prepare|transcribe|mix|live".into())
    }
    Ok(())
}

fn main() {
    if let Err(message) = run(&std::env::args().collect::<Vec<_>>()) {
        emit(json!({"type":"error", "message":message}));
        std::process::exit(1);
    }
}

#[cfg(test)]
mod integration_tests {
    use super::*;
    #[test]
    fn mix_preserves_late_local_speech() {
        let n = SR * 3;
        let system = vec![0.0; n];
        let mut mic = vec![0.0; n];
        for x in mic.iter_mut().skip(SR * 2) { *x = 0.2; }
        let out = audio::duck_mix_default(&system, &mic);
        assert_eq!(out.len(), n);
        assert!(out[SR * 2 + 1000] > 0.19);
    }
    #[test]
    fn written_wav_round_trips() {
        let path = std::env::temp_dir().join(format!("jarvis-engine-{}.wav", std::process::id()));
        write_wav(&path, &[0.0, 0.5, -0.5]).unwrap();
        let samples = audio::read_wav16k(&path).unwrap();
        std::fs::remove_file(path).unwrap();
        assert_eq!(samples.len(), 3);
        assert!((samples[1] - 0.5).abs() < 0.001);
    }
}
