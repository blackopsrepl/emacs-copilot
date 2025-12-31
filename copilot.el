;;; copilot.el --- Smart Ollama code completion with FIM -*- lexical-binding: t; -*-

;; Copyright 2023 Justine Alexandra Roberts Tunney
;; Copyright 2024 Contributors

;; Author: Justine Tunney, pvd
;; License: Apache 2.0
;; Version: 0.2

;; Licensed under the Apache License, Version 2.0 (the "License");
;; you may not use this file except in compliance with the License.
;; You may obtain a copy of the License at
;;
;;     http://www.apache.org/licenses/LICENSE-2.0

;;; Commentary:
;;
;; Emacs Copilot provides AI-powered code completion using Ollama with
;; Fill-in-the-Middle (FIM) prompting. It uses smart context extraction
;; including imports and tree-sitter function detection.
;;
;; Requirements:
;;   - Ollama running locally (http://localhost:11434)
;;   - A FIM-capable model like qwen2.5-coder
;;   - curl and jq in PATH
;;
;; Usage:
;;   Place cursor where you want completion and run M-x copilot-complete
;;   or press C-c C-k
;;
;; Configuration:
;;   (setq copilot-model "qwen2.5-coder:1.5b")  ; or larger model
;;   (setq copilot-url "http://localhost:11434/api/generate")

;;; Code:

(defgroup copilot nil
  "Ollama-based code completion."
  :prefix "copilot-"
  :group 'editing)

(defcustom copilot-model "qwen2.5-coder:1.5b"
  "Ollama model to use for completion."
  :type 'string
  :group 'copilot)

(defcustom copilot-url "http://localhost:11434/api/generate"
  "Ollama API endpoint."
  :type 'string
  :group 'copilot)

(defcustom copilot-import-lines 15
  "Number of lines from start of file to include as imports."
  :type 'integer
  :group 'copilot)

(defcustom copilot-prefix-lines 30
  "Max lines before cursor to include."
  :type 'integer
  :group 'copilot)

(defcustom copilot-suffix-lines 20
  "Max lines after cursor to include."
  :type 'integer
  :group 'copilot)

;;; Context extraction

(defun copilot--get-imports ()
  "Get first `copilot-import-lines' lines of file."
  (save-excursion
    (goto-char (point-min))
    (forward-line copilot-import-lines)
    (buffer-substring-no-properties (point-min) (point))))

(defun copilot--get-prefix ()
  "Get up to `copilot-prefix-lines' lines before point."
  (save-excursion
    (let ((end (point)))
      (forward-line (- copilot-prefix-lines))
      (beginning-of-line)
      (buffer-substring-no-properties (point) end))))

(defun copilot--get-suffix ()
  "Get up to `copilot-suffix-lines' lines after point."
  (save-excursion
    (let ((start (point)))
      (forward-line copilot-suffix-lines)
      (end-of-line)
      (buffer-substring-no-properties start (point)))))

(defun copilot--get-enclosing-defun ()
  "Get enclosing function via tree-sitter if available."
  (when (and (fboundp 'treesit-defun-at-point)
             (ignore-errors (treesit-language-at (point))))
    (let ((node (ignore-errors (treesit-defun-at-point))))
      (when node
        (let ((text (treesit-node-text node)))
          (when (< (length text) 2000)  ; Don't include huge functions
            text))))))

;;; Context assembly

(defun copilot--build-context ()
  "Build smart context for completion.
Returns (PREFIX . SUFFIX) for FIM."
  (let* ((imports (copilot--get-imports))
         (prefix-raw (copilot--get-prefix))
         (suffix (copilot--get-suffix))
         (defun-text (copilot--get-enclosing-defun))
         (current-line (line-number-at-pos))
         prefix)
    ;; Build prefix: imports + context before cursor
    (if (<= current-line copilot-import-lines)
        ;; Near top: just use prefix (includes imports)
        (setq prefix prefix-raw)
      ;; Further down: imports + ... + prefix
      (if (and defun-text
               (not (string-match-p (regexp-quote defun-text) prefix-raw)))
          ;; Include enclosing function if not already in prefix
          (setq prefix (concat imports "\n...\n" defun-text "\n...\n"
                               (substring prefix-raw (min (length prefix-raw)
                                                          (* 5 80))))) ; last ~5 lines
        ;; Just imports + prefix
        (setq prefix (concat imports "\n...\n" prefix-raw))))
    (cons prefix suffix)))

;;; Ollama API

(defun copilot--call-ollama (prefix suffix)
  "Call Ollama with FIM prompt using temp file to avoid shell escaping issues."
  (let* ((tmpfile (make-temp-file "copilot" nil ".json"))
         (payload `((model . ,copilot-model)
                    (prompt . ,(format "<|fim_prefix|>%s<|fim_suffix|>%s<|fim_middle|>"
                                       prefix suffix))
                    (raw . t)
                    (stream . :json-false)
                    (options . ((temperature . 0)
                                (num_predict . 128)
                                (stop . ["<|fim_pad|>" "<|endoftext|>" "\n\n"]))))))
    (with-temp-file tmpfile
      (insert (json-encode payload)))
    (unwind-protect
        (string-trim
         (shell-command-to-string
          (format "curl -s -X POST %s -H 'Content-Type: application/json' -d @%s | jq -r '.response // empty'"
                  copilot-url tmpfile)))
      (delete-file tmpfile))))

;;; Cleanup

(defun copilot--clean-response (response)
  "Clean up model RESPONSE."
  (let ((cleaned response))
    ;; Convert literal \n \t \r to actual chars
    (setq cleaned (replace-regexp-in-string "\\\\n" "\n" cleaned nil t))
    (setq cleaned (replace-regexp-in-string "\\\\t" "\t" cleaned nil t))
    (setq cleaned (replace-regexp-in-string "\\\\r" "" cleaned nil t))
    ;; Remove markdown code blocks
    (setq cleaned (replace-regexp-in-string "^```[a-z]*\n?" "" cleaned))
    (setq cleaned (replace-regexp-in-string "\n?```$" "" cleaned))
    ;; Remove FIM tokens that might leak through
    (setq cleaned (replace-regexp-in-string "<|fim_[a-z]+|>" "" cleaned))
    (setq cleaned (replace-regexp-in-string "<|endoftext|>" "" cleaned))
    (string-trim-right cleaned)))

;;; Main entry point

;;;###autoload
(defun copilot-debug ()
  "Show what would be sent to Ollama."
  (interactive)
  (let* ((prefix (copilot--get-prefix))
         (suffix (copilot--get-suffix)))
    (with-current-buffer (get-buffer-create "*copilot-debug*")
      (erase-buffer)
      (insert "=== PREFIX ===\n" prefix "\n\n=== SUFFIX ===\n" suffix)
      (pop-to-buffer (current-buffer)))))

;;;###autoload
(defun copilot-complete ()
  "Complete code at point using Ollama with FIM."
  (interactive)
  (message "Copilot: generating...")
  (let* ((prefix (copilot--get-prefix))
         (suffix (copilot--get-suffix))
         (response (copilot--call-ollama prefix suffix)))
    (if (and response (not (string-empty-p response)))
        (progn
          (insert (copilot--clean-response response))
          (message "Copilot: done"))
      (message "Copilot: no completion"))))

;;; Keybinding

(global-set-key (kbd "C-c C-k") 'copilot-complete)

(provide 'copilot)
;;; copilot.el ends here
