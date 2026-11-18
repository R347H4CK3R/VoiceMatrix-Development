# Complete licensed regression recordings

These unchanged LibriSpeech recordings are from OpenSLR 12, distributed under
CC BY 4.0. Attribution: LibriSpeech, Vassil Panayotov, Guoguo Chen, Daniel Povey,
and Sanjeev Khudanpur. Source: https://www.openslr.org/12
License: https://creativecommons.org/licenses/by/4.0/ (full text in
`LICENSES/REFERENCE-CC-BY-4.0.txt`). No audio modifications were made here.

The original source identities, dataset revision, byte SHA-256 digests and
reference texts are retained in `probes/human-local-studio/sources.json`.
These are previously studied recordings, not blind holdouts.

Recovered from successful run 44220101199, artifact 14390322032 in
R347H4CK3R/VoiceMatrix-Development. Artifact ZIP SHA-256:
`330be7c0b75cdfbf462fe5a7898211719786be83aa47f5fc0a2677625beb5173`.
Each extracted FLAC was checked against its pre-existing sourceSHA256.

Keeping these small test-only inputs in source removes the external dataset
server as a prerequisite for the regression gates. They are not app resources.
Preparation still checks every original digest before decoding; corruption
fails closed with no network substitution or altered thresholds.
