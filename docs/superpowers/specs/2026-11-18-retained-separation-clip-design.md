# Explicit retained-media clip to separation

Goal: choose a 0.5–10 second interval from the current retained Video Voice Studio source and open Separate vocals prefilled, without external Files trimming. Authorization and a Prepare selected clip action are explicit; no model inference, speaker generation or job mutation occurs automatically.

Use a new 44.1 kHz Float32 stereo AVAssetReader extractor. Existing LocalVideoAudio intentionally downmixes to mono24k and applies speech gates, so reusing it would lose channels and reject music. No blanket mix: require exactly one mono/stereo track and reject missing/ambiguous timelines. Existing downstream speech/music/reference gates remain untouched.

Capture current job UUID, safe retained filename and expected source SHA. Under the shared AudioStore lease copy the bounded complete source into exclusive private staging through RetainedMediaReader, verifying the bytes against the retained job SHA before AVFoundation opens them. Extract only from this snapshot, recheck its digest afterward, and atomically publish a canonical short WAV plus bounded provenance receipt recording source identity, requested/actual interval and output digest. Preserve originals, old jobs and completed clips; remove only newly owned incomplete staging. Fail closed on corrupt source, invalid interval, storage or cancellation. Cancel on back/background/job selection changes; only navigate while the original request remains active.

Destination verifies receipt and clip digest, stages the input, and waits for an explicit Separate action. UI labels the selected short interval as experimental, never as the entire source or verified voice identity. No new models, publication, release changes or device-performance claims.

Scratch admission caps existing crash-staging aggregate bytes plus a full new source/WAV reservation at1GiB, with64entry/3filesperstage limits; rejects symlinks/special entries and never silently cleans crash remnants. Destination acceptance can retry when lease becomesavailable or scene returnsactive after cancellation, but never runs inference automatically.

AVURLAsset explicitly sets AVURLAssetReferenceRestrictionsKey to forbidAll: only media inside the verified container can be decoded, never external MOV data references. Apple documents forbidden-reference property loading failure: https://developer.apple.com/documentation/avfoundation/avurlassetreferencerestrictionskey and https://developer.apple.com/documentation/avfoundation/avassetreferencerestrictions .
