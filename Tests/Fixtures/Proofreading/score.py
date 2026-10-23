"""Scores a proofread SRT against the clean SRT it was made from.

usage: python3 score.py clean.srt typos.srt proofread.srt
Counts word-level differences from the clean text before and after proofreading.
"""
import re
import sys


def words(path):
    lines = [l for l in open(path, encoding="utf-8").read().splitlines()
             if l.strip() and "-->" not in l and not l.strip().isdigit()]
    return re.findall(r"[\wёЁ]+|[.,!?:;—-]", " ".join(lines).replace("ё", "е").replace("Ё", "Е"))


def distance(a, b):
    prev = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        cur = [i] + [0] * len(b)
        for j, y in enumerate(b, 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x != y))
        prev = cur
    return prev[-1]


clean, typos, fixed = (words(p) for p in sys.argv[1:4])
before = distance(clean, typos)
after = distance(clean, fixed)
print(f"errors before {before}, after {after}, fixed {max(0, before - after)}")
