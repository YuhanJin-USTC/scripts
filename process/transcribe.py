import argparse
import math
import os
import sys
from collections.abc import Sequence

from faster_whisper import WhisperModel


def format_timestamp(seconds: float) -> str:
    """Convert seconds to SRT time format."""
    hours = math.floor(seconds / 3600)
    seconds %= 3600
    minutes = math.floor(seconds / 60)
    seconds %= 60
    milliseconds = round((seconds - math.floor(seconds)) * 1000)
    seconds = math.floor(seconds)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d},{milliseconds:03d}"


def generate_subtitles(
    filename: str,
    model_size: str,
    compute_type: str,
    language: str | None,
    beam_size: int,
    vad_filter: bool,
) -> str:
    # Load the GPU Whisper model inside the ASR container.
    print(f"Loading model: {model_size} ({compute_type}).", file=sys.stderr)
    model = WhisperModel(model_size, device="cuda", compute_type=compute_type)

    print(f"Transcribing: {filename}.", file=sys.stderr)

    segments, info = model.transcribe(
        filename,
        beam_size=beam_size,
        language=language,
        vad_filter=vad_filter,
        word_timestamps=True,
    )

    if info.language_probability > 0:
        print(
            f"Source language: {info.language} ({info.language_probability:.2f}).",
            file=sys.stderr,
        )

    # Write SRT next to the input file.
    base_name = os.path.splitext(filename)[0]
    suffix = ".srt"
    output_file = f"{base_name}{suffix}"

    with open(output_file, "w", encoding="utf-8") as f:
        for i, segment in enumerate(segments, start=1):
            start_time = format_timestamp(segment.start)
            end_time = format_timestamp(segment.end)
            text = segment.text.strip()
            print(f"[{start_time} --> {end_time}] {text}", file=sys.stderr)
            f.write(f"{i}\n{start_time} --> {end_time}\n{text}\n\n")

    print(f"[OK] Subtitles saved to: {output_file}", file=sys.stderr)
    sys.stdout.write(f"OUTPUT_SRT:{output_file}\n")
    sys.stdout.flush()
    return output_file


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Generate SRT subtitles with faster-whisper."
    )
    parser.add_argument("filename", help="Path to input media file")
    parser.add_argument("--model", default="large-v3", help="Whisper model size")
    parser.add_argument(
        "--vad", action="store_true", help="Enable VAD filter to remove silences"
    )
    parser.add_argument("--precision", default="float16", help="CUDA compute type")
    parser.add_argument("--language", default=None, help="Source language code")
    parser.add_argument("--beam-size", type=int, default=5, help="Beam search size")

    args = parser.parse_args(argv)

    if not os.path.exists(args.filename):
        print(f"[ERROR] Input file not found: {args.filename}.", file=sys.stderr)
        return 1

    generate_subtitles(
        args.filename,
        args.model,
        args.precision,
        args.language,
        args.beam_size,
        args.vad,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
