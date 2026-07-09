# consult-magit

Switch and manage [magit](https://magit.vc/) repositories with
[consult](https://github.com/minad/consult).

`consult-magit` gives you a single command to jump to a repository,
combining several sources:

- **Open Repository** — currently open `magit-status` buffers, with preview.
- **Repository History** — repositories you have previously opened with
  magit, so you can quickly re-open a local repo even after its buffer has
  been killed.
- **Known Repository** *(optional)* — repositories discovered from
  `magit-repository-directories`. Disabled by default; enable with
  `consult-magit-include-known-repositories`.

While in the minibuffer you can narrow to a single source with consult's
narrowing key (`b` open buffers, `h` history, `r` known repositories).

## Installation

The package depends on `consult` and `magit`.

With `use-package` and a local checkout:

```elisp
(use-package consult-magit
  :vc (:url "https://github.com/nhojb/consult-magit")
  :bind ("C-x C-g" . consult-magit))
```

Or for a local directory (matching a `git-package`/`:git` style):

```elisp
(use-package consult-magit
  :load-path "~/Projects/nhojb/emacs/consult-magit"
  :bind ("C-x C-g" . consult-magit))
```

## Persisting history across sessions

Repository history is stored in `consult-magit-repo-history`. To keep it
between Emacs sessions, add it to `savehist-additional-variables`:

```elisp
(with-eval-after-load 'savehist
  (add-to-list 'savehist-additional-variables 'consult-magit-repo-history))
```

## Customization

| Variable | Default | Description |
| --- | --- | --- |
| `consult-magit-history-length` | `50` | Maximum number of repositories kept in the history. |
| `consult-magit-include-known-repositories` | `nil` | When non-nil, offer repositories from `magit-repository-directories`. |
| `consult-magit-sources` | see source | The list of consult sources used by `consult-magit`. |

## How history is recorded

`consult-magit` adds `consult-magit--record-repo` to
`magit-status-mode-hook`; every time a `magit-status` buffer is created the
repository top-level is pushed to the front of `consult-magit-repo-history`.
