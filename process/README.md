# ASR, Translation, and Subtitle Processing

This pipeline runs Whisper transcription, optional offline NLLB translation,
and optional FFmpeg subtitle burn-in.

## Usage

```bash
# Transcription only
nu process/asr_mt.nu /path/to/video.mp4 --vad

# Transcribe, translate English to Simplified Chinese, and burn subtitles
nu process/asr_mt.nu /path/to/video.mp4 \
  --vad --translate --src-lang eng_Latn --tgt-lang zho_Hans --burn
```

Useful options include the Whisper model, compute precision, spoken language,
beam size, VAD, NLLB source and target languages, subtitle burn-in, and FFmpeg
encoder. Use `nu process/asr_mt.nu --help` for the complete interface.

## Behavior

The three stages are:

1. Run faster-whisper in the configured ASR container.
2. Optionally run offline NLLB translation in the configured model container.
3. Optionally burn the selected subtitles into a derived video with FFmpeg.

The Python helpers are container-side programs. Their heavyweight model, CUDA,
and Python dependencies are not a host environment for this repository.

Generated SRT and video files are written next to the input media under derived
names. Source media and generated outputs are user content. FFmpeg uses
overwrite mode for the derived output name.

## Safety and Validation

This pipeline is real-only and may load GPU models, create subtitles, and
replace the derived burn-in output. Do not run Singularity, CUDA models,
translation, or FFmpeg merely to validate an edit.

Use `nu --ide-check 100 process/asr_mt.nu`. Compile Python source in memory
with the root README command so no `__pycache__` is created. Review container
arguments, bind paths, output names, language flow, UTF-8 handling, and external
exit propagation statically.
