# Synthetic adaptive-merge inputs

Original generated test media, not user recordings. H.264 video-only black
frames and ALAC audio-only 220Hz tone are each exactly three seconds. They
replace simulator AVAssetWriter fixture generation that stalled at frame 2,
before production merge was called. No expected merged output is provided.

Generation commands (FFmpeg):

```
ffmpeg -v error -f lavfi -i 'color=c=black:s=160x96:r=10:d=3' -an -c:v libx264 -pix_fmt yuv420p -movflags +faststart adaptive-video.mp4
ffmpeg -v error -f lavfi -i 'sine=frequency=220:sample_rate=16000:duration=3' -af volume=0.24 -ac 1 -c:a alac -movflags +faststart adaptive-audio.m4a
```

SHA-256:
- adaptive-video.mp4: b0710067fc17fdad4b0d1ad426f4105a64139ab62f41d05f0572dcd3a14b087e
- adaptive-audio.m4a: 40834af6eb24a2e0fb751703f65c003215960f44abf05ef7e134d2ca69104516

These files enter only the unit-test bundle. Native XCTest validates their
separate track types and durations, copies them to a fresh temporary folder,
then calls the actual production merge and digest verification. It still
requires both output tracks, three-second duration, the same byte bound and
byte-for-byte preservation of both original inputs. This is not a device,
real-video, voice-likeness or full workflow acceptance claim.

The audio fixture uses lossless ALAC to avoid AAC priming/skip-sample metadata.
The former AAC fixture measured 3.000s in ffprobe but 2.932s in native
AVFoundation. The exact three-second native assertion remains unchanged;
only the test input codec changes. Native verification is still required.
