# vertico-posframe-preview

`vertico-posframe-preview` displays a second posframe with preview content for
the current Vertico candidate shown by `vertico-posframe`.

## Requirements

- Emacs 30.1 or later
- posframe 1.4.0 or later
- vertico 2.6 or later
- vertico-posframe 0.9.2 or later

Consult integration is optional.  When Consult is loaded, the package mirrors
Consult previews in the preview posframe for supported commands.

## Usage

Put the package on `load-path`, then enable both Vertico posframe and the
preview mode:

```elisp
(require 'vertico-posframe-preview)

(vertico-mode 1)
(vertico-posframe-mode 1)
(vertico-posframe-preview-mode 1)
```

Enable `vertico-posframe-preview-mode` after Consult has loaded if you want
Consult preview mirroring.  If Consult is loaded later, call:

```elisp
(vertico-posframe-preview-refresh-integrations)
```

The default preview function supports common file, buffer, location, grep,
imenu, and xref candidates.  Customize
`vertico-posframe-preview-category-functions` or
`vertico-posframe-preview-command-functions` to add command-specific previews.

## Compatibility Notes

This package intentionally advises private APIs from `vertico-posframe` and
Consult in order to place and synchronize the preview frame:

- `vertico-posframe--show`
- `vertico-posframe--minibuffer-exit-hook`
- `vertico-posframe-cleanup`
- `consult--with-preview-f`
- `consult-imenu--flatten`

Those functions are not stable public APIs.  If a dependency changes one of
these internals, this package may need an update even when byte compilation
still succeeds.  The dependency versions in the package header are the tested
baseline.

## Tests

Run the unit tests with:

```sh
emacs --batch -Q \
  -L /path/to/posframe \
  -L /path/to/vertico \
  -L /path/to/vertico-posframe \
  -L . \
  -l test/vertico-posframe-preview-test.el \
  -f ert-run-tests-batch-and-exit
```

The tests cover non-graphical preview helpers.  Posframe placement should still
be checked manually in a graphical Emacs session.
