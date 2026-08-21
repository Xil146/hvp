# HDR and color pipeline design

Status: Proposed

## Goal

Preserve the content's intended brightness and color as accurately as the active Windows compositor, driver, GPU, and display chain allow, while requiring no per-file configuration.

## Inputs

- Normalized source metadata from libmpv video properties: transfer function, primaries, matrix, bit depth, mastering/peak data, dynamic metadata, and detectable Dolby Vision profile.
- Effective output facts from Windows/libmpv: monitor, desktop HDR state, swap-chain/output colorspace, bit depth, and reported display capabilities.
- The pinned libmpv/libplacebo version and actual negotiated renderer properties.

Container tags can be missing or wrong. The UI distinguishes `Unknown HDR` from confirmed HDR types and diagnostics retain the evidence used to classify the stream.

## Source classification

Apply the most specific supported evidence in this order:

1. Detectable Dolby Vision profile/metadata -> `Dolby Vision`.
2. SMPTE ST 2094-40 dynamic metadata with PQ/BT.2020 -> `HDR10+`.
3. PQ/BT.2020 with static mastering or content-light metadata -> `HDR10`.
4. HLG transfer function -> `HLG`.
5. Known SDR transfer/primaries -> `SDR`.
6. Conflicting or incomplete HDR evidence -> `Unknown HDR`.

Classification is descriptive; it does not promise a specific passthrough mode.

## Output decision table

| Source | Effective output | Intended behavior |
| --- | --- | --- |
| HDR | HDR-capable and HDR active | Use `gpu-next` target colorspace negotiation and HDR-capable swap-chain output where supported. |
| HDR | SDR or HDR unavailable | Let libplacebo tone-map and gamut-map to the effective SDR target. |
| SDR | HDR desktop | Preserve reference white and colors through the negotiated HDR output rather than stretching SDR to display peak. |
| SDR | SDR desktop | Standard SDR rendering with correct levels and primaries. |

Start with `target-colorspace-hint=auto` and libplacebo's automatic tone mapping. Do not force hard-coded display peak values unless an explicit display calibration setting is later approved. Capture the actual input/output colorspaces in diagnostics.

## Windows behavior

- HVP does not toggle the system HDR switch in V1.
- Re-evaluate output facts when the window changes monitor, Windows display mode changes, or the device is reconfigured.
- When HDR content is opened on a capable display with Windows HDR disabled, playback uses the SDR/tone-map path and may show a concise informational hint.
- Multi-monitor decisions follow the monitor containing the video window, not the primary display.

## Dynamic HDR and Dolby Vision

HDR10+ metadata may inform libplacebo's dynamic tone mapping, subject to the pinned engine and renderer. Dolby Vision reporting is best effort; unsupported profiles/layers may fall back to a compatible base layer. Never label fallback rendering as native Dolby Vision output without verified engine and hardware evidence.

## Validation matrix

Each release candidate records:

- source classification and mastering facts;
- Windows HDR state, display, GPU, driver, and connection;
- mpv VO/GPU API, swap-chain/input/output colorspaces, decoder/hardware context;
- expected versus observed black level, reference white, highlight detail, saturation, banding, and clipping;
- dropped frames and performance counters.

Use legally redistributable/generated patterns plus representative user-owned files. Compare against at least one trusted reference player/configuration, but document that visual comparison is not a colorimeter measurement.

## Acceptance criteria

- The status indicator never reports a more specific HDR format than the available evidence supports.
- All four source/output combinations produce usable brightness and color with no obvious clipping, washout, crushed blacks, or severe banding on the release matrix.
- Moving between SDR/HDR monitors triggers a correct re-evaluation without restarting HVP when supported; otherwise the limitation is explicit.
- Diagnostics make renderer decisions reviewable.
