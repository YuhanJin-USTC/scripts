#!/usr/bin/env nu

# Video subtitle pipeline: Whisper ASR, optional NLLB translation, optional burn-in.
def status-label [status: string] {
  match $status {
    "OK" => $"(ansi green)OK(ansi reset)"
    "SKIP" => $"(ansi yellow)SKIP(ansi reset)"
    "ERROR" => $"(ansi red)ERROR(ansi reset)"
    _ => $status
  }
}

def status [label: string message: string] {
  print $"[(status-label $label)] ($message)"
}

def field [name: string value: string] {
  print $"($name): ($value)"
}

def print-header [target: string translate: bool burn: bool] {
  print ""
  print $"(ansi cyan)ASR/MT subtitle pipeline(ansi reset)"
  field "Target" $target
  field "Mode" "run"
  field "Rule" "transcribe, optionally translate, optionally burn subtitles"
  field "Translate" (if $translate { "true" } else { "false" })
  field "Burn" (if $burn { "true" } else { "false" })
  print ""
}

def main [
  filename: path # input video file path

  --model (-m): string = "large-v3" # Whisper model size
  --precision (-p): string = "float16" # compute precision
  --lang (-l): string # spoken language code; auto-detect if omitted
  --beam-size: int = 5 # beam search size
  --vad # enable VAD filter

  --translate (-t) # enable NLLB translation
  --src-lang: string = "eng_Latn" # NLLB source language code
  --tgt-lang: string = "zho_Hans" # NLLB target language code

  --burn (-b) # burn subtitles into video
  --encoder (-e): string = "libx264" # FFmpeg video encoder
] {
  let script_dir = "~/scripts/asr_mt_scripts" | path expand
  let image_dir = "~/Code_Program/asr_mt_containers" | path expand
  let asr_image_path = ($image_dir | path join "faster_whisper")
  let mt_image_path = ($image_dir | path join "meta_NLLB")

  if not ($filename | path exists) { error make {msg: $"Error: File '($filename)' not found."} }
  let abs_file = ($filename | path expand)
  let data_dir = ($abs_file | path dirname)
  let file_name = ($abs_file | path basename)
  let file_base = ($abs_file | path parse | get stem)
  let file_ext = ($abs_file | path parse | get extension)

  print-header $abs_file $translate $burn

  # Stage 1: generate source subtitles.
  status "OK" $"[1/3] Transcribing: ($file_name)"
  let orig_srt_filename = $"($file_base).srt"

  mut asr_args = ["/app/transcribe.py" $"/data/($file_name)" "--model" $model "--precision" $precision]
  if ($lang != null) { $asr_args = ($asr_args | append ["--language" $lang]) }
  if $vad { $asr_args = ($asr_args | append ["--vad"]) }

  let asr_out = (
    singularity exec --nv --bind /usr/lib/wsl --bind $"($script_dir):/app" --bind $"($data_dir):/data" --env LD_LIBRARY_PATH=/usr/lib/wsl/lib
    $asr_image_path python3 ...$asr_args
  )

  # Stage 2: optionally translate subtitles.
  mut final_srt_filename = $orig_srt_filename

  if $translate {
    status "OK" $"[2/3] Translating from ($src_lang) to ($tgt_lang)."
    let trans_srt_filename = $"($file_base)_($tgt_lang).srt"
    $final_srt_filename = $trans_srt_filename

    let mt_args = ["/app/translate.py" $"/data/($orig_srt_filename)" $"/data/($trans_srt_filename)" "--src" $src_lang "--tgt" $tgt_lang]

    let mt_out = (
      singularity exec --nv --bind /usr/lib/wsl --bind $"($script_dir):/app" --bind $"($data_dir):/data" --env LD_LIBRARY_PATH=/usr/lib/wsl/lib
      --env HF_HOME=/opt/huggingface --env TRANSFORMERS_OFFLINE=1
      $mt_image_path python3 ...$mt_args
    )
    status "OK" "Translation complete."
  } else {
    status "SKIP" "[2/3] Translation skipped."
  }

  # Stage 3: optionally burn subtitles into the video.
  if $burn {
    status "OK" $"[3/3] Burning subtitles: ($final_srt_filename)"
    let output_video = $"($file_base)_subbed.($file_ext)"

    try {
      cd $data_dir
      ffmpeg -y -v warning -stats -i $file_name -vf $"subtitles='($final_srt_filename)'" -c:v $encoder -c:a copy $output_video
      status "OK" $"Video saved to ($data_dir)/($output_video)"
    } catch {
      status "ERROR" "FFmpeg execution failed."
    }
  } else {
    status "SKIP" "[3/3] Video burning skipped. Pipeline finished."
  }
}