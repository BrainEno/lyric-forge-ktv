# Lyric quality baseline

3 song(s), 9 candidate document(s), match threshold 0.6.

## By engine

| engine | songs | recall | precision | CER | WER | duplicate rate | line ratio | start MAE | within 500 ms |
|---|---|---|---|---|---|---|---|---|---|
| fused | 3 | 100.0% | 80.8% | 14.8% | 18.1% | 0.0% | 1.24 | 0 ms | 100.0% |
| qwen-only | 3 | 81.0% | 100.0% | 17.2% | 20.0% | 0.0% | 0.81 | 0 ms | 100.0% |
| whisper-only | 3 | 81.0% | 65.4% | 2.8% | 3.2% | 0.0% | 1.24 | 88 ms | 94.1% |

## By song

| song | engine | ref lines | out lines | matched | recall | CER | duplicates | start MAE |
|---|---|---|---|---|---|---|---|---|
| fixture-en | qwen-only | 8 | 7 | 7 | 87.5% | 13.3% | 0 | 0 ms |
| fixture-en | whisper-only | 8 | 10 | 7 | 87.5% | 3.3% | 0 | 0 ms |
| fixture-en | fused | 8 | 10 | 8 | 100.0% | 12.7% | 0 | 0 ms |
| fixture-zh | qwen-only | 7 | 5 | 5 | 71.4% | 31.5% | 0 | 0 ms |
| fixture-zh | whisper-only | 7 | 8 | 5 | 71.4% | 0.0% | 0 | 0 ms |
| fixture-zh | fused | 7 | 8 | 7 | 100.0% | 16.7% | 0 | 0 ms |
| fixture-ja | qwen-only | 6 | 5 | 5 | 83.3% | 16.4% | 0 | 0 ms |
| fixture-ja | whisper-only | 6 | 8 | 5 | 83.3% | 3.6% | 0 | 300 ms |
| fixture-ja | fused | 6 | 8 | 6 | 100.0% | 20.0% | 0 | 0 ms |

## Secondary-only retention

4 of 4 reference line(s) heard only by the secondary engine survive fusion (100.0%); 4 are marked for review.
