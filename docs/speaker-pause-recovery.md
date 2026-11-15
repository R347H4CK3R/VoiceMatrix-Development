# Recovery of a missed paused speaker

The preserved real LibriSpeech A/B fixture exposed a failure: A's two longer Silero regions each failed full/half stability (about 0.598 and 0.605); three shorter regions were omitted. Independently measured full-region embeddings of the adjacent longer A regions matched at 0.791 cosine. The original stability gate was evaluating short phonetic fragments rather than a longer coherent sample.

The CPU candidate backend now considers adjacent disjoint region pairs, only when each is 3–8 seconds, the silent gap is at most 600 ms, the combined interval is at most 12 seconds, and their independently measured embeddings match at >=0.70 cosine (the existing clustering threshold). Pairing never chains through a third region, never jumps an intervening VAD region, and performs at most 512 additional embeddings, each at most eight seconds. The original clipping, energy and >=0.65 full/half stability gates still apply to the resulting candidate windows. Group clustering is unchanged. Cancellation is checked between embeddings.

Same real models, hashes, source WAVs and CPU runtime as cloud-speaker-real.md, with socket networking blocked:
- Silence: zero groups before and after.
- A alone: zero groups before, one after.
- B alone: one group before and after.
- Assembled A-B-A: one group before, two after. All accepted intervals independently map to their known source-speaker boundaries; group 1 is A and group 2 is B.
- Additional real A/B excerpts separated by only 300 ms were not paired; their cosine was -0.0310.

The original report remains untouched. Corrected results, the baseline embedding diagnosis, and boundary/safety results are in qa/cloud-speaker-real. The saved real_speaker_check.py reproducer exercises the current production backend.

Verification: 52 speaker/candidate/preparation regressions passed, then the six-case pairing suite passed after adding cancellation and nontransitive coverage. This is a targeted correction on previously used speech, not an independent broad benchmark. Eight regions remain omitted in the assembled fixture. Very short turns, naturally overlapping conversation, noise/music and missed VAD interjections can still fail; no speaker identity is verified. Pairing does not provide source separation. No thresholds were lowered, original source/models were preserved, GeForce was untouched, and this does not validate the separate iPhone CoreML diarizer. No release was published.
