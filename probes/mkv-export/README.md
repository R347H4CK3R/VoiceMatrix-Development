# Bounded compressed MKV export probe

Run on macOS with Xcode command-line tools and ffmpeg:

```
python3 -m unittest discover -s tests -p test_mkv_export.py -v
```

The native executable compiles the **production** writer and exporter and calls
`LocalMKVExport.export(input:destination:maxBytes:progress:)` on generated AVC/AAC.
FFmpeg independently decodes both containers and compares decoded audio/video
SHA-256. Existing destinations and B-frame/reordered input must fail without
modifying the MP4 or producing an MKV. The fixture disables MP4 edit lists because
this deliberately narrow first export rejects AAC trim attachments rather than
silently discard priming/padding instructions. This is **not** arbitrary MKV import
or a replacement for the MP4 used by the offline audio-processing pipeline.

The writer copies compressed packet bytes; emits real EBML/Matroska Info, Tracks,
CodecPrivate, bounded finite Clusters/BlockGroups, durations, references and Cues;
and does no decoding or encoding. AVC initialization comes from avcC; AAC-LC
initialization is parsed from the real ES descriptor and strictly compared with
its supported configuration. Unsupported media must offer the retained MP4 as
an explicitly labeled fallback, not a renamed file.

No native result is claimed from Linux: the test is skipped there. macOS compile,
decode parity, and sample timing evidence are required before shipping. This
initial implementation is not yet physical-device tested. Integration must reserve
the additional export in the existing 2 GB retained-storage budget and leave the
MP4 decoder companion available. The exporter independently enforces a 512 MiB
output ceiling and 800 MB free-space reserve. It does not enforce the caller's
library-wide retained budget, which is an acquisition/storage-layer responsibility.
