# Reference playback ownership

A reference lookup crosses an actor boundary. Its response must not start audio after the user changes the selected voice, removes/replaces that reference, starts another operation, leaves the screen, or stops playback.

`CharacterLibrary.listenToReference` binds a lookup to a request ID, selected character/reference identity, active/idle state, and `AudioStore.playbackGeneration`. All `AudioStore.stop()` calls advance that generation, including existing view disappearance and new-play paths. Stale lookup errors cannot overwrite newer status text.

`tests/test_reference_playback_ownership.py` compiles the actual production request method and stop method, with a controlled delayed store and audio boundary. Thirteen scenarios cover success, changed selection/reference, removal, busy/inactive states, recording/processing, superseding requests, stale errors, stop and background/foreground return and selecting away/back. The first version failed nine assertions; a subsequent stopped-playback regression also failed before the generation fence was added. Background transitions independently invalidate pending reference requests.

These checks do not verify AVAudioPlayer, hardware sound, UI navigation, or iPhone execution. Those still require the native gate and device testing.
