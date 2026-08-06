;;; consult-magit.el --- Switch and manage magit buffers with consult -*- lexical-binding: t; -*-

;; Copyright (C) 2026 John Buckley

;; Author: John Buckley <nhoj.buckley@gmail.com>
;; Assisted-by: claude:claude-opus-4.8
;; URL: https://github.com/nhojb/consult-magit
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1") (consult "1.0") (magit "3.0"))
;; Keywords: convenience, vc, tools

;; This file is not part of GNU Emacs.

;;; Commentary:

;; `consult-magit' provides a single command to switch between magit
;; repositories using `consult'.  It combines several sources:
;;
;; - open `magit-status' buffers (with preview), and
;; - a history of repositories previously opened with magit, so you can
;;   quickly re-open a local repo even after its buffer has been killed.
;;
;; Optionally (see `consult-magit-include-known-repositories') it can also
;; offer repositories discovered from `magit-repository-directories'.
;;
;; The repository history is stored in `consult-magit-repo-history'.  To
;; persist it across sessions add that variable to
;; `savehist-additional-variables'.

;;; Code:

(require 'consult)
(require 'magit)
(require 'seq)

(defgroup consult-magit nil
  "Switch and manage magit buffers with consult."
  :group 'magit
  :group 'consult
  :prefix "consult-magit-")

(defcustom consult-magit-history-length 50
  "Maximum number of repositories to keep in `consult-magit-repo-history'."
  :type 'natnum)

(defcustom consult-magit-include-known-repositories nil
  "When non-nil, offer repositories from `magit-repository-directories'.
These are shown as an additional source in `consult-magit', for
repositories that are neither currently open nor already present in
`consult-magit-repo-history'."
  :type 'boolean)

(defvar consult-magit-repo-history nil
  "List of repository root directories previously opened with magit.
Ordered most-recently-opened first.  Add this variable to
`savehist-additional-variables' to persist it across sessions.")

(defvar consult-magit--history nil
  "Minibuffer input history for `consult-magit'.")

;;;; History tracking

;;;###autoload
(defun consult-magit-record-repo ()
  "Record the current repository in `consult-magit-repo-history'.
Intended for use in `magit-status-mode-hook', where
`default-directory' is the repository top-level."
  (when default-directory
    (let ((root (abbreviate-file-name default-directory)))
      (setq consult-magit-repo-history
            (cons root (delete root consult-magit-repo-history)))
      (when (> (length consult-magit-repo-history)
               consult-magit-history-length)
        (setcdr (nthcdr (1- consult-magit-history-length)
                        consult-magit-repo-history)
                nil)))))

;;;###autoload
(add-hook 'magit-status-mode-hook #'consult-magit-record-repo)

;;;; Sources

(defun consult-magit--open-repos ()
  "Return the roots of repositories with an open `magit-status' buffer."
  (delq nil
        (mapcar (lambda (buf)
                  (with-current-buffer buf
                    (when (derived-mode-p 'magit-status-mode)
                      (abbreviate-file-name default-directory))))
                (buffer-list))))

(defun consult-magit--open-action (dir)
  "Open a `magit-status' buffer for repository DIR."
  (let ((dir (expand-file-name dir)))
    (unless (file-directory-p dir)
      (user-error "Repository directory no longer exists: %s" dir))
    (magit-status-setup-buffer dir)))

(defun consult-magit--history-items ()
  "Return history repositories that are not currently open."
  (let ((open (consult-magit--open-repos)))
    (seq-remove (lambda (dir) (member dir open))
                consult-magit-repo-history)))

(defun consult-magit--known-items ()
  "Return known repositories that are neither open nor in the history."
  (when consult-magit-include-known-repositories
    (let ((seen (append (consult-magit--open-repos)
                        consult-magit-repo-history)))
      (seq-remove (lambda (dir) (member dir seen))
                  (mapcar #'abbreviate-file-name (magit-list-repos))))))

(defvar consult-magit--source-buffer
  `( :name     "Open Repository"
     :narrow   ?b
     :category buffer
     :face     consult-buffer
     :history  buffer-name-history
     :state    ,#'consult--buffer-state
     :action   ,#'consult--buffer-action
     :default  t
     :items
     ,(lambda ()
        (consult--buffer-query :sort 'visibility
                               :mode 'magit-status-mode
                               :as #'buffer-name)))
  "Open `magit-status' buffers source for `consult-magit'.")

(defvar consult-magit--source-history
  `( :name     "Repository History"
     :narrow   ?h
     :category consult-magit-repo
     :face     consult-file
     :history  consult-magit-repo-history
     :action   ,#'consult-magit--open-action
     :items    ,#'consult-magit--history-items)
  "Repository history source for `consult-magit'.")

(defvar consult-magit--source-known
  `( :name     "Known Repository"
     :narrow   ?r
     :category consult-magit-repo
     :face     consult-file
     :action   ,#'consult-magit--open-action
     :enabled  ,(lambda () consult-magit-include-known-repositories)
     :items    ,#'consult-magit--known-items)
  "Known repositories source for `consult-magit'.
Populated from `magit-repository-directories' and only enabled when
`consult-magit-include-known-repositories' is non-nil.")

(defcustom consult-magit-sources
  '(consult-magit--source-buffer
    consult-magit--source-history
    consult-magit--source-known)
  "Sources used by `consult-magit'.
See `consult--multi' for a description of the source format."
  :type '(repeat symbol))

;;;; Command

(defun consult-magit--prepare-sources ()
  "Resolve `consult-magit-sources' for the current invocation.
Return the enabled sources that actually have candidates, with their
items pre-computed and the first non-empty source marked as the
default.  This lets the command offer the history (or known
repositories) even when no `magit-status' buffer is currently open."
  (let (result default-set)
    (dolist (sym consult-magit-sources)
      (let* ((src (if (symbolp sym) (symbol-value sym) sym))
             (enabled (funcall (or (plist-get src :enabled) #'always)))
             (items (and enabled (plist-get src :items)))
             (items (if (functionp items) (funcall items) items)))
        (when items
          ;; Copy so we can override :items and :default without mutating the
          ;; source variable, and reuse the already-computed items.
          (let ((copy (copy-sequence src)))
            (setq copy (plist-put copy :items items))
            (setq copy (plist-put copy :default (unless default-set
                                                  (setq default-set t))))
            (push copy result)))))
    (nreverse result)))

;;;###autoload
(defun consult-magit ()
  "Switch to a magit repository using `consult'.
Offers open `magit-status' buffers, a history of previously opened
repositories, and optionally repositories known to magit (see
`consult-magit-include-known-repositories').

The history and known repositories are available even when no
`magit-status' buffer is currently open."
  (interactive)
  (let ((sources (consult-magit--prepare-sources)))
    (unless sources
      (user-error "No open magit buffers or repository history"))
    (consult--multi sources
                    :require-match t
                    :sort nil
                    :prompt "Switch to repository: "
                    :history 'consult-magit--history)))

(provide 'consult-magit)
;;; consult-magit.el ends here
