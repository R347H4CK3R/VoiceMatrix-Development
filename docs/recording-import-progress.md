# Bounded recording import

The recording import loop previously trusted every successful decoder read to advance the file position. A read that returned no frames, or returned frames without advancing its position, repeatedly ran on the main actor and could leave the interface unable to respond.

The loop now requires positive frames and forward position progress before writing. Failure uses the existing transactional error path: close the writer, remove the partial imported WAV, retain the user's prior recording and display an import error.

`tests/test_recording_import_progress.py` compiles the exact production import method with controlled AVAudioFile/AVAudioPCMBuffer boundaries and real temporary files. Both non-progress conditions timed out before the fix; after the fix, both reject cleanly and a valid read still replaces the prior recording. These are host tests of handling, not evidence of actual iOS decoder behavior or a complete native build.

A separately reproduced buffer-allocation failure also left an orphan temporary WAV. Allocation now occurs inside the same cleanup boundary; its failure preserves previous audio and removes the partial file. The controlled suite includes all four scenarios.
