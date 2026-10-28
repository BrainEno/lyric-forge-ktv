---
name: lyrics-pipeline-task
description: Build and refine the local lyrics generation pipeline from audio import to editable timestamped lyric draft.
license: MIT
compatibility: opencode
metadata:
  audience: engineering
  workflow: audio-lyrics
---

## What I do

I help implement or refine the lyrics pipeline:
audio import -> preprocess -> vocal-focused transcription -> segment merge -> editable timed lyrics.

## Pipeline principles

- prefer transcribing vocal stem over full mix
- treat output as draft lyrics, not final truth
- preserve segment boundaries and timing metadata
- do not silently discard low-confidence segments
- keep pipeline resumable

## UX expectations

The user should always see:
- current stage
- progress
- failure reason
- retry path

## When to use me

Use this skill when:
- adding import pipeline steps
- changing transcription logic
- implementing merge / dedupe / line grouping
- improving lyric timing or editable output
- exporting LRC or internal project lyrics files

## Output expectations

1. define current stage boundaries
2. name artifacts produced per stage
3. implement with traceable intermediate outputs
4. surface likely error points
5. avoid promising perfect lyric accuracy