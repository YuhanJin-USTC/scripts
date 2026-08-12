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
  let text = $"[(status-label $label)] ($message)"
  if $label == "ERROR" {
    print --stderr $text
  } else {
    print $text
  }
}

def field [name: string value: string] {
  print $"($name): ($value)"
}

def check-command [command: string] {
  if ((which $command) | is-empty) {
    status "ERROR" $"Command not found: ($command)."
    exit 1
  }
}

def check-path [path: string name: string] {
  if not ($path | path exists) {
    status "ERROR" $"Missing ($name): ($path)."
    exit 1
  }
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
  let script_dir = ($env.CURRENT_FILE | path dirname | path expand)
  let image_dir = "~/Code_Program/asr_mt_containers" | path expand
  let asr_image_path = ($image_dir | path join "faster_whisper")
  let mt_image_path = ($image_dir | path join "meta_NLLB")
  let transcribe_path = ($script_dir | path join "transcribe.py")
  let translate_path = ($script_dir | path join "translate.py")

  if not ($filename | path exists) {
    status "ERROR" $"Input file not found: ($filename)."
    exit 1
  }

  check-command "singularity"
  if $burn { check-command "ffmpeg" }
  check-path $transcribe_path "transcription helper"
  check-path $asr_image_path "ASR image"
  if $translate {
    check-path $translate_path "translation helper"
    check-path $mt_image_path "MT image"
  }

  let abs_file = ($filename | path expand)
  let data_dir = ($abs_file | path dirname)
  let file_name = ($abs_file | path basename)
  let file_base = ($abs_file | path parse | get stem)
  let file_ext = ($abs_file | path parse | get extension)

  print-header $abs_file $translate $burn

  print $"[1/3] Transcribing: ($file_name)"
  let orig_srt_filename = $"($file_base).srt"

  mut asr_args = [
    "/app/transcribe.py"
    $"/data/($file_name)"
    "--model" $model
    "--precision" $precision
    "--beam-size" ($beam_size | into string)
  ]
  if ($lang != null) { $asr_args = ($asr_args | append ["--language" $lang]) }
  if $vad { $asr_args = ($asr_args | append ["--vad"]) }

  ^singularity exec --nv --bind /usr/lib/wsl --bind $"($script_dir):/app" --bind $"($data_dir):/data" --env LD_LIBRARY_PATH=/usr/lib/wsl/lib $asr_image_path python3 ...$asr_args
  let asr_exit_code = $env.LAST_EXIT_CODE
  if $asr_exit_code != 0 {
    status "ERROR" $"Transcription failed with code ($asr_exit_code)."
    exit $asr_exit_code
  }
  status "OK" "Transcription completed."

  mut final_srt_filename = $orig_srt_filename

  if $translate {
    print $"[2/3] Translating: ($src_lang) -> ($tgt_lang)"
    let trans_srt_filename = $"($file_base)_($tgt_lang).srt"
    $final_srt_filename = $trans_srt_filename

    let mt_args = ["/app/translate.py" $"/data/($orig_srt_filename)" $"/data/($trans_srt_filename)" "--src" $src_lang "--tgt" $tgt_lang]

    ^singularity exec --nv --bind /usr/lib/wsl --bind $"($script_dir):/app" --bind $"($data_dir):/data" --env LD_LIBRARY_PATH=/usr/lib/wsl/lib --env HF_HOME=/opt/huggingface --env TRANSFORMERS_OFFLINE=1 $mt_image_path python3 ...$mt_args
    let mt_exit_code = $env.LAST_EXIT_CODE
    if $mt_exit_code != 0 {
      status "ERROR" $"Translation failed with code ($mt_exit_code)."
      exit $mt_exit_code
    }
    status "OK" "Translation completed."
  } else {
    status "SKIP" "[2/3] Translation skipped."
  }

  if $burn {
    print $"[3/3] Burning subtitles: ($final_srt_filename)"
    let output_video = $"($file_base)_subbed.($file_ext)"

    cd $data_dir
    ^ffmpeg -y -v warning -stats -i $file_name -vf $"subtitles='($final_srt_filename)'" -c:v $encoder -c:a copy $output_video
    let ffmpeg_exit_code = $env.LAST_EXIT_CODE
    if $ffmpeg_exit_code != 0 {
      status "ERROR" $"FFmpeg failed with code ($ffmpeg_exit_code)."
      exit $ffmpeg_exit_code
    }
    status "OK" $"Subtitle burn-in completed: ($data_dir)/($output_video)"
  } else {
    status "SKIP" "[3/3] Subtitle burn-in skipped."
  }

  status "OK" "ASR/MT processing completed."
}
