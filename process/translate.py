import argparse
import sys
from collections.abc import Sequence

import pysrt
import torch
from tqdm import tqdm
from transformers import AutoModelForSeq2SeqLM, NllbTokenizer

MODEL_FLAT_PATH = "/opt/nllb-model"


def translate_srt(
    input_srt: str, output_srt: str, src_lang: str, tgt_lang: str
) -> None:
    print("Loading NLLB-1.3B model from flat directory.", file=sys.stderr)

    # Load the offline tokenizer.
    tokenizer = NllbTokenizer.from_pretrained(
        MODEL_FLAT_PATH, src_lang=src_lang, local_files_only=True
    )

    # Load model on GPU in float16.
    model = AutoModelForSeq2SeqLM.from_pretrained(
        MODEL_FLAT_PATH,
        dtype=torch.float16,
        use_safetensors=True,
        local_files_only=True,
    ).to("cuda")

    print(f"Parsing SRT file: {input_srt}.", file=sys.stderr)
    subs = pysrt.open(input_srt)

    original_texts = [sub.text for sub in subs]
    translated_texts = []

    print(
        f"Translating {len(original_texts)} segments from {src_lang} to {tgt_lang}.",
        file=sys.stderr,
    )

    for text in tqdm(original_texts, desc="Translating", file=sys.stderr):
        if not text.strip():
            translated_texts.append("")
            continue

        inputs = tokenizer(text, return_tensors="pt").to("cuda")

        forced_bos_token_id = tokenizer.convert_tokens_to_ids(tgt_lang)

        translated_tokens = model.generate(
            **inputs, forced_bos_token_id=forced_bos_token_id, max_length=128
        )

        translated_text = tokenizer.batch_decode(
            translated_tokens, skip_special_tokens=True
        )[0]
        translated_texts.append(translated_text)

    for i, sub in enumerate(subs):
        sub.text = translated_texts[i]

    # Save translated subtitles as UTF-8 SRT.
    subs.save(output_srt, encoding="utf-8")
    print(f"[OK] Translated SRT saved to: {output_srt}", file=sys.stderr)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Translate SRT files using Meta NLLB.")
    parser.add_argument("input_srt", help="Path to input SRT file")
    parser.add_argument("output_srt", help="Path to output SRT file")
    parser.add_argument("--src", required=True, help="Source language code")
    parser.add_argument("--tgt", required=True, help="Target language code")

    args = parser.parse_args(argv)

    translate_srt(args.input_srt, args.output_srt, args.src, args.tgt)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
