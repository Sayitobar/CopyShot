# MFR 1.5 (Pix2Text) Setup & Specifications

The LaTeX capture mode runs the [Pix2Text MFR 1.5](https://huggingface.co/breezedeus/pix2text-mfr-1.5) encoder and decoder locally via ONNX Runtime (`OnnxRuntimeBindings`). It recognizes a cropped mathematical formula.

## Model Specifications

- **Model**: `breezedeus/pix2text-mfr-1.5` (DeiT ViT encoder + autoregressive transformer decoder).
- **Input**: Raw cropped capture rendered onto a $384 \times 384$ white canvas (`NSColor.white`), normalized channel-first to $[-1.0, 1.0]$.
- **Inference**: Greedy autoregressive decoding (argmax, zero sampling temperature) up to **1,024 tokens**.
- **Output Format**: Raw LaTeX math string (e.g., `x^{2} + y^{2} = z^{2}`), trimmed of outer whitespace and copied directly to the clipboard.
- **Scope**: Designed for tightly-cropped single formulas (display or inline). No layout/formula detector (MFD) is bundled; mixed paragraphs with text and formulas are not segmented.

## Download & Installation

Open **Settings → Capture → Mode Configuration → LaTeX → MFR Model → Download…**. The same window appears after a LaTeX screen selection if the model is missing, regardless of how that mode was selected (default mode, remembered mode, radial menu, or menu-bar capture).

The window shows progress bar, downloaded bytes and percentage, followed by a verification stage. Cancel or close the window to stop the download; failed downloads offer Retry. One window and one download are shared across requests. After successful installation, an awaiting capture resumes only if it is still current. When opened from settings, the window stays on its completed state until Done. Other capture modes remain available.

The app fetches three fixed files from Hugging Face at revision `1cef9f0bdcd6a4c63df7de1311fb0894593340cc`: `encoder_model.onnx` (87,510,770 bytes), `decoder_model.onnx` (32,026,253 bytes), and `tokenizer.json` (113,168 bytes). Downloads are staged inside Application Support, checked for exact size and SHA-256, and installed as a complete set. Interrupted or corrupt downloads never become an installed model.

The model card identifies Pix2Text MFR 1.5 as MIT-licensed; attribution and model information are available through the downloader's **Model information** link. This downloads model data only, never executable code or remote recognition services. Hugging Face and its download infrastructure receive normal GET-request metadata such as the user's IP address; screenshots and recognized formulas are never sent.

The existing outgoing-network entitlement covers downloads. No new Screen Recording or broader file access is requested. Models live in CopyShot's own Application Support directory:

`~/Library/Containers/com.sayitobar.CopyShot/Data/Library/Application Support/CopyShot/MFR-1.5/`

The installed-state button opens this directory in Finder. Bundle resources and the diagnostic `COPYSHOT_MFR_MODEL_DIR` override are also supported. A complete local model avoids the download prompt.

## Developer Setup & Runtime

The existing `sh scripts/install-mfr-1.5.sh` remains an alternative for development. End users do not need to run it.

Sessions are initialized lazily on the first LaTeX capture and reused on a background serial queue. By default they unload after 60 seconds without LaTeX recognition, or on warning/critical memory pressure. Both eviction and inference use the same serial queue so an active inference completes before its model is released. The menu bar shows an animated spinner during recognition and resets on completion. No recognition timeout is added. Download cancellation and recognition failures leave the clipboard intact.

Decoder outputs and input tensors are drained through an autorelease pool per token. Greedy decoding scans the final vocabulary position directly in the tensor buffer, avoiding a copy of logits for every earlier position. DEBUG logs separate model loading from inference.

The local recognition benchmark on September 30, 2026 used a 17-token synthetic formula. Session creation took approximately 200–300 ms; reused inference took about 310–340 ms, versus approximately 530–710 ms with recreated sessions. These are diagnostic measurements on the development Mac, with the model files already in the OS cache, and are not latency guarantees for longer formulas or cold disks. Releasing services returned the benchmark process's physical footprint to about 74 MiB; retaining sessions reached about 150–175 MiB. The cache integration benchmark confirmed reloading after idle eviction and recorded approximately 77 MiB after eviction. This is whole-process footprint, not model-only allocation, and does not establish that a higher Activity Monitor figure is a leak.

Recreating sessions for each capture trades roughly the measured load cost for lower idle RAM. The recognition prewarmer (`RecognitionPrewarmer.swift`) mitigates this by asynchronously prewarming the formula engine during overlay interaction whenever LaTeX is the active default mode or selected in the radial menu. The current 60-second idle cache keeps repeated captures fast and releases the model when it is no longer being used. Actual recognition triggers reloading after eviction.

See [TESTING.md](TESTING.md) for the reproducible cold/reused session benchmark. ONNX Runtime also retains allocator resources for reuse; its [memory documentation](https://onnxruntime.ai/docs/performance/tune-performance/memory.html) describes allocator-sharing options. Tensor lifetime fixes alone do not remove retained session weights and workspaces.
