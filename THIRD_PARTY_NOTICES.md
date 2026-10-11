# Open model and runtime credits

Open Whisper uses free local inference software and models. No paid API is required.

- **FluidAudio**, FluidInference contributors. Apache License 2.0. [Source and license](https://github.com/FluidInference/FluidAudio).
- **Parakeet Ultra**, Moondream post-training of NVIDIA Parakeet TDT 0.6B v3; Core ML conversion by FluidInference. Model weights licensed under Creative Commons Attribution 4.0. [Original weights](https://huggingface.co/moondream/parakeet-ultra), [Core ML conversion](https://huggingface.co/FluidInference/parakeet-ultra-coreml), [NVIDIA base model and attribution](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), [CC BY 4.0 license](https://creativecommons.org/licenses/by/4.0/legalcode).
- **Whisper**, OpenAI and contributors. MIT License. [Source and license](https://github.com/openai/whisper). Optional full large-v3 and large-v3 Turbo models are converted by Argmax to Core ML. [Model repository](https://huggingface.co/argmaxinc/whisperkit-coreml).
- **WhisperKit / Argmax Open Source SDK**, Argmax, Inc. and contributors. MIT License. [Source and license](https://github.com/argmaxinc/argmax-oss-swift).

The downloaded Core ML representations and quantized weights are modified deployment formats of their upstream models. Parakeet Ultra additionally contains post-training changes from Moondream. Their authors do not endorse this application.

Dependency license texts are copied into the app's Resources/Licenses folder by the build script. Each model's upstream license and attribution continue to apply to its downloaded files.

Optional cleanup uses Apple's system-provided **Foundation Models** framework and on-device language model on eligible macOS 26+ systems. This is an Apple platform service, not an open-source model bundled or redistributed by this project. Apple Intelligence must be enabled and its model ready. Speech recognition, snippets and correction rules do not require it. [Apple Foundation Models documentation](https://developer.apple.com/documentation/foundationmodels).
