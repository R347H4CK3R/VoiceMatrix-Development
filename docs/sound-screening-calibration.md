# Native sound-screening calibration — 2026-11-15

## Failure and cause

Human-pipeline run 43681000037 recognized both independent LibriSpeech transcripts with word error rate 0, but rejected all six reference crops before generation. The production adapter used one-second SoundAnalysis windows. Their peak music scores were 0.213–0.398, with some singing scores also above the unchanged 0.2 rejection threshold. Correct recognition alone does not prove uncontaminated audio.

Apple documents that longer windows can improve sound classification accuracy while reducing timing precision: https://developer.apple.com/documentation/soundanalysis/snclassifysoundrequest/windowduration . A controlled native comparison changed window length only, holding the hop at 0.5 seconds and retaining every score/coverage threshold.

## Controlled comparison and independent checks

Initial run 43682673919 (source 9a35243fd84acb3d02c154bcd441bc1afc116146) admitted 0/6 speech crops at 1 second, 3/6 at 2 seconds and 6/6 at 3 seconds. All settings rejected all eight unsuitable controls. This selected the three-second candidate.

An expanded validation added two speakers not used to choose the setting and two brief piano bursts in speech. Run 43683038369 initially admitted 7/8 speech clips and rejected 10/10 unsuitable clips. The remaining 1.98-second speech clip had an Apple frame starting at -0.00025 seconds; strict timestamp validation rejected it despite speech confidence 0.977 and low music/singing scores. The exact returned frame became a failing compiled regression before the timing repair.

Final native run 43683298075 (source f8b21b350874f9944d7bfecc94cb9e11f9281407) PASSED:

| Window | Speech admitted | Unsuitable admitted |
| --- | ---: | ---: |
| 1 second | 0/8 | 0/10 |
| 2 seconds | 5/8 | 0/10 |
| 3 seconds | 8/8 | 0/10 |

The eight speech clips represent four speakers, not eight independent speakers. Six crops come from the two original failing recordings. Unsuitable controls comprise piano, three human choral excerpts, two continuous speech/music mixtures (0 and 10 dB speech-to-music RMS), two brief music bursts (0.5 and 1 second at 0 dB), silence and a sine tone. These are a small, deliberately selected regression set, not a population estimate or blind perceptual validation. Labels/provenance are corpus/source descriptions and controlled construction, not a new human listening assessment.

## Production change

Commit 6ef440d3b13d1f93f5cae5df0c3bbe2aed7a1924 caps the analysis window at min(3 seconds, source duration), retaining the half-second hop. Policy version 2 causes retained jobs to recheck old screening results. Music/singing thresholds (0.2), speech score (0.5), speech coverage (0.6), and analysis coverage (0.8) are unchanged.

Commit 70d0f5668c752d581b947329968bd4160cce171c permits at most one millisecond of negative classifier timestamp rounding. Coverage clips starts to zero; pre-source time is never counted. More negative timestamps and windows entirely before the source still fail. The exact real short-clip regression passed after this repair.

## Evidence and provenance

JSON summaries, fixture manifests and final raw classifier frames are under `qa/sound-screening-20261115`. Full archives and audio are preserved in the workspace and GitHub artifacts (14-day retention); the calibration workflow currently requires the original baseline artifact, so it needs that evidence restored if rerun after expiration. Production inference does not depend on these artifacts.

Archive SHA-256:

- Initial calibration: `565ba24f4e09cc2fc8e5bc0eb974eb396e4dc2f67b3a931a13c839b7bf12dc72`
- Validation before clock fix: `6091fdd2ad5008f2d2f1a2fef1aaa45c423969fe07da6d66f0f865f11575e065`
- Final validation: `dc5dcad2f5237a06b83cbe131525049f22cecff22c40e64c7639a8ba2be18d04`

Speech: LibriSpeech, CC BY 4.0, https://www.openslr.org/12 . Piano: Roux, CC0, https://commons.wikimedia.org/wiki/File:Eb_major_piano.ogg . Singing: Alabama Sacred Harp Singers, Sherburne, unrestricted free-use permission recorded at https://commons.wikimedia.org/wiki/File:Alabama_Sacred_Harp_Singers_-_Sherburne.ogg . Original URLs, source hashes, authors and licenses are pinned in `probes/sound-screening/sources.json`, `validation-speech.json`, and each generated manifest. No voice identity, training rights, or synthesized likeness claim is inferred from these classifier tests.

## Limits

This is macOS SoundAnalysis evidence, not physical-iPhone verification. Broad background-noise/music diversity, independent human listening and target-voice similarity remain unresolved. Build 7 does not contain these new production fixes; no new IPA was published during this calibration work.

## Regression tests

The final portable repository command `python3 -m unittest discover -s tests -v` ran 778 tests in 271.080 seconds with no failures and five skips. The skipped yt-dlp selector test passed separately in the existing isolated acquisition environment. Three Windows integration tests and one Apple selective-download integration test were not run by this Linux suite. After the timestamp repair, all 24 focused sound-policy, coordinator and pipeline tests passed, including compiled Swift policy execution. These checks do not substitute for native model execution or device testing.

## Full real-human generation rerun

Run [43683038370](https://github.com/R347H4CK3R/VoiceMatrix-Development/actions/runs/43683038370), source deddd3f2f1efdefd1ec50861a68a6db224ea44fe, compiled successfully and reran both complete offline workflows. This source includes the three-second window change; the later submillisecond policy repair was validated separately by native run 43683298075.

Both recordings now pass screening on their primary reference, generate word-checked previews, and save a reference profile while preserving prior voices. Source 2961 completes cancellation/resume, fresh-store reload, idempotent resume and new-sentence generation with word error rate 0. Its new speech is 2.933 seconds of mono 24 kHz PCM; SHA-256 4dd654ffbd4e92f7251cdade25f67597729a4b2b16d69e6bbdfedb10874a3c81.

Source 4507 creates its profile and passes preview word verification, but final recognition of the later generated sentence throws OnDeviceTranscription.Failure.noSpeech. This is not proof of silence or an explanation of the underlying generation/recognition cause. The original diagnostic copied final generated audio only after successful recognition, so that failed final waveform was not captured in the artifact. Its 9.483-second preview is retained. The diagnostic has now been changed to copy every final attempt before recognition and write its expected text/hash. This evidence-retention change passed Swift syntax and six diagnostic source checks; it has not been executed on Apple hardware in this pass.

Reference/preview cosine diagnostics were 0.7874 and 0.7591 respectively, without a likeness acceptance threshold or human assessment. The rerun overall FAILED (one of two full workflows passed), despite fixing the original screening blockage for both. The remaining generated-sentence failure requires another measured investigation with its waveform preserved.

Full artifact SHA-256: 449d8a1dc8d89bc7dee5ee76c0160635a6e95c3a7f00b595d6265bc32cc333c9. Reports are under qa/sound-screening-20261115/human-generation; WAVs are preserved in the artifact and workspace. No additional release was made.
