;;; vertico-posframe-preview-test.el --- Tests for vertico-posframe-preview  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Nobu

;;; Code:

(require 'ert)
(require 'vertico-posframe-preview)

(ert-deftest vertico-posframe-preview-target-uses-multi-category-property ()
  (let ((candidate (propertize "display" 'multi-category '(file . "/tmp/example"))))
    (cl-letf (((symbol-function 'vertico-posframe-preview--completion-category)
               (lambda () 'multi-category)))
      (should (equal (vertico-posframe-preview--target candidate)
                     '(file . "/tmp/example"))))))

(ert-deftest vertico-posframe-preview-insert-content-truncates-strings ()
  (with-temp-buffer
    (vertico-posframe-preview--insert-content "abcdef" 3)
    (should (equal (buffer-string) "abc"))
    (should (= (point) (point-min)))))

(ert-deftest vertico-posframe-preview-insert-content-truncates-buffers ()
  (with-temp-buffer
    (let ((source (current-buffer)))
      (insert "abcdef")
      (with-temp-buffer
        (vertico-posframe-preview--insert-content source 4)
        (should (equal (buffer-string) "abcd"))
        (should (= (point) (point-min)))))))

(ert-deftest vertico-posframe-preview-directory-entries-respects-limit ()
  (let ((directory (make-temp-file "vertico-posframe-preview-" t)))
    (unwind-protect
        (let ((vertico-posframe-preview-directory-max-entries 2))
          (dolist (file '("a" "b" "c"))
            (with-temp-file (expand-file-name file directory)))
          (should (equal (vertico-posframe-preview--directory-entries
                          directory)
                         '("a" "b" "..."))))
      (delete-directory directory t))))

(ert-deftest vertico-posframe-preview-directory-entries-allows-unlimited ()
  (let ((directory (make-temp-file "vertico-posframe-preview-" t)))
    (unwind-protect
        (let ((vertico-posframe-preview-directory-max-entries nil))
          (dolist (file '("a" "b" "c"))
            (with-temp-file (expand-file-name file directory)))
          (should (equal (vertico-posframe-preview--directory-entries
                          directory)
                         '("a" "b" "c"))))
      (delete-directory directory t))))

(ert-deftest vertico-posframe-preview-position-marker-copies-integers ()
  (with-temp-buffer
    (insert "one\ntwo\nthree\n")
    (let ((marker (vertico-posframe-preview--position-marker 5)))
      (should (markerp marker))
      (should (eq (marker-buffer marker) (current-buffer)))
      (should (= (marker-position marker) 5)))))

(ert-deftest vertico-posframe-preview-position-content-includes-title-and-line ()
  (with-temp-buffer
    (insert "alpha\nbeta\ngamma\n")
    (let ((vertico-posframe-preview-location-context 1)
          (vertico-posframe-preview-auto-location-context nil))
      (let ((content (vertico-posframe-preview--position-content
                      8 "Title\n\n" '((0 . 4)))))
        (should (string-prefix-p "Title\n\n" content))
        (should (string-match-p "alpha\nbeta\ngamma" content))
        (should (get-text-property
                 (string-match "beta" content)
                 'face
                 content))))))

(ert-deftest vertico-posframe-preview-imenu-accepts-marker-candidates ()
  (with-temp-buffer
    (insert "alpha\nbeta\ngamma\n")
    (let ((marker (copy-marker 8))
          (vertico-posframe-preview-location-context 0)
          (vertico-posframe-preview-auto-location-context nil))
      (should (string-match-p "beta"
                              (vertico-posframe-preview-imenu marker))))))

(ert-deftest vertico-posframe-preview-frame-color-falls-back-from-unspecified ()
  (cl-letf (((symbol-function 'face-attribute)
             (lambda (face attribute &rest _)
               (pcase (list face attribute)
                 ('(vertico-posframe :background) "unspecified-bg")
                 ('(default :background) "#eeeeee"))))
            ((symbol-function 'frame-parameter)
             (lambda (&rest _) "#111111")))
    (should (equal (vertico-posframe-preview--frame-color
                    :background 'background-color "white")
                   "#eeeeee"))))

(ert-deftest vertico-posframe-preview-frame-color-uses-hard-fallback ()
  (cl-letf (((symbol-function 'face-attribute)
             (lambda (&rest _) "unspecified-bg"))
            ((symbol-function 'frame-parameter)
             (lambda (&rest _) nil)))
    (should (equal (vertico-posframe-preview--frame-color
                    :background 'background-color "white")
                   "white"))))

(ert-deftest vertico-posframe-preview-apply-layout-reserves-preview-width-for-category ()
  (with-temp-buffer
    (let ((vertico-posframe-preview-golden-ratio-size t)
          (vertico-posframe-preview-category-functions
           '((imenu . vertico-posframe-preview-imenu))))
      (cl-letf (((symbol-function 'vertico-posframe-preview--golden-ratio-size)
                 (lambda ()
                   '(:candidate-width 40 :preview-width 70 :full-width 112 :height 20)))
                ((symbol-function 'vertico-posframe-preview--completion-category)
                 (lambda () 'imenu)))
        (vertico-posframe-preview--apply-layout (current-buffer) nil)
        (should (= vertico-posframe-width 40))
        (should (= vertico-posframe-min-width 40))))))

(ert-deftest vertico-posframe-preview-preview-available-p-honors-suspended-state ()
  (with-temp-buffer
    (let ((vertico-posframe-preview--suspended t)
          (vertico-posframe-preview-category-functions
           '((imenu . vertico-posframe-preview-imenu))))
      (cl-letf (((symbol-function 'vertico-posframe-preview--completion-category)
                 (lambda () 'imenu)))
        (should-not (vertico-posframe-preview--preview-available-p))))))

(ert-deftest vertico-posframe-preview-content-honors-suspended-state ()
  (with-temp-buffer
    (let ((vertico-posframe-preview--suspended t)
          (vertico-posframe-preview--exiting nil)
          (vertico-posframe-preview-function (lambda (_) "preview")))
      (cl-letf (((symbol-function 'vertico-posframe-preview--current-candidate)
                 (lambda () "candidate")))
        (should-not (vertico-posframe-preview--content (current-buffer)))))))

(ert-deftest vertico-posframe-preview-advised-functions-exist ()
  "Smoke test: every advised private API must be defined.
If a dependency renames or removes one of these, this test fires
before users hit a runtime breakage."
  (dolist (sym '(vertico-posframe--show
                 vertico-posframe--minibuffer-exit-hook
                 vertico-posframe-cleanup))
    (should (fboundp sym)))
  ;; Consult APIs are optional but, when loaded, must still match.
  (when (featurep 'consult)
    (should (fboundp 'consult--with-preview-f)))
  (when (featurep 'consult-imenu)
    (should (fboundp 'consult-imenu--flatten))))

(ert-deftest vertico-posframe-preview-apply-layout-sets-vertico-count ()
  (with-temp-buffer
    (let ((vertico-posframe-preview-golden-ratio-size t)
          (vertico-posframe-preview-auto-count t)
          (vertico-posframe-preview-category-functions
           '((file . vertico-posframe-preview-file))))
      (cl-letf (((symbol-function 'vertico-posframe-preview--golden-ratio-size)
                 (lambda ()
                   '(:candidate-width 40 :preview-width 70 :full-width 112 :height 12)))
                ((symbol-function 'vertico-posframe-preview--completion-category)
                 (lambda () 'file)))
        (vertico-posframe-preview--apply-layout (current-buffer) nil)
        (should (= vertico-count 11))))))

(ert-deftest vertico-posframe-preview-apply-layout-skips-count-when-disabled ()
  (with-temp-buffer
    (let ((vertico-posframe-preview-golden-ratio-size t)
          (vertico-posframe-preview-auto-count nil)
          (vertico-count 7)
          (vertico-posframe-preview-category-functions
           '((file . vertico-posframe-preview-file))))
      (cl-letf (((symbol-function 'vertico-posframe-preview--golden-ratio-size)
                 (lambda ()
                   '(:candidate-width 40 :preview-width 70 :full-width 112 :height 12)))
                ((symbol-function 'vertico-posframe-preview--completion-category)
                 (lambda () 'file)))
        (vertico-posframe-preview--apply-layout (current-buffer) nil)
        (should (= vertico-count 7))))))

(ert-deftest vertico-posframe-preview-fill-height-pads-when-enabled ()
  (with-temp-buffer
    (let ((vertico-posframe-preview-fill-fixed-height t))
      (insert "line1\nline2\n")
      (vertico-posframe-preview--fill-height 5)
      (should (= (line-number-at-pos (point-max)) 5)))))

(ert-deftest vertico-posframe-preview-fill-height-noop-when-disabled ()
  (with-temp-buffer
    (let ((vertico-posframe-preview-fill-fixed-height nil))
      (insert "line1\nline2\n")
      (vertico-posframe-preview--fill-height 5)
      (should (equal (buffer-string) "line1\nline2\n")))))

(ert-deftest vertico-posframe-preview-fill-height-noop-when-already-tall ()
  (with-temp-buffer
    (let ((vertico-posframe-preview-fill-fixed-height t))
      (insert "a\nb\nc\nd\ne\n")
      (vertico-posframe-preview--fill-height 3)
      (should (equal (buffer-string) "a\nb\nc\nd\ne\n")))))

(ert-deftest vertico-posframe-preview-binary-file-p-detects-nul ()
  (let ((file (make-temp-file "vpp-binary-")))
    (unwind-protect
        (let ((vertico-posframe-preview-binary-detect-bytes 64))
          (with-temp-buffer
            (set-buffer-multibyte nil)
            (insert "abc\0def")
            (let ((coding-system-for-write 'binary))
              (write-region (point-min) (point-max) file)))
          (should (vertico-posframe-preview--binary-file-p file)))
      (delete-file file))))

(ert-deftest vertico-posframe-preview-binary-file-p-passes-text ()
  (let ((file (make-temp-file "vpp-text-")))
    (unwind-protect
        (let ((vertico-posframe-preview-binary-detect-bytes 64))
          (with-temp-buffer
            (insert "hello world\n")
            (write-region (point-min) (point-max) file))
          (should-not (vertico-posframe-preview--binary-file-p file)))
      (delete-file file))))

(ert-deftest vertico-posframe-preview-binary-file-p-respects-disabled ()
  (let ((file (make-temp-file "vpp-disabled-")))
    (unwind-protect
        (let ((vertico-posframe-preview-binary-detect-bytes nil))
          (with-temp-buffer
            (set-buffer-multibyte nil)
            (insert "abc\0def")
            (let ((coding-system-for-write 'binary))
              (write-region (point-min) (point-max) file)))
          (should-not (vertico-posframe-preview--binary-file-p file)))
      (delete-file file))))

(ert-deftest vertico-posframe-preview-file-resolves-shadow-paths ()
  "Regression: candidates from `consult-dir-shadow-filenames' arrive as
shadow paths like \"/old//abs/new/file\".  preview-file must resolve
them through `substitute-in-file-name' rather than treating the literal
shadow string as the path."
  (let* ((dir (make-temp-file "vpp-shadow-" t))
         (file (expand-file-name "real.txt" dir))
         (shadowed (concat "/non/existent/dir/" file)))
    (unwind-protect
        (let ((vertico-posframe-preview-binary-detect-bytes nil)
              (vertico-posframe-preview-max-size 4096)
              (vertico-posframe-preview-io-timeout nil))
          (with-temp-buffer
            (insert "shadow ok\n")
            (write-region (point-min) (point-max) file))
          (let ((preview (vertico-posframe-preview-file shadowed)))
            (should (stringp preview))
            (should (string-match-p "shadow ok" preview))))
      (when (file-exists-p file) (delete-file file))
      (when (file-directory-p dir) (delete-directory dir)))))

(ert-deftest vertico-posframe-preview-file-skips-binary ()
  (let ((file (make-temp-file "vpp-file-binary-")))
    (unwind-protect
        (let ((vertico-posframe-preview-binary-detect-bytes 64)
              (vertico-posframe-preview-max-size 64)
              (vertico-posframe-preview-io-timeout nil))
          (with-temp-buffer
            (set-buffer-multibyte nil)
            (insert "abc\0def")
            (let ((coding-system-for-write 'binary))
              (write-region (point-min) (point-max) file)))
          (should-not (vertico-posframe-preview-file file)))
      (delete-file file))))

(ert-deftest vertico-posframe-preview-bookmark-previews-file-position ()
  (let ((file (make-temp-file "vpp-bookmark-file-")))
    (unwind-protect
        (let ((bookmark-alist
               `(("file-bookmark"
                  (filename . ,file)
                  (position . 8)
                  (annotation . ""))))
              (vertico-posframe-preview-binary-detect-bytes nil)
              (vertico-posframe-preview-location-context 0)
              (vertico-posframe-preview-auto-location-context nil)
              (vertico-posframe-preview-io-timeout nil))
          (with-temp-buffer
            (insert "alpha\nbeta\ngamma\n")
            (write-region (point-min) (point-max) file))
          (should (string-match-p "beta"
                                  (vertico-posframe-preview-bookmark
                                   "file-bookmark"))))
      (when (file-exists-p file) (delete-file file)))))

(ert-deftest vertico-posframe-preview-bookmark-previews-directory ()
  (let ((directory (make-temp-file "vpp-bookmark-dir-" t)))
    (unwind-protect
        (let ((bookmark-alist
               `(("dir-bookmark"
                  (filename . ,directory)
                  (position . nil)
                  (annotation . ""))))
              (vertico-posframe-preview-directory-max-entries 2)
              (vertico-posframe-preview-io-timeout nil))
          (dolist (file '("a" "b" "c"))
            (with-temp-file (expand-file-name file directory)))
          (should (equal (vertico-posframe-preview-bookmark "dir-bookmark")
                         "a\nb\n...")))
      (delete-directory directory t))))

(ert-deftest vertico-posframe-preview-bookmark-falls-back-to-summary ()
  (let ((bookmark-alist
         '(("non-file-bookmark"
            (location . "custom location")
            (annotation . "bookmark note")))))
    (let ((preview (vertico-posframe-preview-bookmark "non-file-bookmark")))
      (should (string-match-p "non-file-bookmark" preview))
      (should (string-match-p "custom location" preview))
      (should (string-match-p "bookmark note" preview)))))

(ert-deftest vertico-posframe-preview-location-handles-cons-candidate ()
  (with-temp-buffer
    (insert "alpha\nbeta\ngamma\n")
    (let ((marker (copy-marker 8))
          (vertico-posframe-preview-location-context 0)
          (vertico-posframe-preview-auto-location-context nil))
      (should (string-match-p "beta"
                              (vertico-posframe-preview-location
                               (cons marker "ignored")))))))

(ert-deftest vertico-posframe-preview-location-uses-consult-location-property ()
  (with-temp-buffer
    (insert "alpha\nbeta\ngamma\n")
    (let* ((marker (copy-marker 8))
           (candidate (propertize "beta"
                                  'consult-location (cons marker 0)))
           (vertico-posframe-preview-location-context 0)
           (vertico-posframe-preview-auto-location-context nil))
      (should (string-match-p "beta"
                              (vertico-posframe-preview-location candidate))))))

(ert-deftest vertico-posframe-preview-location-handles-marker-candidate ()
  (with-temp-buffer
    (insert "alpha\nbeta\ngamma\n")
    (let ((marker (copy-marker 8))
          (vertico-posframe-preview-location-context 0)
          (vertico-posframe-preview-auto-location-context nil))
      (should (string-match-p "beta"
                              (vertico-posframe-preview-location marker))))))

(ert-deftest vertico-posframe-preview-location-handles-integer-candidate ()
  (with-temp-buffer
    (insert "alpha\nbeta\ngamma\n")
    (let ((vertico-posframe-preview-location-context 0)
          (vertico-posframe-preview-auto-location-context nil))
      (should (string-match-p "beta"
                              (vertico-posframe-preview-location 8))))))

(ert-deftest vertico-posframe-preview-location-returns-nil-for-bare-string ()
  (let ((vertico-posframe-preview-auto-location-context nil))
    (should-not (vertico-posframe-preview-location "no-property"))))

(ert-deftest vertico-posframe-preview-root-frame-returns-self-when-no-parent ()
  (let ((frame (selected-frame)))
    (cl-letf (((symbol-function 'frame-parent) (lambda (_) nil)))
      (should (eq (vertico-posframe-preview--root-frame frame) frame)))))

(ert-deftest vertico-posframe-preview-root-frame-walks-up-child-frames ()
  "Mocked frame chain: child -> middle -> root.
Ensures recursive-minibuffer paths end up sized from the root."
  (let* ((root 'root-frame)
         (middle 'middle-frame)
         (child 'child-frame)
         (parents `((,child . ,middle) (,middle . ,root) (,root . nil))))
    (cl-letf (((symbol-function 'frame-live-p) (lambda (_) t))
              ((symbol-function 'frame-parent)
               (lambda (f) (cdr (assq f parents)))))
      (should (eq (vertico-posframe-preview--root-frame child) root))
      (should (eq (vertico-posframe-preview--root-frame middle) root))
      (should (eq (vertico-posframe-preview--root-frame root) root)))))

(ert-deftest vertico-posframe-preview-consult-state-exit-does-not-mark-outer-buffer ()
  "Regression: after a recursive consult command exits, the surrounding
minibuffer's `--exiting' flag must remain nil.  Otherwise the outer
minibuffer's preview never reappears once the inner command returns."
  (with-temp-buffer
    (let ((outer (current-buffer))
          (vertico-posframe-preview-consult t)
          (inner-state-calls nil))
      (cl-letf (((symbol-function 'active-minibuffer-window)
                 (lambda () (selected-window)))
                ((symbol-function 'window-buffer)
                 (lambda (&rest _) outer))
                ((symbol-function 'get-buffer) (lambda (_) nil))
                ((symbol-function 'posframe-hide) (lambda (_) nil)))
        (let* ((inner-state (lambda (action _candidate)
                              (push action inner-state-calls)
                              nil))
               (wrapped (vertico-posframe-preview--consult-state inner-state)))
          (funcall wrapped 'exit nil)))
      (should (equal inner-state-calls '(exit)))
      (should-not (buffer-local-value 'vertico-posframe-preview--exiting outer)))))

(ert-deftest vertico-posframe-preview-root-frame-stops-on-cycle ()
  "Defensively stop if a frame chain ever loops back on itself."
  (let* ((a 'a) (b 'b)
         (parents `((,a . ,b) (,b . ,a))))
    (cl-letf (((symbol-function 'frame-live-p) (lambda (_) t))
              ((symbol-function 'frame-parent)
               (lambda (f) (cdr (assq f parents)))))
      ;; Should terminate without infinite looping.
      (should (memq (vertico-posframe-preview--root-frame a) '(a b))))))

(provide 'vertico-posframe-preview-test)
;;; vertico-posframe-preview-test.el ends here
