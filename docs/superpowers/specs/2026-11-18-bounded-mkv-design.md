# Bounded MP4-to-MKV export

## Intent and constraints
Create a genuine optional MKV alongside the retained MP4, entirely on device. No laptop, server, source deletion, renamed containers, lowered parity checks, or release changes. MP4 remains the AVFoundation processing companion. Unsupported files keep the explicit MP4 fallback.

## Approaches considered
1. AVAssetReader compressed buffers: rejected after native experiments exposed unmarked control buffers, grouped AAC packets and trim transformations. Copy ownership and separate readers do not resolve these semantics.
2. Minimal FFmpeg libavformat MOV demux/Matroska mux: mature broad solution, but introduces new pinned native device/simulator builds and LGPL distribution/relink/source obligations. FFmpegKitNext adds a larger source-build wrapper and LGPL3 obligations. Not introduced in this iteration.
3. Bounded original MP4 sample-table reader: selected engineering choice under delegated implementation authority. No third-party binary/dependency/licensing change. Explicit narrow support, independently checked against FFmpeg packet/decoded output.

Primary dependency references: https://ffmpeg.org/libavformat.html ; https://ffmpeg.org/doxygen/trunk/remuxing_8c-example.html ; https://ffmpeg.org/legal.html ; https://github.com/arthenica/ffmpeg-kit-next . These are comparative research, not incorporated dependencies.

## Scope
Unfragmented self-contained MP4 with exactly one AVC video track and one AAC-LC mono/stereo track. One sample description, bounded stts/stsc/stsz/stco or co64/stss, no reordered presentation, no unsupported edit lists or transforms, no encryption/external references. Exact AAC roll=-1 groups covering every sample are represented as one-packet Matroska SeekPreRoll, never as a timestamp shift. Final AAC duration must be an integral1–1024 decoded samples; nonfinal packets must be exactly1024. Final padding is represented as positive signed Matroska DiscardPadding, not deletion of compressed bytes; other groups reject. Square-pixel pasp1:1 is accepted, other aspect transforms reject. Preserve original packet bytes and exact sample-table timeline before Matroska millisecond quantization. Reject unsupported structures, do not guess.

Limits: 512 MiB source/output, 16 MiB metadata/sample, 300,000 total packets, 3–1800 seconds, 1280x720 maximum video, 180-second exporter deadline, cancellation checks and original file identity verification. Existing 2 GB retained-library and 800 MB free-space policies remain.

## Verification and limitations
Real native compiler; synthetic real-media decode parity; independent packet hashes and timing; malformed offsets/counts/edit/codec/fragment rejection; source/destination preservation; cancellation/size failures. No physical-device or live website success is inferred. Real merged download files may use unsupported edits and fall back to MP4. Broad edits/B-frames/fragmentation need a separately vetted demux implementation rather than unbounded parser expansion.
