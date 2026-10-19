#!/usr/bin/env python3
"""Create bundled Mandarin Mahjong clips with the installed macOS Tingting voice."""

from pathlib import Path
import subprocess
import tempfile
import shutil


ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "Resources" / "MahjongAudio"
FFMPEG = shutil.which("ffmpeg")

NUMBERS = ["一", "二", "三", "四", "五", "六", "七", "八", "九"]
CLIPS = {
    f"tile-{suit}-{value}": f"{number}{label}"
    for suit, label in (("characters", "万"), ("dots", "筒"), ("bamboo", "条"))
    for value, number in enumerate(NUMBERS, start=1)
}
CLIPS.update(
    {
        "tile-honor-0": "东风",
        "tile-honor-1": "南风",
        "tile-honor-2": "西风",
        "tile-honor-3": "北风",
        "tile-honor-4": "红中",
        "tile-honor-5": "发财",
        "tile-honor-6": "白板",
        "action-chi": "吃",
        "action-pong": "碰",
        "action-kong": "杠",
        "action-exposed-kong": "明杠",
        "action-concealed-kong": "暗杠",
        "action-added-kong": "补杠",
        "action-win": "和了",
        "action-self-draw": "自摸",
        "action-draw": "流局",
        "action-pass": "过",
        "action-missing-suit": "定缺",
    }
)


def run(*command: str) -> None:
    subprocess.run(command, check=True)


def main() -> None:
    voices = {
        "female": ("Tingting", False),
        # macOS on this release host only has Tingting's mainland Mandarin voice
        # installed. Lower the pitch by three semitones for the male voice bank.
        "male": ("Tingting", True),
    }
    for gender, (voice, lower_pitch) in voices.items():
        output_directory = DESTINATION / gender
        output_directory.mkdir(parents=True, exist_ok=True)
        for name, phrase in CLIPS.items():
            with tempfile.TemporaryDirectory(prefix="jarvis-mahjong-audio-") as temporary:
                temporary_path = Path(temporary)
                source = temporary_path / "source.aiff"
                encoded_source = source
                run("/usr/bin/say", "-v", voice, "-o", str(source), phrase)
                if lower_pitch:
                    if not FFMPEG:
                        raise RuntimeError("ffmpeg is required to create the lowered-pitch voice bank")
                    encoded_source = temporary_path / "male.aiff"
                    run(
                        FFMPEG,
                        "-y",
                        "-hide_banner",
                        "-loglevel",
                        "error",
                        "-i",
                        str(source),
                        "-af",
                        "asetrate=18522,atempo=1.190476,aresample=22050",
                        "-c:a",
                        "pcm_s16be",
                        str(encoded_source),
                    )
                run(
                    "/usr/bin/afconvert",
                    str(encoded_source),
                    "-o",
                    str(output_directory / f"{name}.m4a"),
                    "-f",
                    "m4af",
                    "-d",
                    "aac ",
                    "-b",
                    "64000",
                )
        print(f"Generated {len(CLIPS)} Mandarin clips: {gender}")


if __name__ == "__main__":
    main()
