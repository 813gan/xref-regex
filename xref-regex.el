;;; xref-regex.el --- Jump to references/definitions using [ar]g -*- lexical-binding: t; -*-

;; URL: https://github.com/813gan/xref-regex
;; Keywords: convenience, tools
;; Version: 1.0
;; Package: xref-regex
;; Package-Requires: ((emacs "25.1"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; # xref-regex

;; Simple [xref](https://www.gnu.org/software/emacs/manual/html_node/emacs/Xref.html) backend that use user-defined regular expressions.
;; It allows Emacs to support basic navigation in non standard files
;; like configuration files containing references.

;; Source code is shameless copy paste from [xref-js2](https://github.com/js-emacs/xref-js2/), with JS specific logic removed.

;; ## Installation

;; You can just download file `xref-regex.el` and install it using `M-x package-install-file`.
;; [el-get recipe](https://github.com/dimitri/el-get/pull/2910/files) is also available.

;; ## Dependencies

;; - Emacs above 25.1
;; - [ag](http://geoff.greer.fm/ag/), [rg](https://github.com/BurntSushi/ripgrep) or GNU grep
;;   Customize `xref-regex-search-program` to select search tool.  `grep` is default.

;; ## Usage

;; Apart from enabling xref backend with
;; ```
;; (add-hook 'some-random-mode-hook (lambda ()
;;   (add-hook 'xref-backend-functions #'xref-regex-xref-backend nil t)))
;; ```
;; you need to set variables `xref-regex-definitions-regexps` `xref-regex-references-regexps`
;; to lists of regular expression templates,
;; that will match definitions and references to symbols of interest.

;; Example of such regex template list is `("^Host \\K%s" "^Match originalhost \\K%s")`
;; for definitions and `("ProxyJump %s")` for references.
;; Including `%s` is necessary.  It will be replaced by tag Xref will search for.
;; Thanks for `\\K` your point will land in correct column instead beginning of line.
;; (grep does not support `--columns` so xref will always jump to 1st column)
;; Double backslash instead single is needed due to Lisp syntax.

;; Adding following [header](https://www.gnu.org/software/emacs/manual/html_node/emacs/Specifying-File-Variables.html) to your `.ssh/config` will let you use xref to jump to Proxy definition.
;; `# -*- mode: conf; xref-regex-definitions-regexps: ("^Host \\K%s" "^Match originalhost \\K%s"); xref-regex-references-regexps: ("ProxyJump \\K%s"); -*-`
;; Use `M-x normal-mode` or reopen buffer to make it work.

;; You can also use [Directory Variables](https://www.gnu.org/software/emacs/manual/html_node/emacs/Directory-Variables.html) if you don't want to pollute file headers.

;; Possibilities are limited only by Your imagination.  And your ability to write regular expressions.
;; And limitations of regular expressions.

;; ## Troubleshooting

;; If your data is hard to parse with regular expressions you can create comments containing tags instead.

;; If you want searching tool to follow symlinks, customize variables `xref-regex-[ar]g-arguments`
;; and add flag `--follow` to follow symlinks.
;; or in case of grep replace `--recursive` with `--dereference-recursive`
;; in variable `xref-regex-grep-arguments`.

;; Variables `xref-regex-ignored-dirs` and `xref-regex-ignored-files` allows you to ignore unwanted files/dirs.

;;; Code:

(require 'subr-x)
(require 'xref)
(require 'seq)
(require 'map)
(require 'vc)

(defun xref-regex-string-list-p (obj)
  "Determine if OBJ is a list of strings."
  (and (listp obj) (seq-every-p #'stringp obj)))

(defcustom xref-regex-search-program 'grep
  "The backend program used for searching."
  :type 'symbol
  :group 'xref-regex
  :options '(ag rg grep))

(defcustom xref-regex-ag-arguments '("--noheading" "--nocolor" "--column")
  "Default arguments passed to ag."
  :type 'list
  :group 'xref-regex)

(defcustom xref-regex-rg-arguments '("--no-heading"
				     "--line-number"    ; not activated by default on comint
				     "--column"
				     "--pcre2"          ; provides regexp backtracking
				     "--ignore-case"    ; ag is case insensitive by default
				     "--color" "never")
  "Default arguments passed to ripgrep."
  :type 'list
  :group 'xref-regex)

(defcustom xref-regex-grep-arguments '("--line-number"
				       "--binary-files=without-match"
				       "--perl-regexp"
				       "--ignore-case"
				       "--color=never"
				       "--with-filename"
				       "--recursive")
  "Default arguments passed to ripgrep."
  :type 'list
  :group 'xref-regex)

(defcustom xref-regex-ignored-dirs '()
  "List of directories to be ignored when performing a search."
  :type 'list
  :group 'xref-regex
  :safe #'xref-regex-string-list-p)

(defcustom xref-regex-ignored-files '()
  "List of files to be ignored when performing a search."
  :type 'list
  :group 'xref-regex
  :safe #'xref-regex-string-list-p)

(defcustom xref-regex-definitions-regexps '()
  "List of regular expressions that match definitions of a symbol.
In each regexp string, '%s' is expanded with the searched symbol.
This variable is  intended to be used as File Variable."
  :type 'list
  :group 'xref-regex
  :safe #'xref-regex-string-list-p)

(defcustom xref-regex-references-regexps '()
  "List of regular expressions that match references to a symbol.
In each regexp string, '%s' is expanded with the searched symbol.
This variable is intended to be used as File Variable."
  :type 'list
  :group 'xref-regex
  :safe #'xref-regex-string-list-p)

;;;###autoload
(defun xref-regex-xref-backend ()
  "Xref-regex backend for Xref."
  'xref-regex)

(cl-defmethod xref-backend-identifier-at-point ((_backend (eql xref-regex)))
  (symbol-name (symbol-at-point)))

(cl-defmethod xref-backend-definitions ((_backend (eql xref-regex)) symbol)
  (xref-regex--xref-find-definitions symbol))

(cl-defmethod xref-backend-references ((_backend (eql xref-regex)) symbol)
  (xref-regex--xref-find-references symbol))

(defun xref-regex--xref-find-definitions (symbol)
  "Return a list of candidates matching SYMBOL."
  (seq-map (lambda (candidate)
	     (xref-regex--make-xref candidate))
	   (xref-regex--find-definitions symbol)))

(cl-defmethod xref-backend-identifier-completion-table ((_backend (eql xref-regex)))
  "Return a list of terms for completions from symbols in the current buffer.

The current implementation returns all the words in the buffer,
which is really sub optimal."
  (let (words)
    (save-excursion
      (save-restriction
	(widen)
	(goto-char (point-min))
	(while (re-search-forward "\\w+" nil t)
	  (add-to-list 'words (match-string-no-properties 0)))
	(seq-uniq words)))))

(defun xref-regex--xref-find-references (symbol)
  "Return a list of reference candidates matching SYMBOL."
  (seq-map (lambda (candidate)
	     (xref-regex--make-xref candidate))
	   (xref-regex--find-references symbol)))

(defun xref-regex--make-xref (candidate)
  "Return a new Xref object built from CANDIDATE."
  (xref-make (map-elt candidate 'match)
	     (xref-make-file-location (map-elt candidate 'file)
				      (map-elt candidate 'line)
				      (map-elt candidate 'column) )))

(defun xref-regex--find-definitions (symbol)
  "Return a list of definitions for SYMBOL from an ag search."
  (xref-regex--find-candidates
   symbol
   (xref-regex--make-regexp symbol xref-regex-definitions-regexps)))

(defun xref-regex--find-references (symbol)
  "Return a list of references for SYMBOL from an ag search."
  (xref-regex--find-candidates
   symbol
   (xref-regex--make-regexp symbol xref-regex-references-regexps)))

(defun xref-regex--make-regexp (symbol regexps)
  "Return a regular expression to search for SYMBOL using REGEXPS.

REGEXPS must be a list of regular expressions, which are
concatenated together into one regexp, expanding occurrences of
'%s' with SYMBOL."
  (mapconcat #'identity
	     (mapcar (lambda (str)
		       (format str symbol))
		     regexps) "|"))

(defun xref-regex--find-candidates (symbol regexp)
  (let ((default-directory (xref-regex--root-dir))
	matches)
    (with-temp-buffer
      (let* ((search-tuple (cond ;; => (prog-name . function-to-get-args)
			    ((eq xref-regex-search-program 'rg)
			     '("rg" . xref-regex--search-rg-get-args))
			    ((eq xref-regex-search-program 'ag)
			     '("ag" . xref-regex--search-ag-get-args))
			    ((eq xref-regex-search-program 'grep)
			     '("grep" . xref-regex--search-grep-get-args)) ))
	     (search-program (car search-tuple))
	     (search-args    (remove nil ;; rm in case no search args given
				     (funcall (cdr search-tuple) regexp))))
	(apply #'process-file (executable-find search-program) nil t nil search-args))

      (goto-char (point-max)) ;; NOTE maybe redundant
      (while (re-search-backward "^\\(.+\\)$" nil t)
	(push (match-string-no-properties 1) matches)))
    (seq-map (lambda (match)
	       (xref-regex--candidate symbol match))
	     matches)) )

(defun xref-regex--search-ag-get-args (regexp)
  "Aggregate command line arguments to search for REGEXP using ag."
  `(,@xref-regex-ag-arguments
    ,@(seq-mapcat (lambda (dir)
		    (list "--ignore-dir" dir))
		  xref-regex-ignored-dirs)
    ,@(seq-mapcat (lambda (file)
		    (list "--ignore" file))
		  xref-regex-ignored-files)
    ,regexp))

(defun xref-regex--search-rg-get-args (regexp)
  "Aggregate command line arguments to search for REGEXP using ripgrep."
  `(,@xref-regex-rg-arguments
    ,@(seq-mapcat (lambda (dir)
		    (list "-g" (concat "!"                               ; exclude not include
				       dir                               ; directory string
				       (unless (string-suffix-p "/" dir) ; pattern for a directory
					 "/"))))                         ; must end with a slash
		  xref-regex-ignored-dirs)
    ,@(seq-mapcat (lambda (pattern)
		    (list "-g" (concat "!" pattern)))
		  xref-regex-ignored-files)
    ,regexp))

(defun xref-regex--search-grep-get-args (regexp)
  "Aggregate command line arguments to search for REGEXP using grep."
  `(,@xref-regex-grep-arguments
    ,@(seq-mapcat (lambda (dir)
		    (list "--exclude-dir" dir))
		  xref-regex-ignored-dirs)
    ,@(seq-mapcat (lambda (pattern)
		    (list "--exclude" pattern))
		  xref-regex-ignored-files)
    ,regexp))

(defun xref-regex--root-dir ()
  "Return the root directory of the project."
  (or (ignore-errors
	(projectile-project-root))
      (ignore-errors
	(vc-root-dir))
      (file-name-directory buffer-file-name)))

(defun xref-regex--get-column (attrs)
  "Get column from ATTRS unless grep is used.
grep does not support --columns"
  (if (eq xref-regex-search-program 'grep)
      0 (string-to-number (caddr attrs)) ))

(defun xref-regex--candidate (symbol match)
  "Return a candidate alist built from SYMBOL and a raw MATCH result.
The MATCH is one output result from the ag search."
  (let* ((attrs (split-string match ":" t))
	 (match (string-trim (mapconcat #'identity (cddr attrs) ":"))))
    ;; Some minified JS files might match a search. To avoid cluttering the
    ;; search result, we trim the output.
    (when (> (seq-length match) 100)
      (setq match (concat (seq-take match 100) "...")))
    (list (cons 'file (expand-file-name (car attrs) (xref-regex--root-dir)))
	  (cons 'line (string-to-number (cadr attrs)))
	  (cons 'column (xref-regex--get-column attrs))
	  (cons 'symbol symbol)
	  (cons 'match match))))

(provide 'xref-regex)
;;; xref-regex.el ends here
