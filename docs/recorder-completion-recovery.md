# Recorder completion and failure handling

Recorder now observes AVAudioRecorder completion and encoding-error callbacks, rather than relying solely on manual Stop or the ten-second timeout. A callback is accepted only for the current recorder instance. It stops that recorder, cancels its timer, releases the microphone lease and checks whether usable output remains. Failure status never claims the recording is ready. Late callbacks from replaced/stopped recorders cannot change current state.

`tests/test_recorder_completion.py` checks delegate wiring and compiles the actual callback and Stop method bodies with explicit controlled recorder/file boundaries. Seven scenarios cover natural completion, unsuccessful completion, encoding error, empty output, and stale callbacks after replacement or stop.

These tests verify the state decisions, not microphone hardware, system permissions, actual AVAudioFile encoding or interruption delivery. Apple SDK compilation and physical iPhone tests remain required. The existing ten-second timeout is retained as a fallback.
