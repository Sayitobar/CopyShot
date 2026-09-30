# MFR 1.5 (Pix2Text) Setup & Specifications

The LaTeX capture mode runs the [Pix2Text MFR 1.5](https://huggingface.co/breezedeus/pix2text-mfr-1.5) encoder and decoder locally via ONNX Runtime (`OnnxRuntimeBindings`). It recognizes a cropped mathematical formula.

## Model Specifications

- **Model**: `breezedeus/pix2text-mfr-1.5` (DeiT ViT encoder + autoregressive transformer decoder).
- **Input**: Raw cropped capture rendered onto a $384 \times 384$ white canvas (`NSColor.white`), normalized channel-first to $[-1.0, 1.0]$.
- **Inference**: Greedy autoregressive decoding (argmax, zero sampling temperature) up to **1,024 tokens**.
- **Output Format**: Raw LaTeX math string (e.g., `x^{2} + y^{2} = z^{2}`), trimmed of outer whitespace and copied directly to the clipboard.
- **Scope**: Designed for tightly-cropped single formulas (display or inline). No layout/formula detector (MFD) is bundled; mixed paragraphs with text and formulas are not segmented.

## POC Setup (Current)

Run `sh scripts/install-mfr-1.5.sh` once on a machine with internet access. The script downloads `encoder_model.onnx` (~87.5 MB), `decoder_model.onnx` (~32 MB), and `tokenizer.json` (~113 KB) into:
`~/Library/Containers/com.sayitobar.CopyShot/Data/Library/Application Support/CopyShot/MFR-1.5/`

Sessions are initialized lazily on the first LaTeX capture and reused on a background serial queue. They unload after 60 seconds without LaTeX recognition, or on warning/critical memory pressure. Both eviction and inference use the same serial queue so an active inference completes before its model is released. Missing resources report an error in the HUD and leave the clipboard intact.

Decoder outputs and input tensors are drained through an autorelease pool per token. Greedy decoding scans the final vocabulary position directly in the tensor buffer, avoiding a copy of logits for every earlier position. DEBUG logs separate model loading from inference.

The local recognition benchmark on September 30, 2026 used a 17-token synthetic formula. Session creation took approximately 200–300 ms; reused inference took about 310–340 ms, versus approximately 530–710 ms with recreated sessions. These are diagnostic measurements on the development Mac, with the model files already in the OS cache, and are not latency guarantees for longer formulas or cold disks. Releasing services returned the benchmark process's physical footprint to about 74 MiB; retaining sessions reached about 150–175 MiB. The cache integration benchmark confirmed reloading after idle eviction and recorded approximately 77 MiB after eviction. This is whole-process footprint, not model-only allocation, and does not establish that a higher Activity Monitor figure is a leak.

Recreating sessions for each capture trades roughly the measured load cost for lower idle RAM. Loading when LaTeX is selected could overlap loading with the selection gesture, but offers less overlap when LaTeX is already the default and capture is triggered immediately. The current 60-second idle cache keeps repeated captures fast and releases the model when it is no longer being used. Actual recognition triggers reloading after eviction.

See [TESTING.md](TESTING.md) for the reproducible cold/reused session benchmark. ONNX Runtime also retains allocator resources for reuse; its [memory documentation](https://onnxruntime.ai/docs/performance/tune-performance/memory.html) describes allocator-sharing options. Tensor lifetime fixes alone do not remove retained session weights and workspaces.

---

## Target Implementation Plan (On-Demand Model Manager)

To keep CopyShot featherweight (~10 MB) while preserving 100% on-device privacy:

1. **Lightweight Distribution**: Do not bundle the ~120 MB model files inside the base release DMG.
2. **First-Use Prompt**: Selecting LaTeX mode when uninstalled prompts the user:
   > *"LaTeX recognition runs locally using the Pix2Text model (~120 MB). No images or data ever leave your Mac.*  
   > *[ Download Model ] [ Cancel ]"*
3. **Settings Management ("Models / LaTeX")**:
   - Status indicator (`Installed (~120 MB)` / `Not Installed`).
   - One-click `Download Model` and `Delete Model` buttons (allowing users to reclaim disk space).
4. **Air-Gapped / Offline Import**:
   - A `Locate / Import Model...` button allowing enterprise or air-gapped users to import the three model files locally without an internet connection.
