# Emacs Copilot

https://github.com/jart/emacs-copilot/assets/49262/1a79d4e4-9622-452e-9944-950c6f21d67f

Emacs Copilot provides AI-powered code completion using local LLMs. This fork
uses Ollama with Fill-in-the-Middle (FIM) prompting for intelligent completions
that understand both the code before and after your cursor.

## Features

- **FIM prompting**: Uses `<|fim_prefix|>...<|fim_suffix|>...<|fim_middle|>` tokens for context-aware completion
- **Smart context**: Includes imports (first 15 lines) and surrounding code
- **Tree-sitter integration**: Extracts enclosing function for better context (Emacs 29+)
- **Language agnostic**: Works with any programming language
- **Simple setup**: Just Ollama, curl, and jq

## Requirements

- [Ollama](https://ollama.ai) running locally
- A FIM-capable model (qwen2.5-coder recommended)
- `curl` and `jq` in PATH
- Emacs 29+ (for tree-sitter support, optional)

## Quick Start

1. Install Ollama and pull a model:
   ```sh
   ollama pull qwen2.5-coder:1.5b
   ```

2. Copy `copilot.el` to your Emacs load path and add to your config:
   ```elisp
   (require 'copilot)
   ```

3. Open a source file, write some code, and press `C-c C-k`:
   ```python
   def fibonacci(n):
       # cursor here, press C-c C-k
   ```

## Configuration

```elisp
;; Model selection (default: qwen2.5-coder:1.5b)
(setq copilot-model "qwen2.5-coder:7b")  ; larger model for better results

;; Ollama endpoint (default: localhost)
(setq copilot-url "http://localhost:11434/api/generate")

;; Context window sizes
(setq copilot-import-lines 15)   ; lines from file start
(setq copilot-prefix-lines 30)   ; lines before cursor
(setq copilot-suffix-lines 20)   ; lines after cursor
```

## Recommended Models

| Model | Size | Best For |
|-------|------|----------|
| qwen2.5-coder:1.5b | ~1GB | Fast completions, low memory |
| qwen2.5-coder:7b | ~4GB | Better quality, moderate hardware |
| qwen2.5-coder:32b | ~18GB | Best quality, high-end hardware |
| deepseek-coder:6.7b | ~4GB | Alternative with good FIM support |

## How It Works

When you invoke `copilot-complete` (C-c C-k):

1. **Context extraction**: Gathers imports, prefix (code before cursor), and suffix (code after cursor)
2. **Tree-sitter** (if available): Includes the enclosing function definition
3. **FIM prompt**: Constructs `<|fim_prefix|>...<|fim_suffix|>...<|fim_middle|>` prompt
4. **Ollama API**: Sends request via curl, receives completion
5. **Cleanup**: Removes any markdown artifacts or leaked tokens
6. **Insert**: Places the completion at cursor position

## Debugging

Use `M-x copilot-debug` to see what context would be sent to the model.

## Emacs Download Link

If you don't have Emacs installed:

- <https://cosmo.zip/pub/cosmos/bin/emacs>

## Credits

Original implementation by [Justine Tunney](https://github.com/jart) using llamafile.
Ollama + FIM rewrite by Vittorio Distefano.

## License

Apache 2.0
