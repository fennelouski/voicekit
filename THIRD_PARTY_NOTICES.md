# Third-party notices

## OpenWhispr

[OpenWhispr](https://github.com/OpenWhispr/openwhispr), revision
`2516e6e000b866a06099f69fd851b914069653d4`, informed the cleanup validation,
reasoning sanitization, clipboard ownership, prompt framing, and international
spacing changes. Selected validation and spacing behavior was adapted into Swift.

MIT License

Copyright (c) 2024 OpenWhispr Team

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Runtime dependencies

The resolved versions are recorded in `Package.resolved`. Distributed macOS bundles
include this notice and the `ThirdParty/` license files.

- FluidAudio 0.15.5 (`19600a485baa4998812e4654b70d2bab8f2c9949`):
  [Apache 2.0](ThirdParty/FluidAudio-LICENSE.txt). Its bundled VBx and fastcluster
  notices are included separately in `ThirdParty/`.
- Sparkle 2.9.4 (`b6496a74a087257ef5e6da1c5b29a447a60f5bd7`):
  [upstream license and bundled component notices](ThirdParty/Sparkle-LICENSE.txt).

Apple system frameworks and downloaded Apple assets remain governed by Apple's
platform terms. Downloaded diarization models have their own [model-card attribution](ThirdParty/Diarization-MODEL-NOTICE.md);
a library license does not establish a model's license. See
[verification and distribution notes](docs/reliability-verification.md) before
changing the model download path or distributing new model files.
