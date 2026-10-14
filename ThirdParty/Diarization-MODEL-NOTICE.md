# Downloaded speaker diarization assets

Dictate uses FluidAudio's legacy online diarizer with `pyannote_segmentation.mlmodelc`
and `wespeaker_v2.mlmodelc`, Core ML conversions by Fluid Inference. These weights
are downloaded at runtime and are not included in the app bundle.

The current [Fluid Inference model card](https://huggingface.co/FluidInference/speaker-diarization-coreml)
identifies the upstream sources as:

- [pyannote/segmentation-3.0](https://huggingface.co/pyannote/segmentation-3.0), MIT.
  Alexis Plaquet and Hervé Bredin, *Powerset multi-class cross entropy loss for
  neural speaker diarization*, INTERSPEECH 2023.
- [pyannote/wespeaker-voxceleb-resnet34-LM](https://huggingface.co/pyannote/wespeaker-voxceleb-resnet34-LM),
  [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/).
  WeSpeaker contributors; Hongji Wang and colleagues, *Wespeaker: A research and
  production oriented speaker embedding learning toolkit*, ICASSP 2023.

The conversions modify the original model representation for Apple's Core ML.
The [repository notice](https://huggingface.co/FluidInference/speaker-diarization-coreml/blob/main/NOTICE.md)
separates these legacy files from the Community-1 provenance confirmation.
Exact hosted weight revisions/hashes are not established by the Swift package lockfile.
Verify artifact-specific upstream notices before redistributing weights or replacing
this pipeline. No new model weights were downloaded for this inventory.
