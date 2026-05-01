;;; vertico-posframe-preview.el --- Preview extension for vertico-posframe  -*- lexical-binding: t -*-

;; Copyright (C) 2026 Nobu

;; Author: Nobu <https://github.com/kn66>
;; Assisted-by: OpenAI Codex
;; Version: 0.1
;; Keywords: convenience, matching
;; URL: https://github.com/kn66/vertico-posframe-preview
;; Package-Requires: ((emacs "30.1") (posframe "1.4.0") (vertico "2.6") (vertico-posframe "0.9.2"))

;; This file is not part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Display a second posframe with preview content for the current
;; Vertico candidate shown by `vertico-posframe'.
;;
;; This package integrates with `vertico-posframe' and optionally with
;; Consult by advising a small set of internal functions.  It is tested
;; against the dependency versions declared in `Package-Requires'.

;;; Code:

(require 'posframe)
(require 'bookmark)
(require 'cl-lib)
(require 'subr-x)
(require 'vertico)
(require 'vertico-posframe)

(defgroup vertico-posframe-preview nil
  "Preview extension for vertico-posframe."
  :group 'vertico-posframe)

(defface vertico-posframe-preview-line
  '((t :inherit highlight))
  "Face used to highlight the current preview line."
  :group 'vertico-posframe-preview)

(defface vertico-posframe-preview-match
  '((t :inherit match))
  "Face used to highlight matches in preview content."
  :group 'vertico-posframe-preview)

(defcustom vertico-posframe-preview-function #'vertico-posframe-preview-default
  "Function used to render preview for current Vertico candidate.

The function is called with the current candidate string in the
minibuffer buffer.  It should return a string, a buffer whose
contents will be copied, or nil to hide the preview posframe."
  :type '(choice (const nil) function))

(defcustom vertico-posframe-preview-command-functions
  '((switch-to-buffer . vertico-posframe-preview-buffer)
    (switch-to-buffer-other-window . vertico-posframe-preview-buffer)
    (switch-to-buffer-other-frame . vertico-posframe-preview-buffer)
    (project-switch-to-buffer . vertico-posframe-preview-buffer)
    (bookmark-jump . vertico-posframe-preview-bookmark)
    (bookmark-jump-other-window . vertico-posframe-preview-bookmark)
    (bookmark-jump-other-frame . vertico-posframe-preview-bookmark))
  "Alist of commands and preview functions.

This is a fallback for commands which do not provide useful
completion metadata.  Prefer `vertico-posframe-preview-category-functions'
for normal configuration.

Each preview function is called with the current candidate string."
  :type '(alist :key-type symbol :value-type function))

(defcustom vertico-posframe-preview-category-functions
  '((file . vertico-posframe-preview-file)
    (project-file . vertico-posframe-preview-file)
    (buffer . vertico-posframe-preview-buffer)
    (project-buffer . vertico-posframe-preview-buffer)
    (consult-location . vertico-posframe-preview-location)
    (consult-grep . vertico-posframe-preview-grep)
    (imenu . vertico-posframe-preview-imenu)
    (xref-location . vertico-posframe-preview-xref)
    (consult-xref . vertico-posframe-preview-xref)
    (bookmark . vertico-posframe-preview-bookmark))
  "Alist of completion categories and preview functions.

Each preview function is called with the current candidate string.
This is the preferred place to configure previews."
  :type '(alist :key-type symbol :value-type function))

(defcustom vertico-posframe-preview-poshandler
  #'vertico-posframe-preview-poshandler-default
  "The posframe poshandler used by vertico-posframe preview."
  :type 'function)

(defcustom vertico-posframe-preview-width nil
  "The width of vertico-posframe preview."
  :type '(choice (const nil) number))

(defcustom vertico-posframe-preview-max-width nil
  "The max width of vertico-posframe preview.

When nil, the preview width is limited to 45 percent of the
selected frame width."
  :type '(choice (const nil) number))

(defcustom vertico-posframe-preview-height nil
  "The height of vertico-posframe preview."
  :type '(choice (const nil) number))

(defcustom vertico-posframe-preview-min-width nil
  "The min width of vertico-posframe preview."
  :type '(choice (const nil) number))

(defcustom vertico-posframe-preview-min-height nil
  "The min height of vertico-posframe preview."
  :type '(choice (const nil) number))

(defcustom vertico-posframe-preview-max-size 20000
  "Maximum number of characters copied into vertico-posframe preview."
  :type 'natnum)

(defcustom vertico-posframe-preview-directory-max-entries 200
  "Maximum number of directory entries shown in file previews.

Set this to nil to list all entries."
  :type '(choice (const nil) natnum))

(defcustom vertico-posframe-preview-location-context 5
  "Number of context lines shown around a location preview."
  :type 'natnum)

(defcustom vertico-posframe-preview-parameters nil
  "The frame parameters used by vertico-posframe preview."
  :type '(alist :key-type symbol :value-type sexp))

(defcustom vertico-posframe-preview-consult t
  "Non-nil means mirror Consult previews in vertico-posframe preview."
  :type 'boolean)

(defcustom vertico-posframe-preview-golden-ratio-size t
  "Non-nil means use fixed golden-ratio sizes while preview mode is enabled.

When enabled, the Vertico candidate posframe and the preview
posframe are sized from the Emacs frame containing
`vertico-posframe-last-window'.  The candidate posframe uses the
smaller part and the preview posframe uses the larger part."
  :type 'boolean)

(defcustom vertico-posframe-preview-golden-ratio-gap 2
  "Number of columns reserved between candidate and preview posframes."
  :type 'natnum)

(defcustom vertico-posframe-preview-golden-ratio-position t
  "Non-nil means place candidate and preview posframes side by side.

This is used only when `vertico-posframe-preview-golden-ratio-size'
is non-nil."
  :type 'boolean)

(defcustom vertico-posframe-preview-fill-fixed-height t
  "Non-nil means pad preview content to the fixed preview height.

This avoids a short preview, such as a one-line location header,
shrinking the preview posframe while golden-ratio sizing is used."
  :type 'boolean)

(defcustom vertico-posframe-preview-auto-count t
  "Non-nil means set `vertico-count' from the fixed posframe height.

The count is set buffer-locally in the minibuffer.  One line is
reserved for the minibuffer prompt, so a fixed height of N shows
N - 1 candidates."
  :type 'boolean)

(defcustom vertico-posframe-preview-auto-location-context t
  "Non-nil means expand location previews to fill the preview height.

When nil, location previews use
`vertico-posframe-preview-location-context' exactly."
  :type 'boolean)

(defcustom vertico-posframe-preview-io-timeout 0.3
  "Seconds to wait for filesystem I/O when generating a preview.

Used as a hard cap around `file-regular-p', `file-directory-p',
`directory-files', and `insert-file-contents' so that pathological
candidates (slow network shares, unresponsive automounts, etc.)
cannot freeze the UI.  Set to nil to disable the timeout."
  :type '(choice (const :tag "No timeout" nil) number))

(defcustom vertico-posframe-preview-binary-detect-bytes 512
  "Number of leading bytes inspected to decide if a file is binary.

When the inspected bytes contain a NUL byte, the file is treated
as binary and skipped by `vertico-posframe-preview-file'.  Set to
nil or 0 to disable the check."
  :type '(choice (const :tag "Disabled" nil) natnum))

(defvar vertico-posframe-preview--buffer " *vertico-posframe-preview*")
(defvar vertico-posframe-preview--consult-buffer nil)
(defvar vertico-posframe-preview--frame nil)
(defvar vertico-posframe-preview-mode nil)
(defvar-local vertico-posframe-preview--content nil)
(defvar-local vertico-posframe-preview--content-set nil)
(defvar-local vertico-posframe-preview--exiting nil)
(defvar-local vertico-posframe-preview--suspended nil)
(defvar vertico-posframe-preview--quit-commands
  '(abort-recursive-edit keyboard-quit minibuffer-keyboard-quit)
  "Commands which should immediately hide the preview frame.")

(declare-function consult-imenu--flatten "consult-imenu")
(declare-function consult--grep-position "consult")
(declare-function consult--with-preview-f "consult")
;; Posframe internal, used to align the preview frame with the candidate frame.
(defvar posframe--frame)

(defun vertico-posframe-preview--specified-color-p (color)
  "Return non-nil when COLOR is a concrete color string."
  (and (stringp color)
       (not (string-prefix-p "unspecified" color))
       (color-defined-p color)))

(defun vertico-posframe-preview--frame-color (attribute parameter fallback)
  "Return a concrete color for ATTRIBUTE, frame PARAMETER, or FALLBACK."
  (or (cl-loop for face in '(vertico-posframe default)
               for color = (face-attribute face attribute nil t)
               when (vertico-posframe-preview--specified-color-p color)
               return color)
      (let ((color (frame-parameter nil parameter)))
        (and (vertico-posframe-preview--specified-color-p color)
             color))
      fallback))

(defun vertico-posframe-preview--consult-imenu-flatten-filter (items)
  "Add preview location properties to Consult imenu ITEMS."
  (dolist (item items)
    (when (and (consp item) (stringp (car item)))
      (put-text-property 0 1 'vertico-posframe-preview-imenu (cdr item) (car item))))
  items)

(defun vertico-posframe-preview--consult-state (state)
  "Return a Consult STATE wrapper which mirrors previews in posframe."
  (lambda (action candidate)
    (prog1 (funcall state action candidate)
      (when vertico-posframe-preview-consult
        (pcase action
          ('preview
           (if-let* ((window (active-minibuffer-window))
                     (buffer (window-buffer window))
                     ((not (buffer-local-value 'vertico-posframe-preview--exiting
                                               buffer)))
                     ((not (buffer-local-value 'vertico-posframe-preview--suspended
                                               buffer)))
                     (preview-function
                      (buffer-local-value 'vertico-posframe-preview-function buffer))
                     (content (and candidate
                                   (let ((vertico-posframe-preview--consult-buffer
                                          (current-buffer)))
                                     (with-current-buffer buffer
                                       (funcall preview-function candidate))))))
               (vertico-posframe-preview--show-content buffer content)
             (posframe-hide vertico-posframe-preview--buffer)))
          ('exit
           ;; `consult--with-preview-f' calls the state with `exit' from its
           ;; unwind-protect cleanup, which runs *after* the recursive
           ;; minibuffer has been torn down.  At that point
           ;; `(active-minibuffer-window)' refers to the surrounding (e.g.
           ;; find-file) minibuffer, so flagging that buffer as exiting via
           ;; `vertico-posframe-preview--hide' would prevent its preview from
           ;; ever showing again.  Hide the posframe only; the per-minibuffer
           ;; `minibuffer-exit-hook' marks the actually-exiting buffer.
           (when (get-buffer vertico-posframe-preview--buffer)
             (posframe-hide vertico-posframe-preview--buffer))))))))

(defun vertico-posframe-preview--consult-with-preview-advice
    (function preview-key state transform candidate save-input body)
  "Wrap Consult preview STATE around FUNCTION."
  (funcall function
           preview-key
           (if state (vertico-posframe-preview--consult-state state) state)
           transform candidate save-input body))

;;;###autoload
(define-minor-mode vertico-posframe-preview-mode
  "Toggle vertico-posframe preview."
  :global t
  :group 'vertico-posframe-preview
  (if vertico-posframe-preview-mode
      (vertico-posframe-preview--enable)
    (vertico-posframe-preview--disable)))

(defun vertico-posframe-preview--enable ()
  "Enable vertico-posframe preview integration."
  (advice-remove #'vertico-posframe--show
                 #'vertico-posframe-preview--set-size-advice)
  (advice-remove #'vertico-posframe--show
                 #'vertico-posframe-preview--show-advice)
  (advice-add #'vertico-posframe--show
              :before
              #'vertico-posframe-preview--set-size-advice)
  (advice-add #'vertico-posframe--show
              :after
              #'vertico-posframe-preview--show-advice)
  (advice-remove #'vertico-posframe-cleanup
                 #'vertico-posframe-preview--cleanup-advice)
  (advice-add #'vertico-posframe-cleanup
              :after
              #'vertico-posframe-preview--cleanup-advice)
  (advice-remove #'vertico-posframe--minibuffer-exit-hook
                 #'vertico-posframe-preview--hide-advice)
  (advice-add #'vertico-posframe--minibuffer-exit-hook
              :before
              #'vertico-posframe-preview--hide-advice)
  (vertico-posframe-preview-refresh-integrations))

(defun vertico-posframe-preview--disable ()
  "Disable vertico-posframe preview integration."
  (advice-remove #'vertico-posframe--show
                 #'vertico-posframe-preview--set-size-advice)
  (advice-remove #'vertico-posframe--show
                 #'vertico-posframe-preview--show-advice)
  (advice-remove #'vertico-posframe-cleanup
                 #'vertico-posframe-preview--cleanup-advice)
  (advice-remove #'vertico-posframe--minibuffer-exit-hook
                 #'vertico-posframe-preview--hide-advice)
  (vertico-posframe-preview--disable-consult-imenu)
  (vertico-posframe-preview--disable-consult)
  (vertico-posframe-preview-cleanup))

(defun vertico-posframe-preview--enable-consult-imenu ()
  "Enable Consult imenu integration."
  (advice-remove #'consult-imenu--flatten
                 #'vertico-posframe-preview--consult-imenu-flatten-filter)
  (advice-add #'consult-imenu--flatten
              :filter-return
              #'vertico-posframe-preview--consult-imenu-flatten-filter))

(defun vertico-posframe-preview--disable-consult-imenu ()
  "Disable Consult imenu integration."
  (when (fboundp 'consult-imenu--flatten)
    (advice-remove #'consult-imenu--flatten
                   #'vertico-posframe-preview--consult-imenu-flatten-filter)))

(defun vertico-posframe-preview--enable-consult ()
  "Enable Consult preview integration."
  (advice-remove #'consult--with-preview-f
                 #'vertico-posframe-preview--consult-with-preview-advice)
  (advice-add #'consult--with-preview-f
              :around
              #'vertico-posframe-preview--consult-with-preview-advice))

(defun vertico-posframe-preview--disable-consult ()
  "Disable Consult preview integration."
  (when (fboundp 'consult--with-preview-f)
    (advice-remove #'consult--with-preview-f
                   #'vertico-posframe-preview--consult-with-preview-advice)))

;;;###autoload
(defun vertico-posframe-preview-refresh-integrations ()
  "Enable optional integrations for already-loaded packages."
  (interactive)
  (when (and vertico-posframe-preview-mode
             (featurep 'consult-imenu))
    (vertico-posframe-preview--enable-consult-imenu))
  (when (and vertico-posframe-preview-mode
             (featurep 'consult))
    (vertico-posframe-preview--enable-consult)))

(cl-defmethod vertico--setup
  :after (&context ((vertico-posframe-mode-workable-p) (eql t)))
  "Setup vertico-posframe preview cleanup."
  (when vertico-posframe-preview-mode
    (setq-local vertico-posframe-preview--exiting nil)
    (setq-local vertico-posframe-preview--suspended nil)
    (vertico-posframe-preview--apply-layout (current-buffer))
    (add-hook 'pre-command-hook
              #'vertico-posframe-preview--pre-command-hook
              nil 'local)
    (add-hook 'minibuffer-exit-hook
              #'vertico-posframe-preview--minibuffer-exit-hook
              nil 'local)))

(defun vertico-posframe-preview--hide (&optional buffer)
  "Hide the vertico-posframe preview frame.
When BUFFER is non-nil, mark its preview as exiting before hiding.

This only hides the posframe so it can be reused by an outer
recursive minibuffer.  Use `vertico-posframe-preview-cleanup' to
fully delete the frame and buffer."
  (when buffer
    (with-current-buffer buffer
      (setq-local vertico-posframe-preview--exiting t)))
  (when (get-buffer vertico-posframe-preview--buffer)
    (posframe-hide vertico-posframe-preview--buffer)))

(defun vertico-posframe-preview--delete-frame ()
  "Delete the preview posframe and its buffer."
  (when (frame-live-p vertico-posframe-preview--frame)
    (let ((delete-frame-functions nil))
      (delete-frame vertico-posframe-preview--frame)))
  (setq vertico-posframe-preview--frame nil)
  (posframe-delete-frame vertico-posframe-preview--buffer))

(defun vertico-posframe-preview--candidate-posframe-buffer ()
  "Return the buffer used by `vertico-posframe' for candidates, if any."
  (and (boundp 'vertico-posframe--buffer)
       vertico-posframe--buffer
       (buffer-live-p vertico-posframe--buffer)
       vertico-posframe--buffer))

(defun vertico-posframe-preview--ensure-candidate-hidden ()
  "Defensively hide the `vertico-posframe' candidate posframe.

Used as a belt-and-suspenders cleanup so that frame state from a
recursive minibuffer (for example `consult-dir' invoked from
`find-file') cannot outlive its exit when our advice ordering
interacts unexpectedly with
`vertico-posframe--minibuffer-exit-hook'."
  (when-let* ((buffer (vertico-posframe-preview--candidate-posframe-buffer)))
    (ignore-errors (posframe-hide buffer))))

(defun vertico-posframe-preview--hide-advice (&rest _)
  "Hide preview frame when vertico-posframe hides its own frame.
Also defensively hides the candidate posframe.

When a recursive minibuffer (e.g. `consult-dir' invoked from
`find-file') exits, also delete the preview child frame outright.
While inner was active the preview frame was created as a child
of an outer posframe child frame; reusing that frame for the
surviving outer minibuffer leaves the preview parented to the
wrong frame and positioned in the wrong coordinate system, which
manifests as the preview never reappearing for the outer
command.  Forcing a fresh frame on the next show fixes that."
  (ignore-errors
    (vertico-posframe-preview--hide (and (minibufferp)
                                         (current-buffer))))
  (vertico-posframe-preview--ensure-candidate-hidden)
  (when (> (minibuffer-depth) 1)
    (ignore-errors (vertico-posframe-preview--delete-frame))))

(defun vertico-posframe-preview--pre-command-hook ()
  "Hide the preview frame before commands which quit the minibuffer."
  (when (memq this-command vertico-posframe-preview--quit-commands)
    (vertico-posframe-preview--hide (current-buffer))))

(defun vertico-posframe-preview--minibuffer-exit-hook ()
  "Hide the vertico-posframe preview frame.
Also defensively hides the candidate posframe in case recursive
minibuffer interaction left it visible."
  (ignore-errors
    (vertico-posframe-preview--hide (current-buffer)))
  (vertico-posframe-preview--ensure-candidate-hidden))

(defun vertico-posframe-preview--root-frame (frame)
  "Walk FRAME up to the topmost non-child Emacs frame.

Recursive minibuffers can leave `vertico-posframe-last-window'
pointing at a window inside a posframe child frame.  Sizing the
candidate/preview posframes from that small child frame produces
a near-invisible inner posframe.  Resolving to the root frame
keeps sizes anchored to the user-visible Emacs frame."
  (let ((current frame)
        (seen nil))
    (while (and (frame-live-p current)
                (frame-parent current)
                (not (memq current seen)))
      (push current seen)
      (setq current (frame-parent current)))
    current))

(defun vertico-posframe-preview--golden-ratio-size ()
  "Return fixed candidate and preview sizes based on the Emacs frame."
  (when vertico-posframe-preview-golden-ratio-size
    (let* ((window (vertico-posframe-last-window))
           (raw-frame (if (window-live-p window)
                          (window-frame window)
                        (selected-frame)))
           (frame (vertico-posframe-preview--root-frame raw-frame))
           (width (max 20 (frame-width frame)))
           (height (max 1 (frame-height frame)))
           (phi (/ (+ 1 (sqrt 5.0)) 2))
           (gap (min vertico-posframe-preview-golden-ratio-gap
                     (max 0 (- width 20))))
           (available (max 20 (- width gap)))
           (preview-width (max 1 (round (/ available phi))))
           (candidate-width (max 1 (- available preview-width)))
           (posframe-height (max 1 (round (/ height phi)))))
      (list :candidate-width candidate-width
            :preview-width preview-width
            :full-width available
            :height posframe-height))))

(defun vertico-posframe-preview--location-context-lines ()
  "Return cons of before and after context lines for a location preview."
  (let ((height (and vertico-posframe-preview-auto-location-context
                     (plist-get (vertico-posframe-preview--golden-ratio-size)
                                :height))))
    (if height
        ;; Two title lines are added by `vertico-posframe-preview--position'.
        ;; Split the remaining visible lines so the target line is centered.
        (let* ((content-height (max 1 (- height 2)))
               (before (/ (1- content-height) 2)))
          (cons before (max 0 (- content-height before 1))))
      (let ((context vertico-posframe-preview-location-context))
        (cons context context)))))

(defun vertico-posframe-preview--preview-available-p ()
  "Return non-nil when the current completion can show a preview."
  (unless vertico-posframe-preview--suspended
    (let ((category (vertico-posframe-preview--completion-category)))
      (or (assoc category vertico-posframe-preview-category-functions)
          (and (eq category 'multi-category)
               vertico-posframe-preview-category-functions)
          (assq this-command vertico-posframe-preview-command-functions)
          minibuffer-completing-file-name))))

(defun vertico-posframe-preview--apply-layout (buffer &optional content)
  "Apply fixed preview layout variables to minibuffer BUFFER."
  (when-let* ((size (vertico-posframe-preview--golden-ratio-size)))
    (with-current-buffer buffer
      (let ((candidate-width (if (or content
                                     (vertico-posframe-preview--preview-available-p))
                                 (plist-get size :candidate-width)
                               (plist-get size :full-width))))
        (setq-local vertico-posframe-width candidate-width)
        (setq-local vertico-posframe-min-width candidate-width))
      (setq-local vertico-posframe-height
                  (plist-get size :height))
      (setq-local vertico-posframe-min-height
                  (plist-get size :height))
      (when vertico-posframe-preview-auto-count
        (setq-local vertico-count
                    (max 1 (1- (plist-get size :height)))))
      (when vertico-posframe-preview-golden-ratio-position
        (setq-local vertico-posframe-poshandler
                    #'vertico-posframe-preview-poshandler-candidate)))))

(defun vertico-posframe-preview--set-size-advice (buffer &rest _)
  "Set fixed Vertico posframe size for BUFFER before it is shown."
  ;; Invariant: if `vertico-posframe--show' is being called for BUFFER,
  ;; that buffer is being displayed and therefore cannot be in an
  ;; exiting state.  Clear any stale `--exiting' flag here so that
  ;; phantom state left behind by recursive minibuffer interactions
  ;; (e.g. consult-dir invoked from find-file) cannot suppress the
  ;; surviving outer buffer's preview indefinitely.
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when vertico-posframe-preview--exiting
        (setq-local vertico-posframe-preview--exiting nil))))
  (let ((content (vertico-posframe-preview--content buffer)))
    (with-current-buffer buffer
      (setq-local vertico-posframe-preview--content content)
      (setq-local vertico-posframe-preview--content-set t))
    (vertico-posframe-preview--apply-layout buffer content)))

(defun vertico-posframe-preview--golden-ratio-pixel-layout (info)
  "Return pixel layout for candidate and preview posframes using INFO."
  (let* ((parent-width (plist-get info :parent-frame-width))
         (parent-height (plist-get info :parent-frame-height))
         (font-width (max 1 (or (plist-get info :font-width) 1)))
         (font-height (max 1 (or (plist-get info :font-height) 1)))
         (gap (* font-width vertico-posframe-preview-golden-ratio-gap))
         (candidate-width (* font-width
                             (or (plist-get
                                  (vertico-posframe-preview--golden-ratio-size)
                                  :candidate-width)
                                 1)))
         (preview-width (* font-width
                           (or (plist-get
                                (vertico-posframe-preview--golden-ratio-size)
                                :preview-width)
                               1)))
         (height (plist-get info :posframe-height))
         (total-width (+ candidate-width gap preview-width))
         (x (max 0 (/ (- parent-width total-width) 2)))
         (y (max font-height
                 (/ (- parent-height height (* font-height 2)) 2))))
    (list :candidate-x x
          :preview-x (+ x candidate-width gap)
          :y y)))

(defun vertico-posframe-preview-poshandler-candidate (info)
  "Poshandler for the candidate posframe in golden-ratio preview layout."
  (let ((layout (vertico-posframe-preview--golden-ratio-pixel-layout info)))
    (cons (plist-get layout :candidate-x)
          (plist-get layout :y))))

(defun vertico-posframe-preview-poshandler-golden-ratio (info)
  "Poshandler for the preview posframe in golden-ratio preview layout."
  (let ((layout (vertico-posframe-preview--golden-ratio-pixel-layout info)))
    (cons (plist-get layout :preview-x)
          (plist-get layout :y))))

(defun vertico-posframe-preview--candidate-frame ()
  "Return the current Vertico candidate posframe."
  (and (buffer-live-p vertico-posframe--buffer)
       (buffer-local-value 'posframe--frame vertico-posframe--buffer)))

(defun vertico-posframe-preview--sync-frame-to-candidate ()
  "Align preview frame position to the candidate frame."
  (when (and vertico-posframe-preview-golden-ratio-size
             vertico-posframe-preview-golden-ratio-position
             (frame-live-p vertico-posframe-preview--frame))
    (when-let* ((candidate-frame (vertico-posframe-preview--candidate-frame))
                ((frame-live-p candidate-frame))
                (candidate-position (frame-position candidate-frame)))
      (let* ((gap (* (default-font-width)
                     vertico-posframe-preview-golden-ratio-gap)))
        (set-frame-position vertico-posframe-preview--frame
                            (+ (car candidate-position)
                               (frame-pixel-width candidate-frame)
                               gap)
                            (cdr candidate-position))))))

(defun vertico-posframe-preview--show-advice (buffer _window-point)
  "Display preview after `vertico-posframe--show' displays BUFFER."
  (unless (or (not (when-let* ((window (active-minibuffer-window)))
                     (eq buffer (window-buffer window))))
              (buffer-local-value 'vertico-posframe-preview--exiting buffer))
    (vertico-posframe-preview--show buffer)))

(defun vertico-posframe-preview--current-candidate ()
  "Return the current Vertico candidate string, or nil."
  (when (and (boundp 'vertico--index)
             (boundp 'vertico--total)
             (> vertico--total 0)
             (>= vertico--index 0))
    (ignore-errors
      (vertico--candidate))))

(defun vertico-posframe-preview--content (buffer)
  "Return preview content for the current candidate in BUFFER."
  (when-let* (((not (buffer-local-value 'vertico-posframe-preview--exiting buffer)))
              ((not (buffer-local-value 'vertico-posframe-preview--suspended buffer)))
              (function (buffer-local-value 'vertico-posframe-preview-function buffer))
              (candidate (with-current-buffer buffer
                           (vertico-posframe-preview--current-candidate))))
    (condition-case err
        (with-current-buffer buffer
          (funcall function candidate))
      (error
       (message "vertico-posframe-preview: %s" (error-message-string err))
       nil))))

(defun vertico-posframe-preview--completion-category ()
  "Return the current completion category, or nil."
  (ignore-errors
    (vertico--metadata-get 'category)))

(defun vertico-posframe-preview--target (candidate)
  "Return preview category and target for CANDIDATE."
  (let ((category (vertico-posframe-preview--completion-category)))
    (if (eq category 'multi-category)
        (if-let* ((multi (get-text-property 0 'multi-category candidate)))
            (cons (car multi) (cdr multi))
          (cons category candidate))
      (cons category candidate))))

(defun vertico-posframe-preview-default (candidate)
  "Return preview content for CANDIDATE using built-in preview rules."
  (let* ((preview (vertico-posframe-preview--target candidate))
         (category (car preview))
         (target (cdr preview)))
    (or (when-let* ((function (cdr (assoc category
                                          vertico-posframe-preview-category-functions))))
          (funcall function target))
        (when-let* ((function (cdr (assq this-command
                                         vertico-posframe-preview-command-functions))))
          (funcall function target))
        (when minibuffer-completing-file-name
          (vertico-posframe-preview-file candidate)))))

(defmacro vertico-posframe-preview--with-io-timeout (&rest body)
  "Run BODY under `with-timeout' using `vertico-posframe-preview-io-timeout'.
Returns nil when the timeout fires.  When the option is nil, BODY
runs without a timeout."
  (declare (indent 0) (debug t))
  `(if vertico-posframe-preview-io-timeout
       (with-timeout (vertico-posframe-preview-io-timeout nil)
         ,@body)
     (progn ,@body)))

(defun vertico-posframe-preview--binary-file-p (file)
  "Return non-nil when FILE looks binary based on a leading-byte scan.

Reads up to `vertico-posframe-preview-binary-detect-bytes' bytes
and treats the file as binary if a NUL byte is found.  Returns
nil when detection is disabled or the file is empty."
  (when-let* ((bytes vertico-posframe-preview-binary-detect-bytes)
              ((natnump bytes))
              ((> bytes 0)))
    (with-temp-buffer
      (set-buffer-multibyte nil)
      (let ((coding-system-for-read 'binary))
        (insert-file-contents-literally file nil 0 bytes))
      (goto-char (point-min))
      (search-forward "\0" nil t))))

(defun vertico-posframe-preview--directory-entries (directory)
  "Return a bounded list of preview entries for DIRECTORY."
  (let* ((limit vertico-posframe-preview-directory-max-entries)
         (entries (directory-files directory
                                   nil
                                   directory-files-no-dot-files-regexp
                                   nil
                                   (and limit (1+ limit)))))
    (if (and limit (> (length entries) limit))
        (append (butlast entries) '("..."))
      entries)))

(defun vertico-posframe-preview-file (candidate)
  "Return file preview content for CANDIDATE.

Remote (TRAMP) paths are skipped to avoid blocking the UI on
network I/O when previewing candidates from sources such as
`consult-dir-tramp-ssh-hosts'.  Local I/O is bounded by
`vertico-posframe-preview-io-timeout'.  Files whose leading bytes
contain a NUL are treated as binary and skipped.

Applies `substitute-in-file-name' to CANDIDATE before resolving
so that path shadowing (e.g. \"/old/path//c:/new/path/\" produced
by `consult-dir-shadow-filenames'), `~/', and environment
variables are handled the same way `find-file' would."
  (let ((raw (ignore-errors
               (substitute-in-file-name
                (substring-no-properties candidate)))))
    (when (and raw
               (not (file-remote-p raw))
               (not (file-remote-p default-directory)))
      (let ((file (ignore-errors (expand-file-name raw))))
        (when (and file (not (file-remote-p file)))
          (vertico-posframe-preview--with-io-timeout
            (cond
             ((file-regular-p file)
              (unless (vertico-posframe-preview--binary-file-p file)
                (with-temp-buffer
                  (insert-file-contents file nil 0 vertico-posframe-preview-max-size)
                  (buffer-string))))
             ((file-directory-p file)
              (mapconcat #'identity
                         (vertico-posframe-preview--directory-entries file)
                         "\n")))))))))

(defun vertico-posframe-preview-buffer (candidate)
  "Return buffer preview content for CANDIDATE."
  (when-let* ((buffer (if (bufferp candidate)
                         candidate
                       (get-buffer (substring-no-properties candidate)))))
    buffer))

(defun vertico-posframe-preview--bookmark-summary (bookmark)
  "Return a textual summary for BOOKMARK."
  (let* ((name (car-safe bookmark))
         (location (ignore-errors (bookmark-location bookmark)))
         (annotation (ignore-errors (bookmark-get-annotation bookmark)))
         (lines (delq nil
                      (list (and name (format "Bookmark: %s" name))
                            (and location (format "Location: %s" location))
                            (and (stringp annotation)
                                 (not (string-empty-p annotation))
                                 annotation)))))
    (and lines (mapconcat #'identity lines "\n"))))

(defun vertico-posframe-preview--bookmark-file (file position)
  "Return preview content for bookmark FILE at POSITION."
  (when (and file
             (not (file-remote-p file))
             (not (file-remote-p default-directory)))
    (vertico-posframe-preview--with-io-timeout
      (cond
       ((file-directory-p file)
        (mapconcat #'identity
                   (vertico-posframe-preview--directory-entries file)
                   "\n"))
       ((file-regular-p file)
        (unless (vertico-posframe-preview--binary-file-p file)
          (if (integer-or-marker-p position)
              (let ((buffer (find-file-noselect file)))
                (with-current-buffer buffer
                  (vertico-posframe-preview--position
                   (if (markerp position)
                       position
                     (copy-marker (max (point-min)
                                       (min (point-max) position)))))))
            (with-temp-buffer
              (insert-file-contents file nil 0 vertico-posframe-preview-max-size)
              (buffer-string)))))))))

(defun vertico-posframe-preview-bookmark (candidate)
  "Return bookmark preview content for CANDIDATE."
  (when-let* ((bookmark (ignore-errors
                          (bookmark-get-bookmark
                           (substring-no-properties candidate)
                           t))))
    (let* ((file (ignore-errors (bookmark-get-filename bookmark)))
           (position (ignore-errors (bookmark-get-position bookmark))))
      (or (vertico-posframe-preview--bookmark-file file position)
          (vertico-posframe-preview--bookmark-summary bookmark)))))

(defun vertico-posframe-preview--position-marker (position)
  "Return a marker for POSITION."
  (cond
   ((markerp position) position)
   ((integerp position)
    (with-current-buffer (or vertico-posframe-preview--consult-buffer
                             (current-buffer))
      (copy-marker position)))
   ((and (consp position) (bufferp (car position)))
    (set-marker (make-marker) (cdr position) (car position)))))

(defun vertico-posframe-preview--add-face (string beg end face)
  "Add FACE to STRING between BEG and END, clipping to string bounds."
  (let ((beg (max 0 beg))
        (end (min (length string) end)))
    (when (< beg end)
      (add-face-text-property beg end face nil string))))

(defun vertico-posframe-preview--position-content (point title matches)
  "Return preview content around POINT in the current buffer.
TITLE is inserted above the preview when non-nil.
MATCHES is a list of match begin/end pairs relative to POINT."
  (goto-char point)
  (let* ((target-line-beg (line-beginning-position))
         (target-line-end (line-end-position))
         (line (line-number-at-pos point))
         (context (vertico-posframe-preview--location-context-lines))
         (before-context (car context))
         (after-context (cdr context)))
    (forward-line (- before-context))
    (let ((beg (line-beginning-position)))
      (goto-char point)
      (forward-line (1+ after-context))
      (let* ((end (line-beginning-position))
             (content (buffer-substring-no-properties beg end))
             (target-offset (- point beg)))
        (vertico-posframe-preview--add-face
         content
         (- target-line-beg beg)
         (- target-line-end beg)
         'vertico-posframe-preview-line)
        (dolist (match matches)
          (vertico-posframe-preview--add-face
           content
           (+ target-offset (car match))
           (+ target-offset (cdr match))
           'vertico-posframe-preview-match))
        (concat
         (or title (format "%s:%d\n\n" (buffer-name) line))
         content)))))

(defun vertico-posframe-preview--position (position &optional title matches)
  "Return preview content around POSITION.
TITLE is inserted above the preview when non-nil.
MATCHES is a list of match begin/end pairs relative to POSITION."
  (let* ((marker (vertico-posframe-preview--position-marker position))
         (buffer (and marker (marker-buffer marker)))
         (point (and marker (marker-position marker))))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (save-excursion
          (save-restriction
            (widen)
            (vertico-posframe-preview--position-content
             point title matches)))))))

(defun vertico-posframe-preview-location (candidate)
  "Return location preview content for CANDIDATE.

CANDIDATE is a Consult location: a propertized string carrying a
`consult-location' text property whose car is a marker, or a cons
cell `(MARKER . _)' for callers that pass the raw location."
  (cond
   ((and (stringp candidate)
         (get-text-property 0 'consult-location candidate))
    (vertico-posframe-preview--position
     (car (get-text-property 0 'consult-location candidate))))
   ((consp candidate)
    (vertico-posframe-preview--position (car candidate)))
   ((or (markerp candidate) (integerp candidate))
    (vertico-posframe-preview--position candidate))))

(defun vertico-posframe-preview--find-file-noselect-local (file)
  "Open FILE with `find-file-noselect' unless it is remote.
Returns nil for remote paths so callers can skip the preview
without blocking the UI on TRAMP I/O."
  (unless (file-remote-p file)
    (find-file-noselect file)))

(defun vertico-posframe-preview-grep (candidate)
  "Return grep location preview content for CANDIDATE.

Skipped when the surrounding `default-directory' is remote, since
`consult--grep-position' would otherwise resolve the candidate
against a TRAMP path and block on network I/O."
  (when (and (stringp candidate)
             (fboundp 'consult--grep-position)
             (not (file-remote-p default-directory)))
    (when-let* ((position
                 (ignore-errors
                   (consult--grep-position
                    candidate
                    #'vertico-posframe-preview--find-file-noselect-local)))
                (marker (car-safe position)))
      (vertico-posframe-preview--position marker nil (cdr position)))))

(defun vertico-posframe-preview-imenu (candidate)
  "Return imenu preview content for CANDIDATE."
  (let* ((item (cond
                ((or (markerp candidate) (integerp candidate))
                 candidate)
                ((consp candidate)
                 candidate)
                ((stringp candidate)
                 (or (get-text-property 0 'vertico-posframe-preview-imenu candidate)
                     (get-text-property 0 'imenu-choice candidate)))))
         (position (cdr-safe item)))
    (vertico-posframe-preview--position (or position item))))

(defun vertico-posframe-preview--xref-location-remote-p (location)
  "Return non-nil when xref LOCATION points to a remote file.
Uses `xref-location-group', which is conventionally the file
path for file-backed locations.  This avoids realising the
location into a marker (which would open the file via TRAMP)."
  (when (and location (fboundp 'xref-location-group))
    (let ((group (ignore-errors (xref-location-group location))))
      (and (stringp group) (file-remote-p group)))))

(defun vertico-posframe-preview-xref (candidate)
  "Return xref preview content for CANDIDATE.

Remote xref locations are skipped to avoid blocking the UI on
TRAMP I/O when the marker is materialised."
  (when (and (fboundp 'xref-item-location)
             (fboundp 'xref-location-marker))
    (let* ((xref (or (and (stringp candidate)
                          (get-text-property 0 'consult-xref candidate))
                     (if (consp candidate) (cdr candidate) candidate)))
           (location (ignore-errors (xref-item-location xref))))
      (unless (vertico-posframe-preview--xref-location-remote-p location)
        (when-let* ((marker (and location
                                 (ignore-errors (xref-location-marker location)))))
          (vertico-posframe-preview--position marker))))))

(defun vertico-posframe-preview--insert-content (content max-size)
  "Insert CONTENT up to MAX-SIZE into current preview buffer."
  (erase-buffer)
  (cond
   ((stringp content)
    (insert (substring content 0 (min (length content) max-size))))
   ((bufferp content)
    (insert-buffer-substring content
                             (with-current-buffer content (point-min))
                             (with-current-buffer content
                               (min (point-max)
                                    (+ (point-min) max-size))))))
  (goto-char (point-min)))

(defun vertico-posframe-preview--fill-height (height)
  "Pad current buffer to HEIGHT lines."
  (when (and vertico-posframe-preview-fill-fixed-height
             (natnump height)
             (> height 0))
    (save-excursion
      (goto-char (point-max))
      (let ((missing (- height (line-number-at-pos (point-max)))))
        (when (> missing 0)
          (insert (make-string missing ?\n)))))))

(defun vertico-posframe-preview--show-content (buffer content)
  "Show preview CONTENT in a posframe for Vertico minibuffer BUFFER."
  (if (and content
           (not (buffer-local-value 'vertico-posframe-preview--exiting buffer)))
      (let* ((preview-buffer (get-buffer-create vertico-posframe-preview--buffer))
             (size (vertico-posframe-preview--golden-ratio-size))
             (preview-width (or (buffer-local-value 'vertico-posframe-preview-width buffer)
                                (plist-get size :preview-width)))
             (preview-height (or (buffer-local-value 'vertico-posframe-preview-height buffer)
                                 (plist-get size :height))))
        (with-current-buffer preview-buffer
          (let ((inhibit-read-only t))
            (setq-local cursor-type nil)
            (setq-local truncate-lines t)
            (setq-local mode-line-format nil)
            (vertico-posframe-preview--insert-content
             content
             (buffer-local-value 'vertico-posframe-preview-max-size buffer))
            (vertico-posframe-preview--fill-height preview-height)))
        (setq vertico-posframe-preview--frame
              (with-selected-window (vertico-posframe-last-window)
                (posframe-show
                 preview-buffer
                 :poshandler (if (and size
                                      vertico-posframe-preview-golden-ratio-position)
                                 #'vertico-posframe-preview-poshandler-golden-ratio
                               (buffer-local-value
                                'vertico-posframe-preview-poshandler buffer))
                 :font (buffer-local-value 'vertico-posframe-font buffer)
                 :background-color
                 (vertico-posframe-preview--frame-color
                  :background 'background-color "white")
                 :foreground-color
                 (vertico-posframe-preview--frame-color
                  :foreground 'foreground-color "black")
                 :border-width (buffer-local-value 'vertico-posframe-border-width buffer)
                 :border-color (vertico-posframe--get-border-color)
                 :override-parameters (buffer-local-value 'vertico-posframe-preview-parameters buffer)
                 :refposhandler (buffer-local-value 'vertico-posframe-refposhandler buffer)
                 :lines-truncate t
                 :width preview-width
                 :max-width (or (buffer-local-value 'vertico-posframe-preview-max-width buffer)
                                preview-width
                                (round (* (frame-width) 0.45)))
                 :height preview-height
                 :min-width (or (buffer-local-value 'vertico-posframe-preview-min-width buffer)
                                preview-width)
                 :min-height (or (buffer-local-value 'vertico-posframe-preview-min-height buffer)
                                 preview-height
                                 (max 1 vertico-count)))))
        (vertico-posframe-preview--sync-frame-to-candidate))
    (posframe-hide vertico-posframe-preview--buffer)))

(defun vertico-posframe-preview--refresh ()
  "Refresh Vertico display after preview visibility changes."
  (when (and (minibufferp)
             (fboundp 'vertico--exhibit))
    (setq-local vertico-posframe-preview--content nil)
    (setq-local vertico-posframe-preview--content-set nil)
    (vertico--exhibit)))

;;;###autoload
(defun vertico-posframe-preview-toggle ()
  "Toggle preview visibility for the active Vertico minibuffer.

When called outside an active minibuffer, toggle
`vertico-posframe-preview-mode' globally."
  (interactive)
  (if (and (minibufferp)
           vertico-posframe-preview-mode)
      (progn
        (setq-local vertico-posframe-preview--suspended
                    (not vertico-posframe-preview--suspended))
        (if vertico-posframe-preview--suspended
            (vertico-posframe-preview--hide (current-buffer))
          (setq-local vertico-posframe-preview--exiting nil))
        (vertico-posframe-preview--refresh)
        (message "vertico-posframe-preview %s"
                 (if vertico-posframe-preview--suspended
                     "hidden"
                   "shown")))
    (call-interactively #'vertico-posframe-preview-mode)))

;;;###autoload
(defun vertico-posframe-preview-diagnose ()
  "Print preview state for the active minibuffer to *Messages*.
Useful when the preview unexpectedly fails to appear: invoke this
via \\[execute-extended-command] from inside the minibuffer (or
right after returning from a recursive command) and check the
result in *Messages*."
  (interactive)
  (let* ((mb (active-minibuffer-window))
         (buf (and mb (window-buffer mb))))
    (message
     (concat
      "vertico-posframe-preview state:\n"
      (format "  active-minibuffer-window: %S\n" mb)
      (format "  buffer:                   %S (live=%S)\n"
              buf (and buf (buffer-live-p buf)))
      (format "  minibuffer-depth:         %S\n" (minibuffer-depth))
      (format "  preview-mode:             %S\n" vertico-posframe-preview-mode)
      (when (and buf (buffer-live-p buf))
        (with-current-buffer buf
          (format
           (concat "  --exiting:                %S\n"
                   "  --suspended:              %S\n"
                   "  --content-set:            %S\n"
                   "  preview-function:         %S\n"
                   "  vertico--total:           %S\n"
                   "  vertico--index:           %S\n"
                   "  default-directory:        %S\n")
           vertico-posframe-preview--exiting
           vertico-posframe-preview--suspended
           vertico-posframe-preview--content-set
           vertico-posframe-preview-function
           (and (boundp 'vertico--total) vertico--total)
           (and (boundp 'vertico--index) vertico--index)
           default-directory)))
      (format "  --frame:                  %S (live=%S, visible=%S)\n"
              vertico-posframe-preview--frame
              (and (frame-live-p vertico-posframe-preview--frame))
              (and (frame-live-p vertico-posframe-preview--frame)
                   (frame-visible-p vertico-posframe-preview--frame)))
      (format "  preview-buffer:           %S\n"
              (get-buffer vertico-posframe-preview--buffer))))))

(defun vertico-posframe-preview--show (buffer)
  "Show preview posframe for Vertico minibuffer BUFFER."
  (let ((content (if (buffer-local-value 'vertico-posframe-preview--content-set
                                         buffer)
                     (buffer-local-value 'vertico-posframe-preview--content
                                         buffer)
                   (vertico-posframe-preview--content buffer))))
    (with-current-buffer buffer
      (setq-local vertico-posframe-preview--content nil)
      (setq-local vertico-posframe-preview--content-set nil))
    (vertico-posframe-preview--show-content buffer content)))

(defun vertico-posframe-preview-poshandler-default (info)
  "The default poshandler used by vertico-posframe preview.
Argument INFO is the posframe information plist."
  (let* ((parent-width (plist-get info :parent-frame-width))
         (parent-height (plist-get info :parent-frame-height))
         (font-width (or (plist-get info :font-width) 0))
         (font-height (or (plist-get info :font-height) 0))
         (width (plist-get info :posframe-width))
         (height (plist-get info :posframe-height))
         (margin-x (* font-width 2))
         (margin-y font-height)
         (candidate-frame
          (and (buffer-live-p vertico-posframe--buffer)
               (buffer-local-value 'posframe--frame vertico-posframe--buffer)))
         (candidate-position
          (and (frame-live-p candidate-frame)
               (frame-position candidate-frame)))
         (candidate-right
          (and candidate-position
               (+ (car candidate-position)
                  (frame-pixel-width candidate-frame)
                  margin-x)))
         (candidate-top
          (and candidate-position
               (cdr candidate-position)))
         (x (if candidate-right
                (min candidate-right
                     (max 0 (- parent-width width margin-x)))
              (max 0 (- parent-width width margin-x))))
         (y (if candidate-top
                (min candidate-top
                     (max 0 (- parent-height height margin-y)))
              (max 0 (/ (- parent-height height) 2)))))
    (cons x y)))

;;;###autoload
(defun vertico-posframe-preview-cleanup ()
  "Remove frames and buffers used for vertico-posframe preview."
  (interactive)
  (vertico-posframe-preview--hide)
  (vertico-posframe-preview--delete-frame))

(defun vertico-posframe-preview--cleanup-advice (&rest _)
  "Clean up preview frames after `vertico-posframe-cleanup'."
  (vertico-posframe-preview-cleanup))

(provide 'vertico-posframe-preview)
;;; vertico-posframe-preview.el ends here
