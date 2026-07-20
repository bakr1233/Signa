"""
handsegment.py

Unchanged from the original hthuwal/sign-language-gesture-recognition
repo: a crude HSV/BGR skin-color range mask used to isolate the signer's
hands before feature extraction. Still valid with modern OpenCV, kept
as-is (only cleaned up dead comments).
"""
import numpy as np
import cv2

BOUNDARIES = [
    ([0, 120, 0], [140, 255, 100]),
    ([25, 0, 75], [180, 38, 255]),
]


def handsegment(frame):
    (lower1, upper1), (lower2, upper2) = BOUNDARIES
    mask1 = cv2.inRange(frame, np.array(lower1, dtype="uint8"), np.array(upper1, dtype="uint8"))
    mask2 = cv2.inRange(frame, np.array(lower2, dtype="uint8"), np.array(upper2, dtype="uint8"))
    mask = cv2.bitwise_or(mask1, mask2)
    return cv2.bitwise_and(frame, frame, mask=mask)


if __name__ == "__main__":
    frame = cv2.imread("test.jpeg")
    handsegment(frame)
