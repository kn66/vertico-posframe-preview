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

(provide 'vertico-posframe-preview-test)
;;; vertico-posframe-preview-test.el ends here
