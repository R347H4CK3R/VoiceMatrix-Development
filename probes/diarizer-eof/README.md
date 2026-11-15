# Diagnostic only: source-bounded FluidAudio reconstruction

Upstream: FluidInference/FluidAudio, ee78635d23d52379117554ba72358b65a0612447 (Apache-2.0).
See included license. Modified files and exact before/after SHA-256 values are in manifest.json; changes are marked in the patch. This is not an upstream release or a production dependency update.

The retained 36.5993125-second sample produced a final raw end of 36.68930435180664 seconds. This exceeds the unchanged app 50 ms guard. The upstream reconstruction aggregates full zero-padded windows, rather than bounding its timeline to source samples. This is not merely a single model-frame rounding error.

The experiment bounds aggregation by decoded sample count, discards votes outside that timeline, and intersects the final valid frame with EOF. It does not clamp an arbitrarily invalid segment or relax app validation. True overlapping segments remain overlapping and are rejected for reference selection as before.

The patch is applied only to a clean diagnostic checkout at the pinned revision, with original and resulting file hashes checked. The pinned package is freshly resolved; the generated Package.resolved is retained and checked unchanged across the experiment. Proof identifies a **modified dependency**, not an unmodified frozen build. All production app files and release artifacts remain untouched. Any later adoption needs an explicitly versioned dependency and updated complete source proof.

Native XCTest and the exact retained audio must pass before interpreting this as a working fix. Linux patch/guard tests do not prove Apple compilation or model inference.
