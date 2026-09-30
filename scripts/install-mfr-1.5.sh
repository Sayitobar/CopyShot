#!/bin/sh
set -eu

# Install only Pix2Text MFR 1.5 inference resources for the current user.
model_dir="${HOME}/Library/Containers/com.sayitobar.CopyShot/Data/Library/Application Support/CopyShot/MFR-1.5"
model_base='https://huggingface.co/breezedeus/pix2text-mfr-1.5/resolve/1cef9f0'
mkdir -p "$model_dir"
for model_file in encoder_model.onnx decoder_model.onnx tokenizer.json; do
    curl --fail --location --retry 3 --output "$model_dir/$model_file.download" "$model_base/$model_file"
    mv "$model_dir/$model_file.download" "$model_dir/$model_file"
done
printf 'Installed Pix2Text MFR 1.5 resources in %s\n' "$model_dir"
