# Runtime Lessons

This note captures hard-won Gala runtime diagnosis lessons. Keep it short and update it when a bug teaches a reusable rule.

## Diagnosis Order

1. Capture Wine logs and the exact user-visible symptom before changing profiles.
2. Classify the failure: D3D/rendering, DirectShow, Media Foundation, codec/container, font/codepage, or path/registry.
3. Inspect local files before trusting VNDB: executable imports, DLLs, archive types, movie files, and fake extensions.
4. Probe media files with `ffprobe` when OP/logo/movie playback is involved.
5. Change one variable per experiment and record what changed: Wine variant, DXMT, DirectShow/LAV, Media Foundation, codec/container, locale.
6. Validate risky runtime changes in a temporary prefix before changing shared profile code.

## Playback Failure Taxonomy

- D3D/rendering failures usually show black screen, shader/device errors, or audio with no visuals. Check D3D11/DXGI/DXMT before touching media filters.
- DirectShow failures usually affect OP/logo/movie clips while the game itself can still run. Check `quartz`, `amstream`, LAV filters, ASF/WMV signatures, and fake `.dat` extensions.
- Media Foundation failures are separate from DirectShow. Look for `MFStartup`, `MFCreateMediaSession`, `MFPlat`, Wine GStreamer logs, and WMV/WMA behavior.
- Codec/container failures require inspecting the actual file, not just the extension. WMV video with WMA/WMA Lossless audio can need a different fix than WMV video itself.
- Font/codepage failures show boxes or mojibake and should not be conflated with playback or rendering issues.

## Runtime Profile Lessons

- Engine brand is not a runtime profile. Hamidashi and Amakano3 are both Artemis/iarsys D3D11 but need different media stacks.
- Local signatures outrank VNDB. VNDB can match the wrong game, wrong release, port, or patch.
- Shared bottles must be scoped by runtime compatibility, not by broad engine family.
- Every profile fix should ask whether it pollutes other games using that profile.
- Dependencies that are essential to a Gala profile should be hosted in Gala GitHub release assets.
- Never patch original game directories. Use Gala-owned caches, overlays, symlinks, or generated files.
- Treat first-run media cache generation as a possible warmup artifact if a second launch is synchronized.
- Runtime migrations should be repeatable and skippable. If scanning is expensive, persist a marker and rerun only when rules or selected executable change.

## Known Cases

- Hamidashi Creative Totsu: OP/WMV clips used the DirectShow/LAV path. The effective fix was not just "install LAV"; Gala had to remove bad `.dat` extension mappings and route ASF content signatures to LAV Splitter Source without overriding `d3d11`/`dxgi`.
- Amakano3 / 甜蜜女友3: the main black-screen issue was D3D11 rendering, fixed by the DXMT profile. The later OP/movie issue was Media Foundation WMV/WMA behavior, fixed by the `artemis-mf-d3d11` profile, Gala MF Runtime, GStreamer environment, and per-game WMV audio overlay.
- WHITE ALBUM2: Leaf/AQUAPLUS needed stricter DirectShow routing than `common`, including builtin DirectShow, disabled Wine WMA/WMV codecs, and LAV RGB output.
- Family Project: path and registry expectations were part of the runtime, not just media playback. It needs its own `do-kizunar` profile and `G:\` mapping.

## Anti-Patterns

- Do not start by swapping Wine variants, GPTK, Whisky, or D3DMetal without first classifying the failure.
- Do not assume all OP failures are LAV problems.
- Do not assume all Artemis/iarsys games can share one bottle.
- Do not let a VNDB engine label force a special profile without local evidence.
- Do not run many environment changes at once; it makes the successful variable impossible to identify.
- Do not turn one game's workaround into a shared-profile override unless other games in that profile are known to tolerate it.
