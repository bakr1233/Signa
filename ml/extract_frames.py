"""
extract_frames.py

Modernized replacement for the original repo's video-to-frame.py.
Same behavior (hand-segment + grayscale, pad/repeat to a fixed frame
count per video) but cleaned up: no bare os.chdir dance, proper
pathlib, and configurable frame count instead of a hardcoded 201.

Usage:
    python3 extract_frames.py train_videos train_frames --frames-per-video 60
    python3 extract_frames.py test_videos  test_frames  --frames-per-video 60
"""
import argparse
from pathlib import Path

import cv2
from tqdm import tqdm

from handsegment import handsegment


def extract_video(video_path: Path, out_dir: Path, frames_per_video: int):
    out_dir.mkdir(parents=True, exist_ok=True)
    cap = cv2.VideoCapture(str(video_path))
    last_frame = None
    count = 0

    while count < frames_per_video:
        ret, frame = cap.read()
        if not ret:
            break
        out_path = out_dir / f"{video_path.stem}_frame_{count}.jpeg"
        if not out_path.exists():
            frame = handsegment(frame)
            frame = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            last_frame = frame
            cv2.imwrite(str(out_path), frame)
        count += 1
    cap.release()

    # Pad short videos by repeating the last frame so every video
    # produces exactly `frames_per_video` frames (required for the
    # fixed-length RNN input window used later).
    while count < frames_per_video and last_frame is not None:
        out_path = out_dir / f"{video_path.stem}_frame_{count}.jpeg"
        if not out_path.exists():
            cv2.imwrite(str(out_path), last_frame)
        count += 1


def convert(gesture_folder: str, target_folder: str, frames_per_video: int):
    gesture_root = Path(gesture_folder).resolve()
    target_root = Path(target_folder).resolve()
    target_root.mkdir(parents=True, exist_ok=True)

    gestures = sorted(p.name for p in gesture_root.iterdir() if p.is_dir())
    print(f"Source: {gesture_root}")
    print(f"Target: {target_root}")
    print(f"Classes found: {gestures}\n")

    for gesture in tqdm(gestures, unit="class", ascii=True):
        gesture_path = gesture_root / gesture
        out_dir = target_root / gesture
        videos = sorted(p for p in gesture_path.iterdir() if p.is_file())
        for video in tqdm(videos, unit="video", ascii=True, leave=False):
            extract_video(video, out_dir, frames_per_video)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Extract fixed-length frame sequences from gesture videos.")
    parser.add_argument("gesture_folder", help="Folder containing one subfolder of videos per gesture class.")
    parser.add_argument("target_folder", help="Folder to write extracted frames into.")
    parser.add_argument("--frames-per-video", type=int, default=60,
                        help="Fixed number of frames sampled per video (default 60, ~2s at 30fps; "
                             "original repo used 201, which is heavier than needed for live on-device use).")
    args = parser.parse_args()
    convert(args.gesture_folder, args.target_folder, args.frames_per_video)
