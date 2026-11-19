# Exact licensed human holdout sources (test-only)

These four complete FLAC recordings are from **LibriSpeech ASR corpus**, authored
by Vassil Panayotov, Guoguo Chen, Daniel Povey and Sanjeev Khudanpur, distributed
by OpenSLR: https://www.openslr.org/12 . License: **CC BY 4.0**,
https://creativecommons.org/licenses/by/4.0/ . Full license text is in
`LICENSES/REFERENCE-CC-BY-4.0.txt` at repository root.

No audio changes were made. These are the exact bytes already predeclared in
`probes/reference-context-human-holdouts/sources.json`, not replacement clips.
Original dataset revision, source links, transcripts, speaker IDs, frame counts,
byte counts and SHA-256 hashes are preserved verbatim in `provenance.json`.

Recovery: successful GitHub Actions run **44229678218**, source commit
`2a88ecb79803c2990ab073131621db672648b107`, artifact **14396650003**,
`Production-reference-context-human-holdouts`.
Artifact ZIP size: **2,468,733 bytes**. SHA-256:
`abf2e7b2966e439644dfd71e1765400a0fb962c90827371d8aca4f2212e0b2e1`.
https://github.com/R347H4CK3R/VoiceMatrix-Development/actions/runs/44229678218/artifacts/14396650003

The downloaded ZIP digest and each FLAC's existing pinned digest and size were
verified before adding these copies. The preparation script checks provenance,
full predeclared metadata, size and checksum before decoding, and fails closed
if a source is missing or corrupt. No network fallback, alternate source,
transcoding of stored FLACs, crop, transcript replacement or threshold change.

Both baseline and reference methods still receive the same complete decoded WAV
for each of the four preselected sources, eight cases total. Corpus words remain
evaluation labels, never inference prompts. These clips have now been evaluated
in prior runs: they remain fixed regression/holdout cases, not a fresh blind
population sample. They establish neither voice likeness nor physical-device
performance. Fixtures stay outside application resources and are not packaged
into the app.
