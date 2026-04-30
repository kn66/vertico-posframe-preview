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

(provide 'vertico-posframe-preview-test)
;;; vertico-posframe-preview-test.el ends here
