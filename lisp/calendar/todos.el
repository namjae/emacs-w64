;;; Todos.el --- facilities for making and maintaining Todo lists

;; Copyright (C) 1997, 1999, 2001-2012  Free Software Foundation, Inc.

;; Author: Oliver Seidel <privat@os10000.net>
;;         Stephen Berman <stephen.berman@gmx.net>
;; Maintainer: Stephen Berman <stephen.berman@gmx.net>
;; Created: 2 Aug 1997
;; Keywords: calendar, todo

;; This file is [not yet] part of GNU Emacs.

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

;;; Code:

(require 'diary-lib)
;; For remove-duplicates in todos-insertion-commands-args.
(eval-when-compile (require 'cl))

;; ---------------------------------------------------------------------------
;;; User options

(defgroup todos nil
  "Create and maintain categorized lists of todo items."
  :link '(emacs-commentary-link "todos")
  :version "24.2"
  :group 'calendar)

(defcustom todos-files-directory (locate-user-emacs-file "todos/")
  "Directory where user's Todos files are saved."
  :type 'directory
  :group 'todos)

(defun todos-files (&optional archives)
  "Default value of `todos-files-function'.
This returns the case-insensitive alphabetically sorted list of
file truenames in `todos-files-directory' with the extension
\".todo\".  With non-nil ARCHIVES return the list of archive file
truenames (those with the extension \".toda\")."
  (let ((files (if (file-exists-p todos-files-directory)
		   (mapcar 'file-truename
		    (directory-files todos-files-directory t
				     (if archives "\.toda$" "\.todo$") t)))))
    (sort files (lambda (s1 s2) (let ((cis1 (upcase s1))
				      (cis2 (upcase s2)))
				  (string< cis1 cis2))))))

(defcustom todos-files-function 'todos-files
  "Function returning the value of the variable `todos-files'.
This function should take an optional argument that, if non-nil,
makes it return the value of the variable `todos-archives'."
  :type 'function
  :group 'todos)

(defun todos-short-file-name (file)
  "Return short form of Todos FILE.
This lacks the extension and directory components."
  (file-name-sans-extension (file-name-nondirectory file)))

(defcustom todos-default-todos-file (todos-short-file-name
				     (car (funcall todos-files-function)))
  "Todos file visited by first session invocation of `todos-show'."
  :type `(radio ,@(mapcar (lambda (f) (list 'const f))
			  (mapcar 'todos-short-file-name
				  (funcall todos-files-function))))
  :group 'todos)

(defun todos-reevaluate-default-file-defcustom ()
  "Reevaluate defcustom of `todos-default-todos-file'.
Called after adding or deleting a Todos file."
  (eval (defcustom todos-default-todos-file (car (funcall todos-files-function))
	  "Todos file visited by first session invocation of `todos-show'."
	  :type `(radio ,@(mapcar (lambda (f) (list 'const f))
				  (mapcar 'todos-short-file-name
					  (funcall todos-files-function))))
	  :group 'todos)))

(defcustom todos-show-current-file t
  "Non-nil to make `todos-show' visit the current Todos file.
Otherwise, `todos-show' always visits `todos-default-todos-file'."
  :type 'boolean
  :initialize 'custom-initialize-default
  :set 'todos-set-show-current-file
  :group 'todos)

(defun todos-set-show-current-file (symbol value)
  "The :set function for user option `todos-show-current-file'."
  (custom-set-default symbol value)
  (if value
      (add-hook 'pre-command-hook 'todos-show-current-file nil t)
    (remove-hook 'pre-command-hook 'todos-show-current-file t)))

(defcustom todos-category-completions-files nil
  "List of files for building `todos-read-category' completions."
  :type `(set ,@(mapcar (lambda (f) (list 'const f))
			(mapcar 'todos-short-file-name
				(funcall todos-files-function))))
  :group 'todos)

(defun todos-reevaluate-category-completions-files-defcustom ()
  "Reevaluate defcustom of `todos-category-completions-files'.
Called after adding or deleting a Todos file."
  (eval (defcustom todos-category-completions-files nil
  "List of files for building `todos-read-category' completions."
	  :type `(set ,@(mapcar (lambda (f) (list 'const f))
				(mapcar 'todos-short-file-name
					(funcall todos-files-function))))
	  :group 'todos)))

(defcustom todos-visit-files-commands (list 'find-file 'dired-find-file)
  "List of file finding commands for `todos-display-as-todos-file'.
Invoking these commands to visit a Todos or Todos Archive file
calls `todos-show' or `todos-show-archive', so that the file is
displayed correctly."
  :type '(repeat function)
  :group 'todos)

(defcustom todos-initial-file "Todo"
  "Default file name offered on adding first Todos file."
  :type 'string
  :group 'todos)

(defcustom todos-initial-category "Todo"
  "Default category name offered on initializing a new Todos file."
  :type 'string
  :group 'todos)

(defcustom todos-show-first 'first
  "What action to take on first use of `todos-show' on a file."
  :type '(choice (const :tag "Show first category" first)
		 (const :tag "Show table of categories" table)
		 (const :tag "Show top priorities" top)
		 (const :tag "Show diary items" diary)
		 (const :tag "Show regexp items" regexp))
  :group 'todos)

(defcustom todos-completion-ignore-case nil
  "Non-nil means case is ignored by `todos-read-*' functions."
  :type 'boolean
  :group 'todos)

(defcustom todos-undo-item-omit-comment 'ask
  "Whether to omit done item comment on undoing the item.
Nil means never omit the comment, t means always omit it, `ask'
means prompt user and omit comment only on confirmation."
  :type '(choice (const :tag "Never" nil)
		 (const :tag "Always" t)
		 (const :tag "Ask" ask))
  :group 'todos)

(defcustom todos-print-function 'ps-print-buffer-with-faces
  "Function called to print buffer content; see `todos-print'."
  :type 'symbol
  :group 'todos)

(defcustom todos-todo-mode-date-time-regexp
  (concat "\\(?1:[0-9]\\{4\\}\\)-\\(?2:[0-9]\\{2\\}\\)-"
	  "\\(?3:[0-9]\\{2\\}\\) \\(?4:[0-9]\\{2\\}:[0-9]\\{2\\}\\)")
  "Regexp matching legacy todo-mode.el item date-time strings.
In order for `todos-convert-legacy-files' to correctly convert this
string to the current Todos format, the regexp must contain four
explicitly numbered groups (see `(elisp) Regexp Backslash'),
where group 1 matches a string for the year, group 2 a string for
the month, group 3 a string for the day and group 4 a string for
the time.  The default value converts date-time strings built
using the default value of `todo-time-string-format' from
todo-mode.el."
  :type 'regexp
  :group 'todos)

;; ---------------------------------------------------------------------------
;;; Todos mode display options

(defgroup todos-mode-display nil
  "User display options for Todos mode."
  :version "24.2"
  :group 'todos)

(defcustom todos-prefix ""
  "String prefixed to todo items for visual distinction."
  :type '(string :validate
		 (lambda (widget)
		   (when (string= (widget-value widget) todos-item-mark)
		     (widget-put
		      widget :error
		      "Invalid value: must be distinct from `todos-item-mark'")
		     widget)))
  :initialize 'custom-initialize-default
  :set 'todos-reset-prefix
  :group 'todos-mode-display)

(defcustom todos-number-priorities t
  "Non-nil to prefix items with consecutively increasing integers.
These reflect the priorities of the items in each category."
  :type 'boolean
  :initialize 'custom-initialize-default
  :set 'todos-reset-prefix
  :group 'todos-mode-display)

(defun todos-reset-prefix (symbol value)
  "The :set function for `todos-prefix' and `todos-number-priorities'."
  (let ((oldvalue (symbol-value symbol))
	(files todos-file-buffers))
    (custom-set-default symbol value)
    (when (not (equal value oldvalue))
      (dolist (f files)
	(with-current-buffer (find-file-noselect f)
	  ;; Activate the new setting in the current category.
	  (save-excursion (todos-category-select)))))))

(defcustom todos-item-mark "*"
  "String used to mark items.
To ensure item marking works, change the value of this option
only when no items are marked."
  :type '(string :validate
		 (lambda (widget)
		   (when (string= (widget-value widget) todos-prefix)
		     (widget-put
		      widget :error
		      "Invalid value: must be distinct from `todos-prefix'")
		     widget)))
  :set (lambda (symbol value)
	 (custom-set-default symbol (propertize value 'face 'todos-mark)))
  :group 'todos-mode-display)

(defcustom todos-done-separator-string "="
  "String for generating `todos-done-separator'.

If the string consists of a single character,
`todos-done-separator' will be the string made by repeating this
character for the width of the window, and the length is
automatically recalculated when the window width changes.  If the
string consists of more (or less) than one character, it will be
the value of `todos-done-separator'."
  :type 'string
  :initialize 'custom-initialize-default
  :set 'todos-reset-done-separator-string
  :group 'todos-mode-display)

(defun todos-reset-done-separator-string (symbol value)
  "The :set function for `todos-done-separator-string'."
  (let ((oldvalue (symbol-value symbol))
	(files todos-file-buffers)
	(sep todos-done-separator))
    (custom-set-default symbol value)
    (when (not (equal value oldvalue))
      (dolist (f files)
	(with-current-buffer (find-file-noselect f)
	  (let (buffer-read-only)
	    (setq todos-done-separator (todos-done-separator))
	    (when (= 1 (length value))
	      (todos-reset-done-separator sep)))
	  (todos-category-select))))))

(defcustom todos-done-string "DONE "
  "Identifying string appended to the front of done todos items."
  :type 'string
  :initialize 'custom-initialize-default
  :set 'todos-reset-done-string
  :group 'todos-mode-display)

(defun todos-reset-done-string (symbol value)
  "The :set function for user option `todos-done-string'."
  (let ((oldvalue (symbol-value symbol))
	(files (append todos-files todos-archives)))
    (custom-set-default symbol value)
    ;; Need to reset this to get font-locking right.
    (setq todos-done-string-start
	  (concat "^\\[" (regexp-quote todos-done-string)))
    (when (not (equal value oldvalue))
      (dolist (f files)
	(with-current-buffer (find-file-noselect f)
	  (let (buffer-read-only)
	    (widen)
	    (goto-char (point-min))
	    (while (not (eobp))
	      (if (re-search-forward
		   (concat "^" (regexp-quote todos-nondiary-start)
			   "\\(" (regexp-quote oldvalue) "\\)")
		   nil t)
		  (replace-match value t t nil 1)
		(forward-line)))
	    (todos-category-select)))))))

(defcustom todos-comment-string "COMMENT"
  "String inserted before optional comment appended to done item."
  :type 'string
  :initialize 'custom-initialize-default
  :set 'todos-reset-comment-string
  :group 'todos-mode-display)

(defun todos-reset-comment-string (symbol value)
  "The :set function for user option `todos-comment-string'."
  (let ((oldvalue (symbol-value symbol))
  	(files (append todos-files todos-archives)))
    (custom-set-default symbol value)
    (when (not (equal value oldvalue))
      (dolist (f files)
  	(with-current-buffer (find-file-noselect f)
  	  (let (buffer-read-only)
  	    (save-excursion
	      (widen)
	      (goto-char (point-min))
	      (while (not (eobp))
		(if (re-search-forward
		     (concat
			     "\\[\\(" (regexp-quote oldvalue) "\\): [^]]*\\]")
		     nil t)
		    (replace-match value t t nil 1)
		  (forward-line)))
	      (todos-category-select))))))))

(defcustom todos-show-with-done nil
  "Non-nil to display done items in all categories."
  :type 'boolean
  :group 'todos-mode-display)

(defun todos-mode-line-control (cat)
  "Return a mode line control for Todos buffers.
Argument CAT is the name of the current Todos category.
This function is the value of the user variable
`todos-mode-line-function'."
  (let ((file (todos-short-file-name todos-current-todos-file)))
    (format "%s category %d: %s" file todos-category-number cat)))

(defcustom todos-mode-line-function 'todos-mode-line-control
  "Function that returns a mode line control for Todos buffers.
The function expects one argument holding the name of the current
Todos category.  The resulting control becomes the local value of
`mode-line-buffer-identification' in each Todos buffer."
  :type 'function
  :group 'todos-mode-display)

(defcustom todos-skip-archived-categories nil
  "Non-nil to skip categories with only archived items when browsing.

Moving by category todos or archive file (with
\\[todos-forward-category] and \\[todos-backward-category]) skips
categories that contain only archived items.  Other commands
still recognize these categories.  In Todos Categories
mode (reached with \\[todos-display-categories]) these categories
shown in `todos-archived-only' face and clicking them in Todos
Categories mode visits the archived categories."
  :type 'boolean
  :group 'todos-mode-display)

(defcustom todos-highlight-item nil
  "Non-nil means highlight items at point."
  :type 'boolean
  :initialize 'custom-initialize-default
  :set 'todos-reset-highlight-item
  :group 'todos-mode-display)

(defun todos-reset-highlight-item (symbol value)
  "The :set function for `todos-highlight-item'."
  (let ((oldvalue (symbol-value symbol))
	(files (append todos-files todos-archives)))
    (custom-set-default symbol value)
    (when (not (equal value oldvalue))
      (dolist (f files)
	(let ((buf (find-buffer-visiting f)))
	  (when buf
	    (with-current-buffer buf
	      (require 'hl-line)
	      (if value
		  (hl-line-mode 1)
		(hl-line-mode -1)))))))))

(defcustom todos-wrap-lines t
  "Non-nil to wrap long lines via `todos-line-wrapping-function'."
  :group 'todos-mode-display
  :type 'boolean)

(defcustom todos-line-wrapping-function 'todos-wrap-and-indent
  "Line wrapping function used with non-nil `todos-wrap-lines'."
  :group 'todos-mode-display
  :type 'function)

(defun todos-wrap-and-indent ()
  "Use word wrapping on long lines and indent with a wrap prefix.
The amount of indentation is given by user option
`todos-indent-to-here'."
  (set (make-local-variable 'word-wrap) t)
  (set (make-local-variable 'wrap-prefix) (make-string todos-indent-to-here 32))
  (unless (member '(continuation) fringe-indicator-alist)
    (push '(continuation) fringe-indicator-alist)))

(defcustom todos-indent-to-here 6
  "Number of spaces `todos-line-wrapping-function' indents to."
  :type '(integer :validate
		  (lambda (widget)
		    (unless (> (widget-value widget) 0)
		      (widget-put widget :error
				  "Invalid value: must be a positive integer")
		      widget)))
  :group 'todos)

(defun todos-indent ()
  "Indent from point to `todos-indent-to-here'."
  (indent-to todos-indent-to-here todos-indent-to-here))

;; ---------------------------------------------------------------------------
;;; Item insertion options

(defgroup todos-item-insertion nil
  "User options for adding new todo items."
  :version "24.2"
  :group 'todos)

(defcustom todos-include-in-diary nil
  "Non-nil to allow new Todo items to be included in the diary."
  :type 'boolean
  :group 'todos-item-insertion)

(defcustom todos-diary-nonmarking nil
  "Non-nil to insert new Todo diary items as nonmarking by default.
This appends `diary-nonmarking-symbol' to the front of an item on
insertion provided it doesn't begin with `todos-nondiary-marker'."
  :type 'boolean
  :group 'todos-item-insertion)

(defcustom todos-nondiary-marker '("[" "]")
  "List of strings surrounding item date to block diary inclusion.
The first string is inserted before the item date and must be a
non-empty string that does not match a diary date in order to
have its intended effect.  The second string is inserted after
the diary date."
  :type '(list string string)
  :group 'todos-item-insertion
  :initialize 'custom-initialize-default
  :set 'todos-reset-nondiary-marker)

(defun todos-reset-nondiary-marker (symbol value)
  "The :set function for user option `todos-nondiary-marker'."
  (let ((oldvalue (symbol-value symbol))
	(files (append todos-files todos-archives)))
    (custom-set-default symbol value)
    ;; Need to reset these to get font-locking right.
    (setq todos-nondiary-start (nth 0 todos-nondiary-marker)
	  todos-nondiary-end (nth 1 todos-nondiary-marker)
	  todos-date-string-start
	  ;; See comment in defvar of `todos-date-string-start'.
	  (concat "^\\(" (regexp-quote todos-nondiary-start) "\\|"
		  (regexp-quote diary-nonmarking-symbol) "\\)?"))
    (when (not (equal value oldvalue))
      (dolist (f files)
	(with-current-buffer (find-file-noselect f)
	  (let (buffer-read-only)
	    (widen)
	    (goto-char (point-min))
	    (while (not (eobp))
	      (if (re-search-forward
		   (concat "^\\(" todos-done-string-start "[^][]+] \\)?"
			   "\\(?1:" (regexp-quote (car oldvalue))
			   "\\)" todos-date-pattern "\\( "
			   diary-time-regexp "\\)?\\(?2:"
			   (regexp-quote (cadr oldvalue)) "\\)")
		   nil t)
		  (progn
		    (replace-match (nth 0 value) t t nil 1)
		    (replace-match (nth 1 value) t t nil 2))
		(forward-line)))
	    (todos-category-select)))))))

(defcustom todos-always-add-time-string nil
  "Non-nil adds current time to a new item's date header by default.
When the Todos insertion commands have a non-nil \"maybe-notime\"
argument, this reverses the effect of
`todos-always-add-time-string': if t, these commands omit the
current time, if nil, they include it."
  :type 'boolean
  :group 'todos-item-insertion)

(defcustom todos-use-only-highlighted-region t
  "Non-nil to enable inserting only highlighted region as new item."
  :type 'boolean
  :group 'todos-item-insertion)

;; ---------------------------------------------------------------------------
;;; Todos Filter Items mode options

(defgroup todos-filtered nil
  "User options for Todos Filter Items mode."
  :version "24.2"
  :group 'todos)

(defcustom todos-priorities-rules nil
  "List of rules giving how many items `todos-top-priorities' shows.
This variable should be set interactively by
`\\[todos-set-top-priorities-in-file]' or
`\\[todos-set-top-priorities-in-category]'.

Each rule is a list of the form (FILE NUM ALIST), where FILE is a
member of `todos-files', NUM is a number specifying the default
number of top priority items for each category in that file, and
ALIST, when non-nil, consists of conses of a category name in
FILE and a number specifying the default number of top priority
items in that category, which overrides NUM."
  :type 'sexp
  :group 'todos-filtered)

;; FIXME: rename to todos-top-priorities AFTER renaming command
;; todos-top-priorities to todos-filter-top-priorities
(defcustom todos-show-priorities 1
  "Default number of top priorities shown by `todos-top-priorities'."
  :type 'integer
  :group 'todos-filtered)

(defcustom todos-filter-files nil
  "List of default files for multifile item filtering."
  :type `(set ,@(mapcar (lambda (f) (list 'const f))
			(mapcar 'todos-short-file-name
				(funcall todos-files-function))))
  :group 'todos-filtered)

(defun todos-reevaluate-filter-files-defcustom ()
  "Reevaluate defcustom of `todos-filter-files'.
Called after adding or deleting a Todos file."
  (eval (defcustom todos-filter-files nil
	  "List of files for multifile item filtering."
	  :type `(set ,@(mapcar (lambda (f) (list 'const f))
				(mapcar 'todos-short-file-name
					(funcall todos-files-function))))
	  :group 'todos)))

(defcustom todos-filter-done-items nil
  "Non-nil to include done items when processing regexp filters.
Done items from corresponding archive files are also included."
  :type 'boolean
  :group 'todos-filtered)

;; ---------------------------------------------------------------------------
;;; Todos Categories mode options

(defgroup todos-categories nil
  "User options for Todos Categories mode."
  :version "24.2"
  :group 'todos)

(defcustom todos-categories-category-label "Category"
  "Category button label in Todos Categories mode."
  :type 'string
  :group 'todos-categories)

(defcustom todos-categories-todo-label "Todo"
  "Todo button label in Todos Categories mode."
  :type 'string
  :group 'todos-categories)

(defcustom todos-categories-diary-label "Diary"
  "Diary button label in Todos Categories mode."
  :type 'string
  :group 'todos-categories)

(defcustom todos-categories-done-label "Done"
  "Done button label in Todos Categories mode."
  :type 'string
  :group 'todos-categories)

(defcustom todos-categories-archived-label "Archived"
  "Archived button label in Todos Categories mode."
  :type 'string
  :group 'todos-categories)

(defcustom todos-categories-totals-label "Totals"
  "String to label total item counts in Todos Categories mode."
  :type 'string
  :group 'todos-categories)

(defcustom todos-categories-number-separator " | "
  "String between number and category in Todos Categories mode.
This separates the number from the category name in the default
categories display according to priority."
  :type 'string
  :group 'todos-categories)

(defcustom todos-categories-align 'center
  "Alignment of category names in Todos Categories mode."
  :type '(radio (const left) (const center) (const right))
  :group 'todos-categories)

;; ---------------------------------------------------------------------------
;;; Faces and font locking

(defgroup todos-faces nil
  "Faces for the Todos modes."
  :version "24.2"
  :group 'todos)

(defface todos-prefix-string
  ;; '((t :inherit font-lock-constant-face))
  '((((class grayscale) (background light))
     (:foreground "LightGray" :weight bold :underline t))
    (((class grayscale) (background dark))
     (:foreground "Gray50" :weight bold :underline t))
    (((class color) (min-colors 88) (background light)) (:foreground "dark cyan"))
    (((class color) (min-colors 88) (background dark)) (:foreground "Aquamarine"))
    (((class color) (min-colors 16) (background light)) (:foreground "CadetBlue"))
    (((class color) (min-colors 16) (background dark)) (:foreground "Aquamarine"))
    (((class color) (min-colors 8)) (:foreground "magenta"))
    (t (:weight bold :underline t)))
  "Face for Todos prefix or numerical priority string."
  :group 'todos-faces)

(defface todos-top-priority
  ;; bold font-lock-comment-face
  '((default :weight bold)
    (((class grayscale) (background light)) :foreground "DimGray" :slant italic)
    (((class grayscale) (background dark)) :foreground "LightGray" :slant italic)
    (((class color) (min-colors 88) (background light)) :foreground "Firebrick")
    (((class color) (min-colors 88) (background dark)) :foreground "chocolate1")
    (((class color) (min-colors 16) (background light)) :foreground "red")
    (((class color) (min-colors 16) (background dark)) :foreground "red1")
    (((class color) (min-colors 8) (background light)) :foreground "red")
    (((class color) (min-colors 8) (background dark)) :foreground "yellow")
    (t :slant italic))
  "Face for top priority Todos item numerical priority string.
The item's priority number string has this face if the number is
less than or equal the category's top priority setting."
  :group 'todos-faces)

(defface todos-mark
  ;; '((t :inherit font-lock-warning-face))
  '((((class color)
      (min-colors 88)
      (background light))
     (:weight bold :foreground "Red1"))
    (((class color)
      (min-colors 88)
      (background dark))
     (:weight bold :foreground "Pink"))
    (((class color)
      (min-colors 16)
      (background light))
     (:weight bold :foreground "Red1"))
    (((class color)
      (min-colors 16)
      (background dark))
     (:weight bold :foreground "Pink"))
    (((class color)
      (min-colors 8))
     (:foreground "red"))
    (t
     (:weight bold :inverse-video t)))
  "Face for marks on Todos items."
  :group 'todos-faces)

(defface todos-button
  ;; '((t :inherit widget-field))
  '((((type tty))
     (:foreground "black" :background "yellow3"))
    (((class grayscale color)
      (background light))
     (:background "gray85"))
    (((class grayscale color)
      (background dark))
     (:background "dim gray"))
    (t
     (:slant italic)))
  "Face for buttons in todos-display-categories."
  :group 'todos-faces)

(defface todos-sorted-column
  '((((type tty))
     (:inverse-video t))
    (((class color)
      (background light))
     (:background "grey85"))
    (((class color)
      (background dark))
      (:background "grey85" :foreground "grey10"))
    (t
     (:background "gray")))
  "Face for buttons in todos-display-categories."
  :group 'todos-faces)

(defface todos-archived-only
  ;; '((t (:inherit (shadow))))
  '((((class color)
      (background light))
     (:foreground "grey50"))
    (((class color)
      (background dark))
     (:foreground "grey70"))
    (t
     (:foreground "gray")))
  "Face for archived-only categories in todos-display-categories."
  :group 'todos-faces)

(defface todos-search
  ;; '((t :inherit match))
  '((((class color)
      (min-colors 88)
      (background light))
     (:background "yellow1"))
    (((class color)
      (min-colors 88)
      (background dark))
     (:background "RoyalBlue3"))
    (((class color)
      (min-colors 8)
      (background light))
     (:foreground "black" :background "yellow"))
    (((class color)
      (min-colors 8)
      (background dark))
     (:foreground "white" :background "blue"))
    (((type tty)
      (class mono))
     (:inverse-video t))
    (t
     (:background "gray")))
  "Face for matches found by todos-search."
  :group 'todos-faces)

(defface todos-diary-expired
  ;; Doesn't contrast enough with todos-date (= diary) face.
  ;; ;; '((t :inherit warning))
  ;; '((default :weight bold)
  ;;   (((class color) (min-colors 16)) :foreground "DarkOrange")
  ;;   (((class color)) :foreground "yellow"))
  ;; bold font-lock-function-name-face
  '((default :weight bold)
    (((class color) (min-colors 88) (background light)) :foreground "Blue1")
    (((class color) (min-colors 88) (background dark))  :foreground "LightSkyBlue")
    (((class color) (min-colors 16) (background light)) :foreground "Blue")
    (((class color) (min-colors 16) (background dark))  :foreground "LightSkyBlue")
    (((class color) (min-colors 8)) :foreground "blue")
    (t :inverse-video t))
  "Face for expired dates of diary items."
  :group 'todos-faces)
(defvar todos-diary-expired-face 'todos-diary-expired)

(defface todos-date
  '((t :inherit diary))
  "Face for the date string of a Todos item."
  :group 'todos-faces)
(defvar todos-date-face 'todos-date)

(defface todos-time
  '((t :inherit diary-time))
  "Face for the time string of a Todos item."
  :group 'todos-faces)
(defvar todos-time-face 'todos-time)

(defface todos-nondiary
  ;; '((t :inherit font-lock-type-face))
  '((((class grayscale) (background light)) :foreground "Gray90" :weight bold)
    (((class grayscale) (background dark))  :foreground "DimGray" :weight bold)
    (((class color) (min-colors 88) (background light)) :foreground "ForestGreen")
    (((class color) (min-colors 88) (background dark))  :foreground "PaleGreen")
    (((class color) (min-colors 16) (background light)) :foreground "ForestGreen")
    (((class color) (min-colors 16) (background dark))  :foreground "PaleGreen")
    (((class color) (min-colors 8)) :foreground "green")
    (t :weight bold :underline t))
  "Face for non-diary markers around todo item date/time header."
  :group 'todos-faces)
(defvar todos-nondiary-face 'todos-nondiary)

(defface todos-category-string
    ;; '((t :inherit font-lock-type-face))
  '((((class grayscale) (background light)) :foreground "Gray90" :weight bold)
    (((class grayscale) (background dark))  :foreground "DimGray" :weight bold)
    (((class color) (min-colors 88) (background light)) :foreground "ForestGreen")
    (((class color) (min-colors 88) (background dark))  :foreground "PaleGreen")
    (((class color) (min-colors 16) (background light)) :foreground "ForestGreen")
    (((class color) (min-colors 16) (background dark))  :foreground "PaleGreen")
    (((class color) (min-colors 8)) :foreground "green")
    (t :weight bold :underline t))
  "Face for category file names in Todos Filtered Item."
  :group 'todos-faces)
(defvar todos-category-string-face 'todos-category-string)

(defface todos-done
  ;; '((t :inherit font-lock-keyword-face))
  '((((class grayscale) (background light)) :foreground "LightGray" :weight bold)
    (((class grayscale) (background dark))  :foreground "DimGray" :weight bold)
    (((class color) (min-colors 88) (background light)) :foreground "Purple")
    (((class color) (min-colors 88) (background dark))  :foreground "Cyan1")
    (((class color) (min-colors 16) (background light)) :foreground "Purple")
    (((class color) (min-colors 16) (background dark))  :foreground "Cyan")
    (((class color) (min-colors 8)) :foreground "cyan" :weight bold)
    (t :weight bold))
  "Face for done Todos item header string."
  :group 'todos-faces)
(defvar todos-done-face 'todos-done)

(defface todos-comment
  ;; '((t :inherit font-lock-comment-face))
  '((((class grayscale) (background light))
     :foreground "DimGray" :weight bold :slant italic)
    (((class grayscale) (background dark))
     :foreground "LightGray" :weight bold :slant italic)
    (((class color) (min-colors 88) (background light))
     :foreground "Firebrick")
    (((class color) (min-colors 88) (background dark))
     :foreground "chocolate1")
    (((class color) (min-colors 16) (background light))
     :foreground "red")
    (((class color) (min-colors 16) (background dark))
     :foreground "red1")
    (((class color) (min-colors 8) (background light))
     :foreground "red")
    (((class color) (min-colors 8) (background dark))
     :foreground "yellow")
    (t :weight bold :slant italic))
  "Face for comments appended to done Todos items."
  :group 'todos-faces)
(defvar todos-comment-face 'todos-comment)

(defface todos-done-sep
  ;; '((t :inherit font-lock-builtin-face))
  '((((class grayscale) (background light)) :foreground "LightGray" :weight bold)
    (((class grayscale) (background dark))  :foreground "DimGray" :weight bold)
    (((class color) (min-colors 88) (background light)) :foreground "dark slate blue")
    (((class color) (min-colors 88) (background dark))  :foreground "LightSteelBlue")
    (((class color) (min-colors 16) (background light)) :foreground "Orchid")
    (((class color) (min-colors 16) (background dark)) :foreground "LightSteelBlue")
    (((class color) (min-colors 8)) :foreground "blue" :weight bold)
    (t :weight bold))
  "Face for separator string bewteen done and not done Todos items."
  :group 'todos-faces)
(defvar todos-done-sep-face 'todos-done-sep)

(defun todos-date-string-matcher (lim)
  "Search for Todos date string within LIM for font-locking."
  (re-search-forward
   (concat todos-date-string-start "\\(?1:" todos-date-pattern "\\)") lim t))

(defun todos-time-string-matcher (lim)
  "Search for Todos time string within LIM for font-locking."
  (re-search-forward (concat todos-date-string-start todos-date-pattern
			     " \\(?1:" diary-time-regexp "\\)") lim t))

(defun todos-nondiary-marker-matcher (lim)
  "Search for Todos nondiary markers within LIM for font-locking."
  (re-search-forward (concat "^\\(?1:" (regexp-quote todos-nondiary-start) "\\)"
			     todos-date-pattern "\\(?: " diary-time-regexp
			     "\\)?\\(?2:" (regexp-quote todos-nondiary-end) "\\)")
		     lim t))

(defun todos-diary-nonmarking-matcher (lim)
  "Search for diary nonmarking symbol within LIM for font-locking."
  (re-search-forward (concat "^\\(?1:" (regexp-quote diary-nonmarking-symbol)
			     "\\)" todos-date-pattern) lim t))

(defun todos-diary-expired-matcher (lim)
  "Search for expired diary item date within LIM for font-locking."
  (when (re-search-forward (concat "^\\(?:"
				   (regexp-quote diary-nonmarking-symbol)
				   "\\)?\\(?1:" todos-date-pattern "\\) \\(?2:"
				   diary-time-regexp "\\)?") lim t)
    (let* ((date (match-string-no-properties 1))
    	   (time (match-string-no-properties 2))
	   ;; Function days-between requires a non-empty time string.
    	   (date-time (concat date " " (or time "00:00"))))
      (or (and (not (string-match ".+day\\|\\*" date))
	       (< (days-between date-time (current-time-string)) 0))
	  (todos-diary-expired-matcher lim)))))

(defun todos-done-string-matcher (lim)
  "Search for Todos done header within LIM for font-locking."
  (re-search-forward (concat todos-done-string-start
		      "[^][]+]")
		     lim t))

(defun todos-comment-string-matcher (lim)
  "Search for Todos done comment within LIM for font-locking."
  (re-search-forward (concat "\\[\\(?1:" todos-comment-string "\\):")
		     lim t))

;; (defun todos-category-string-matcher (lim)
;;   "Search for Todos category name within LIM for font-locking.
;; This is for fontifying category names appearing in Todos filter
;; mode."
;;   (if (eq major-mode 'todos-filtered-items-mode)
;;       (re-search-forward
;;        (concat "^\\(?:" todos-date-string-start "\\)?" todos-date-pattern
;;        	       "\\(?: " diary-time-regexp "\\)?\\(?:"
;;        	       (regexp-quote todos-nondiary-end) "\\)? \\(?1:\\[.+\\]\\)")
;;        lim t)))

(defun todos-category-string-matcher-1 (lim)
  "Search for Todos category name within LIM for font-locking.
This is for fontifying category and file names appearing in Todos
Filtered Items mode following done items."
  (if (eq major-mode 'todos-filtered-items-mode)
      (re-search-forward (concat todos-done-string-start todos-date-pattern
				 "\\(?: " diary-time-regexp
				 ;; Use non-greedy operator to prevent
				 ;; capturing possible following non-diary
				 ;; date string.
				 "\\)?] \\(?1:\\[.+?\\]\\)")
			 lim t)))

(defun todos-category-string-matcher-2 (lim)
  "Search for Todos category name within LIM for font-locking.
This is for fontifying category and file names appearing in Todos
Filtered Items mode following todo (not done) items."
  (if (eq major-mode 'todos-filtered-items-mode)
      (re-search-forward (concat todos-date-string-start todos-date-pattern
				 "\\(?: " diary-time-regexp "\\)?\\(?:"
				 (regexp-quote todos-nondiary-end)
				 "\\)? \\(?1:\\[.+\\]\\)")
			 lim t)))

(defvar todos-font-lock-keywords
  (list
   '(todos-nondiary-marker-matcher 1 todos-nondiary-face t)
   '(todos-nondiary-marker-matcher 2 todos-nondiary-face t)
   ;; diary-lib.el uses font-lock-constant-face for diary-nonmarking-symbol.
   '(todos-diary-nonmarking-matcher 1 font-lock-constant-face t)
   '(todos-date-string-matcher 1 todos-date-face t)
   '(todos-time-string-matcher 1 todos-time-face t)
   '(todos-done-string-matcher 0 todos-done-face t)
   '(todos-comment-string-matcher 1 todos-comment-face t)
   '(todos-category-string-matcher-1 1 todos-category-string-face t t)
   '(todos-category-string-matcher-2 1 todos-category-string-face t t)
   '(todos-diary-expired-matcher 1 todos-diary-expired-face t)
   '(todos-diary-expired-matcher 2 todos-diary-expired-face t t)
   )
  "Font-locking for Todos modes.")

;; ---------------------------------------------------------------------------
;;; Todos mode local variables and hook functions

(defvar todos-current-todos-file nil
  "Variable holding the name of the currently active Todos file.")

(defun todos-show-current-file ()
  "Visit current instead of default Todos file with `todos-show'.
This function is added to `pre-command-hook' when user option
`todos-show-current-file' is set to non-nil."
  (setq todos-global-current-todos-file todos-current-todos-file))

(defun todos-display-as-todos-file ()
  "Show Todos files correctly when visited from outside of Todos mode."
  (and (member this-command todos-visit-files-commands)
       (= (- (point-max) (point-min)) (buffer-size))
       (member major-mode '(todos-mode todos-archive-mode))
       (todos-category-select)))

(defun todos-add-to-buffer-list ()
  "Add name of just visited Todos file to `todos-file-buffers'.
This function is added to `find-file-hook' in Todos mode."
  (let ((filename (file-truename (buffer-file-name))))
    (when (member filename todos-files)
      (add-to-list 'todos-file-buffers filename))))

(defun todos-update-buffer-list ()
  "Make current Todos mode buffer file car of `todos-file-buffers'.
This function is added to `post-command-hook' in Todos mode."
  (let ((filename (file-truename (buffer-file-name))))
    (unless (eq (car todos-file-buffers) filename)
      (setq todos-file-buffers
	    (cons filename (delete filename todos-file-buffers))))))

(defun todos-reset-global-current-todos-file ()
  "Update the value of `todos-global-current-todos-file'.
This becomes the latest existing Todos file or, if there is none,
the value of `todos-default-todos-file'.
This function is added to `kill-buffer-hook' in Todos mode."
  (let ((filename (file-truename (buffer-file-name))))
    (setq todos-file-buffers (delete filename todos-file-buffers))
    (setq todos-global-current-todos-file
	  (or (car todos-file-buffers)
	      (todos-absolute-file-name todos-default-todos-file)))))

(defvar todos-categories nil
  "Alist of categories in the current Todos file.
The elements are cons cells whose car is a category name and
whose cdr is a vector of the category's item counts.  These are,
in order, the numbers of todo items, of todo items included in
the Diary, of done items and of archived items.")

(defvar todos-categories-with-marks nil
  "Alist of categories and number of marked items they contain.")

(defvar todos-category-number 1
  "Variable holding the number of the current Todos category.
Todos categories are numbered starting from 1.")

(defvar todos-show-done-only nil
  "If non-nil display only done items in current category.
Set by the command `todos-show-done-only' and used by
`todos-category-select'.")

(defun todos-reset-and-enable-done-separator ()
  "Show resized done items separator overlay after window change.
Added to `window-configuration-change-hook' in `todos-mode'."
  (when (= 1 (length todos-done-separator-string))
    (let ((sep todos-done-separator))
      (setq todos-done-separator (todos-done-separator))
      (save-match-data (todos-reset-done-separator sep)))))

;; ---------------------------------------------------------------------------
;;; Global variables and helper functions for files and buffers

(defvar todos-files (funcall todos-files-function)
  "List of truenames of user's Todos files.")

(defvar todos-archives (funcall todos-files-function t)
  "List of truenames of user's Todos archives.")

(defvar todos-visited nil
  "List of Todos files visited in this session by `todos-show'.
Used to determine initial display according to the value of
`todos-show-first'.")

(defvar todos-file-buffers nil
  "List of file names of live Todos mode buffers.")

(defvar todos-global-current-todos-file nil
  "Variable holding name of current Todos file.
Used by functions called from outside of Todos mode to visit the
current Todos file rather than the default Todos file (i.e. when
users option `todos-show-current-file' is non-nil).")

(defun todos-reevaluate-filelist-defcustoms ()
  "Reevaluate defcustoms that provide choice list of Todos files."
  (custom-set-default 'todos-default-todos-file
		      (symbol-value 'todos-default-todos-file))
  (todos-reevaluate-default-file-defcustom)
  (custom-set-default 'todos-filter-files (symbol-value 'todos-filter-files))
  (todos-reevaluate-filter-files-defcustom)
  (custom-set-default 'todos-category-completions-files
		      (symbol-value 'todos-category-completions-files))
  (todos-reevaluate-category-completions-files-defcustom))

(defvar todos-edit-buffer "*Todos Edit*"
  "Name of current buffer in Todos Edit mode.")

(defvar todos-categories-buffer "*Todos Categories*"
  "Name of buffer in Todos Categories mode.")

(defvar todos-print-buffer "*Todos Print*"
  "Name of buffer containing printable Todos text.")

(defun todos-absolute-file-name (name &optional type)
  "Return the absolute file name of short Todos file NAME.
With TYPE `archive' or `top' return the absolute file name of the
short Todos Archive or Top Priorities file name, respectively."
  ;; NOP if there is no Todos file yet (i.e. don't concatenate nil).
  (when name
    (file-truename
     (concat todos-files-directory name
	     (cond ((eq type 'archive) ".toda")
		   ((eq type 'top) ".todt")
		   ((eq type 'diary) ".tody")
		   ((eq type 'regexp) ".todr")
		   (t ".todo"))))))

(defun todos-check-format ()
  "Signal an error if the current Todos file is ill-formatted.
Otherwise return t.  The error message gives the line number
where the invalid formatting was found."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((cats (prin1-to-string todos-categories))
	    (sexp (buffer-substring-no-properties (line-beginning-position)
						  (line-end-position))))
	;; Check for `todos-categories' sexp as the first line
	(unless (string= sexp cats)
	  (error "Invalid or missing todos-categories sexp")))
      (forward-line)
      (let ((legit (concat "\\(^" (regexp-quote todos-category-beg) "\\)"
			   "\\|\\(" todos-date-string-start todos-date-pattern "\\)"
			   "\\|\\(^[ \t]+[^ \t]*\\)"
			   "\\|^$"
			   "\\|\\(^" (regexp-quote todos-category-done) "\\)"
			   "\\|\\(" todos-done-string-start "\\)")))
	(while (not (eobp))
	  (unless (looking-at legit)
	    (error "Illegitimate Todos file format at line %d"
		   (line-number-at-pos (point))))
	  (forward-line)))))
  ;; (message "This Todos file is well-formatted.")
  t)

;; ---------------------------------------------------------------------------
(defun todos-convert-legacy-date-time ()
  "Return converted date-time string.
Helper function for `todos-convert-legacy-files'."
  (let* ((year (match-string 1))
	 (month (match-string 2))
	 (monthname (calendar-month-name (string-to-number month) t))
	 (day (match-string 3))
	 (time (match-string 4))
	 dayname)
    (replace-match "")
    (insert (mapconcat 'eval calendar-date-display-form "")
	    (when time (concat " " time)))))

;; ---------------------------------------------------------------------------
;;; Global variables and helper functions for categories

(defun todos-category-number (cat)
  "Return the number of category CAT in this Todos file.
The buffer-local variable `todos-category-number' holds this
number as its value."
  (let ((categories (mapcar 'car todos-categories)))
    (setq todos-category-number
	  ;; Increment by one, so that the highest priority category in Todos
	  ;; Categories mode is numbered one rather than zero.
	  (1+ (- (length categories)
		 (length (member cat categories)))))))

(defun todos-current-category ()
  "Return the name of the current category."
  (car (nth (1- todos-category-number) todos-categories)))

(defconst todos-category-beg "--==-- "
  "String marking beginning of category (inserted with its name).")

(defconst todos-category-done "==--== DONE "
  "String marking beginning of category's done items.")

(defun todos-done-separator ()
  "Return string used as value of variable `todos-done-separator'."
  (let ((sep todos-done-separator-string))
    (propertize (if (= 1 (length sep))
		    ;; If separator's length is window-width, then
		    ;; with non-nil todos-wrap-lines and
		    ;; todos-wrap-and-indent as value of
		    ;; todos-line-wrapping-function, an indented empty
		    ;; line appears between the separator and the
		    ;; first done item.
		    (make-string (1- (window-width)) (string-to-char sep))
		    ;; (make-string (window-width) (string-to-char sep))
		  todos-done-separator-string)
		'face 'todos-done-sep)))

(defvar todos-done-separator (todos-done-separator)
  "String used to visually separate done from not done items.
Displayed as an overlay instead of `todos-category-done' when
done items are shown.  Its value is determined by user option
`todos-done-separator-string'.")

(defun todos-reset-done-separator (sep)
  "Replace existing overlays of done items separator string SEP."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (while (re-search-forward
	      (concat "\n\\(" (regexp-quote todos-category-done) "\\)") nil t)
	(let* ((beg (match-beginning 1))
	       (end (match-end 0))
	       (ov (progn (goto-char beg)
			  (todos-get-overlay 'separator)))
	       (old-sep (when ov (overlay-get ov 'display)))
	       new-ov)
	  (when old-sep
	    (unless (string= old-sep sep)
	      (setq new-ov (make-overlay beg end))
	      (overlay-put new-ov 'todos 'separator)
	      (overlay-put new-ov 'display todos-done-separator)
	      (delete-overlay ov))))))))

(defun todos-category-completions ()
  "Return a list of completions for `todos-read-category'.
Each element of the list is a cons of a category name and the
file or list of files (as short file names) it is in.  The files
are the current (or else the default) Todos file plus all other
Todos files named in `todos-category-completions-files'."
  (let* ((curfile (or todos-current-todos-file
		      (and todos-show-current-file
			   todos-global-current-todos-file)
		      (todos-absolute-file-name todos-default-todos-file)))
	 (files (or (mapcar 'todos-absolute-file-name
			    todos-category-completions-files)
		    (list curfile)))
	 listall listf)
    ;; If file was just added, it has no category completions.
    (unless (zerop (buffer-size (find-buffer-visiting curfile)))
      (add-to-list 'files curfile)
      (dolist (f files listall)
	(with-current-buffer (find-file-noselect f 'nowarn)
	  ;; Ensure category is properly displayed in case user
	  ;; switches to file via a non-Todos command.
	  (todos-category-select)
	  (save-excursion
	    (save-restriction
	      (widen)
	      (goto-char (point-min))
	      (setq listf (read (buffer-substring-no-properties
				 (line-beginning-position)
				 (line-end-position)))))))
	(mapc (lambda (elt) (let* ((cat (car elt))
				   (la-elt (assoc cat listall)))
			      (if la-elt
				  (setcdr la-elt (append (list (cdr la-elt))
							 (list f)))
				(push (cons cat f) listall))))
	      listf)))))

(defun todos-category-select ()
  "Display the current category correctly."
  (let ((name (todos-current-category))
	cat-begin cat-end done-start done-sep-start done-end)
    (widen)
    (goto-char (point-min))
    (re-search-forward
     (concat "^" (regexp-quote (concat todos-category-beg name)) "$") nil t)
    (setq cat-begin (1+ (line-end-position)))
    (setq cat-end (if (re-search-forward
		       (concat "^" (regexp-quote todos-category-beg)) nil t)
		      (match-beginning 0)
		    (point-max)))
    (setq mode-line-buffer-identification
	  (funcall todos-mode-line-function name))
    (narrow-to-region cat-begin cat-end)
    (todos-prefix-overlays)
    (goto-char (point-min))
    (if (re-search-forward (concat "\n\\(" (regexp-quote todos-category-done)
				   "\\)") nil t)
	(progn
	  (setq done-start (match-beginning 0))
	  (setq done-sep-start (match-beginning 1))
	  (setq done-end (match-end 0)))
      (error "Category %s is missing todos-category-done string" name))
    (if todos-show-done-only
	(narrow-to-region (1+ done-end) (point-max))
      (when (and todos-show-with-done
		 (re-search-forward todos-done-string-start nil t))
	;; Now we want to see the done items, so reset displayed end to end of
	;; done items.
	(setq done-start cat-end)
	;; Make display overlay for done items separator string, unless there
	;; already is one.
	(let* ((done-sep todos-done-separator)
	       (ov (progn (goto-char done-sep-start)
			  (todos-get-overlay 'separator))))
	  (unless ov
	    (setq ov (make-overlay done-sep-start done-end))
	    (overlay-put ov 'todos 'separator)
	    (overlay-put ov 'display done-sep))))
      (narrow-to-region (point-min) done-start)
      ;; Loading this from todos-mode, or adding it to the mode hook, causes
      ;; Emacs to hang in todos-item-start, at (looking-at todos-item-start).
      (when todos-highlight-item
	(require 'hl-line)
	(hl-line-mode 1)))))

(defun todos-get-count (type &optional category)
  "Return count of TYPE items in CATEGORY.
If CATEGORY is nil, default to the current category."
  (let* ((cat (or category (todos-current-category)))
	 (counts (cdr (assoc cat todos-categories)))
	 (idx (cond ((eq type 'todo) 0)
		    ((eq type 'diary) 1)
		    ((eq type 'done) 2)
		    ((eq type 'archived) 3))))
    (aref counts idx)))

(defun todos-update-count (type increment &optional category)
  "Change count of TYPE items in CATEGORY by integer INCREMENT.
With nil or omitted CATEGORY, default to the current category."
  (let* ((cat (or category (todos-current-category)))
	 (counts (cdr (assoc cat todos-categories)))
	 (idx (cond ((eq type 'todo) 0)
		    ((eq type 'diary) 1)
		    ((eq type 'done) 2)
		    ((eq type 'archived) 3))))
    (aset counts idx (+ increment (aref counts idx)))))

(defun todos-set-categories ()
  "Set `todos-categories' from the sexp at the top of the file."
  ;; New archive files created by `todos-move-category' are empty, which would
  ;; make the sexp test fail and raise an error, so in this case we skip it.
  (unless (zerop (buffer-size))
    (save-excursion
      (save-restriction
	(widen)
	(goto-char (point-min))
	(setq todos-categories
	      (if (looking-at "\(\(\"")
		  (read (buffer-substring-no-properties
			 (line-beginning-position)
			 (line-end-position)))
		(error "Invalid or missing todos-categories sexp")))))))

(defun todos-update-categories-sexp ()
  "Update the `todos-categories' sexp at the top of the file."
  (let (buffer-read-only)
    (save-excursion
      (save-restriction
	(widen)
	(goto-char (point-min))
	(if (looking-at (concat "^" (regexp-quote todos-category-beg)))
	    (progn (newline) (goto-char (point-min)) ; Make space for sexp.
		   (setq todos-categories (todos-make-categories-list t)))
	  (delete-region (line-beginning-position) (line-end-position)))
	(prin1 todos-categories (current-buffer))))))

(defun todos-make-categories-list (&optional force)
  "Return an alist of Todos categories and their item counts.
With non-nil argument FORCE parse the entire file to build the
list; otherwise, get the value by reading the sexp at the top of
the file."
  (setq todos-categories nil)
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let (counts cat archive)
	;; If the file is a todo file and has archived items, identify the
	;; archive, in order to count its items.  But skip this with
	;; `todos-convert-legacy-files', since that converts filed items to
	;; archived items.
	(when buffer-file-name	 ; During conversion there is no file yet.
	  ;; If the file is an archive, it doesn't have an archive.
	  (unless (member (file-truename buffer-file-name)
			  (funcall todos-files-function t))
	    (setq archive (concat (file-name-sans-extension
				   todos-current-todos-file) ".toda"))))
	(while (not (eobp))
	  (cond ((looking-at (concat (regexp-quote todos-category-beg)
				     "\\(.*\\)\n"))
		 (setq cat (match-string-no-properties 1))
		 ;; Counts for each category: [todo diary done archive]
		 (setq counts (make-vector 4 0))
		 (setq todos-categories
		       (append todos-categories (list (cons cat counts))))
		 ;; Add archived item count to the todo file item counts.
		 ;; Make sure to include newly created archives, e.g. due to
		 ;; todos-move-category.
		 (when (member archive (funcall todos-files-function t))
		   (let ((archive-count 0))
		     (with-current-buffer (find-file-noselect archive)
		       (widen)
		       (goto-char (point-min))
		       (when (re-search-forward
			      (concat "^" (regexp-quote todos-category-beg)
				      cat "$")
			      (point-max) t)
			 (forward-line)
			 (while (not (or (looking-at
					  (concat
					   (regexp-quote todos-category-beg)
					   "\\(.*\\)\n"))
					 (eobp)))
			   (when (looking-at todos-done-string-start)
			     (setq archive-count (1+ archive-count)))
			   (forward-line))))
		     (todos-update-count 'archived archive-count cat))))
		((looking-at todos-done-string-start)
		 (todos-update-count 'done 1 cat))
		((looking-at (concat "^\\("
				     (regexp-quote diary-nonmarking-symbol)
				     "\\)?" todos-date-pattern))
		 (todos-update-count 'diary 1 cat)
		 (todos-update-count 'todo 1 cat))
		((looking-at (concat todos-date-string-start todos-date-pattern))
		 (todos-update-count 'todo 1 cat))
		;; If first line is todos-categories list, use it and end loop
		;; -- unless FORCEd to scan whole file.
		((bobp)
		 (unless force
		   (setq todos-categories (read (buffer-substring-no-properties
						 (line-beginning-position)
						 (line-end-position))))
		   (goto-char (1- (point-max))))))
	  (forward-line)))))
  todos-categories)

(defun todos-repair-categories-sexp ()
  "Repair corrupt Todos categories sexp.
This should only be needed as a consequence of careless manual
editing or a bug in todos.el.

*Warning*: Calling this command restores the category order to
the list element order in the Todos categories sexp, so any order
changes made in Todos Categories mode will have to be made again."
  (interactive)
  (let ((todos-categories (todos-make-categories-list t)))
    (todos-update-categories-sexp)))

;;; Global variables and helper functions for items

(defconst todos-month-name-array
  (vconcat calendar-month-name-array (vector "*"))
  "Array of month names, in order.
The final element is \"*\", indicating an unspecified month.")

(defconst todos-month-abbrev-array
  (vconcat calendar-month-abbrev-array (vector "*"))
  "Array of abbreviated month names, in order.
The final element is \"*\", indicating an unspecified month.")

(defconst todos-date-pattern
  (let ((dayname (diary-name-pattern calendar-day-name-array nil t)))
    (concat "\\(?5:" dayname "\\|"
	    (let ((dayname)
		  (monthname (format "\\(?6:%s\\)" (diary-name-pattern
						    todos-month-name-array
						    todos-month-abbrev-array)))
		  (month "\\(?7:[0-9]+\\|\\*\\)")
		  (day "\\(?8:[0-9]+\\|\\*\\)")
		  (year "-?\\(?9:[0-9]+\\|\\*\\)"))
	      (mapconcat 'eval calendar-date-display-form ""))
	    "\\)"))
  "Regular expression matching a Todos date header.")

(defconst todos-nondiary-start (nth 0 todos-nondiary-marker)
  "String inserted before item date to block diary inclusion.")

(defconst todos-nondiary-end (nth 1 todos-nondiary-marker)
  "String inserted after item date matching `todos-nondiary-start'.")

;; By itself this matches anything, because of the `?'; however, it's only
;; used in the context of `todos-date-pattern' (but Emacs Lisp lacks
;; lookahead).
(defconst todos-date-string-start
  (concat "^\\(" (regexp-quote todos-nondiary-start) "\\|"
	  (regexp-quote diary-nonmarking-symbol) "\\)?")
  "Regular expression matching part of item header before the date.")

(defconst todos-done-string-start
  (concat "^\\[" (regexp-quote todos-done-string))
  "Regular expression matching start of done item.")

(defconst todos-item-start (concat "\\(" todos-date-string-start "\\|"
				 todos-done-string-start "\\)"
				 todos-date-pattern)
  "String identifying start of a Todos item.")

(defun todos-item-start ()
  "Move to start of current Todos item and return its position."
  (unless (or
	   ;; Buffer is empty (invocation possible e.g. via todos-forward-item
	   ;; from todos-filter-items when processing category with no todo
	   ;; items).
	   (eq (point-min) (point-max))
	   ;; Point is on the empty line below category's last todo item...
	   (and (looking-at "^$")
		(or (eobp)		; ...and done items are hidden...
		    (save-excursion	; ...or done items are visible.
		      (forward-line)
		      (looking-at (concat "^"
					  (regexp-quote todos-category-done))))))
	   ;; Buffer is widened.
	   (looking-at (regexp-quote todos-category-beg)))
    (goto-char (line-beginning-position))
    (while (not (looking-at todos-item-start))
      (forward-line -1))
    (point)))

(defun todos-item-end ()
  "Move to end of current Todos item and return its position."
  ;; Items cannot end with a blank line.
  (unless (looking-at "^$")
    (let* ((done (todos-done-item-p))
	   (to-lim nil)
	   ;; For todo items, end is before the done items section, for done
	   ;; items, end is before the next category.  If these limits are
	   ;; missing or inaccessible, end it before the end of the buffer.
	   (lim (if (save-excursion
		      (re-search-forward
		       (concat "^" (regexp-quote (if done
						     todos-category-beg
						   todos-category-done)))
		       nil t))
		    (progn (setq to-lim t) (match-beginning 0))
		  (point-max))))
      (when (bolp) (forward-char))	; Find start of next item.
      (goto-char (if (re-search-forward todos-item-start lim t)
		     (match-beginning 0)
		   (if to-lim lim (point-max))))
      ;; For last todo item, skip back over the empty line before the done
      ;; items section, else just back to the end of the previous line.
      (backward-char (when (and to-lim (not done) (eq (point) lim)) 2))
      (point))))

(defun todos-item-string ()
  "Return bare text of current item as a string."
  (let ((opoint (point))
	(start (todos-item-start))
	(end (todos-item-end)))
    (goto-char opoint)
    (and start end (buffer-substring-no-properties start end))))

(defun todos-remove-item ()
  "Internal function called in editing, deleting or moving items."
  (let* ((end (progn (todos-item-end) (1+ (point))))
	 (beg (todos-item-start))
	 (ov (todos-get-overlay 'prefix)))
    (when ov (delete-overlay ov))
    (delete-region beg end)))

(defun todos-diary-item-p ()
  "Return non-nil if item at point has diary entry format."
  (save-excursion
    (when (todos-item-string)		; Exclude empty lines.
      (todos-item-start)
      (not (looking-at (regexp-quote todos-nondiary-start))))))

(defun todos-done-item-p ()
  "Return non-nil if item at point is a done item."
  (save-excursion
    (todos-item-start)
    (looking-at todos-done-string-start)))

(defun todos-done-item-section-p ()
  "Return non-nil if point is in category's done items section."
  (save-excursion
    (or (re-search-backward (concat "^" (regexp-quote todos-category-done))
			    nil t)
	(progn (goto-char (point-min))
	       (looking-at todos-done-string-start)))))

(defun todos-get-overlay (val)
  "Return the overlay at point whose `todos' property has value VAL."
  ;; Use overlays-in to find prefix overlays and check over two
  ;; positions to find done separator overlay.
  (let ((ovs (overlays-in (point) (1+ (point))))
  	ov)
    (catch 'done
      (while ovs
  	(setq ov (pop ovs))
  	(when (eq (overlay-get ov 'todos) val)
  	  (throw 'done ov))))))

(defun todos-marked-item-p ()
  "Non-nil if this item begins with `todos-item-mark'.
 In that case, return the item's prefix overlay."
  ;; If a todos-item-insert command is called on a Todos file before
  ;; it is visited, it has no prefix overlays, so conditionalize:
  (let* ((ov (todos-get-overlay 'prefix))
	 (pref (when ov (overlay-get ov 'before-string)))
	 (marked (when pref
		   (string-match (concat "^" (regexp-quote todos-item-mark))
				 pref))))
    (when marked ov)))

(defun todos-insert-with-overlays (item)
  "Insert ITEM at point and update prefix/priority number overlays."
  (todos-item-start)
  ;; Insertion pushes item down but not its prefix overlay.  When the
  ;; overlay includes a mark, this would now mark the inserted ITEM,
  ;; so move it to the pushed down item.
  (let ((ov (todos-get-overlay 'prefix))
	(marked (todos-marked-item-p)))
    (insert item "\n")
    (when marked (move-overlay ov (point) (point))))
  (todos-backward-item)
  (todos-prefix-overlays))

(defun todos-prefix-overlays ()
  "Update the prefix overlays of the current category's items.
The overlay's value is the string `todos-prefix' or with non-nil
`todos-number-priorities' an integer in the sequence from 1 to
the number of todo or done items in the category indicating the
item's priority.  Todo and done items are numbered independently
of each other."
  (let ((num 0)
	(cat-tp (or (cdr (assoc-string
			  (todos-current-category)
			  (nth 2 (assoc-string todos-current-todos-file
					       todos-priorities-rules))))
		    todos-show-priorities))
	done prefix)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
	(when (or (todos-date-string-matcher (line-end-position))
		  (todos-done-string-matcher (line-end-position)))
	  (goto-char (match-beginning 0))
	  (setq num (1+ num))
	  ;; Reset number to 1 for first done item.
	  (when (and (looking-at todos-done-string-start)
		     (looking-back (concat "^"
					   (regexp-quote todos-category-done)
					   "\n")))
	    (setq num 1
		  done t))
	  (setq prefix (concat (propertize
				(if todos-number-priorities
				    (number-to-string num)
				  todos-prefix)
				'face
				;; Prefix of top priority items has a
				;; distinct face in Todos mode.
				(if (and (not done) (<= num cat-tp)
					 (eq major-mode 'todos-mode))
				    'todos-top-priority
				  'todos-prefix-string))
			       " "))
	  (let ((ov (todos-get-overlay 'prefix))
		(marked (todos-marked-item-p)))
	    ;; Prefix overlay must be at a single position so its
	    ;; bounds aren't changed when (re)moving an item.
	    (unless ov (setq ov (make-overlay (point) (point))))
	    (overlay-put ov 'todos 'prefix)
	    (overlay-put ov 'before-string (if marked
					       (concat todos-item-mark prefix)
					     prefix))))
	(forward-line)))))

;; ---------------------------------------------------------------------------
;;; Helper functions for user input with prompting and completion

(defun todos-read-file-name (prompt &optional archive mustmatch)
  "Choose and return the name of a Todos file, prompting with PROMPT.

Show completions with TAB or SPC; the names are shown in short
form but the absolute truename is returned.  With non-nil ARCHIVE
return the absolute truename of a Todos archive file.  With non-nil
MUSTMATCH the name of an existing file must be chosen;
otherwise, a new file name is allowed."
  (let* ((completion-ignore-case todos-completion-ignore-case)
	 (files (mapcar 'todos-short-file-name
			(if archive todos-archives todos-files)))
	 (file (completing-read prompt files nil mustmatch nil nil
				(unless files
				  ;; Trigger prompt for initial file.
				  ""))))
    (unless (file-exists-p todos-files-directory)
      (make-directory todos-files-directory))
    (unless mustmatch
      (setq file (todos-validate-name file 'file)))
    (setq file (file-truename (concat todos-files-directory file
				      (if archive ".toda" ".todo"))))))

(defun todos-read-category (prompt &optional match-type file)
  "Choose and return a category name, prompting with PROMPT.
Show completions for existing categories with TAB or SPC.

The argument MATCH-TYPE specifies the matching requirements on
the category name: with the value `merge' the name must complete
to that of an existing category; with the value `add' the name
must not be that of an existing category; with all other values
both existing and new valid category names are accepted.

With non-nil argument FILE prompt for a file and complete only
against categories in that file; otherwise complete against all
categories from `todos-category-completions-files'."
  ;; Allow SPC to insert spaces, for adding new category names.
  (let ((map minibuffer-local-completion-map))
    (define-key map " " nil)
    (let* ((add (eq match-type 'add))
	   (file0 (when (and file (> (length todos-files) 1))
		    (todos-read-file-name "Choose a Todos file: " nil t)))
	   (completions (unless file0 (todos-category-completions)))
	   (categories (cond (file0
			      (with-current-buffer
				  (find-file-noselect file0 'nowarn)
				(let ((todos-current-todos-file file0))
				  todos-categories)))
			     ((and add (not file))
			      (with-current-buffer
				  (find-file-noselect todos-current-todos-file)
				todos-categories))
			     (t
			      completions)))
	   (completion-ignore-case todos-completion-ignore-case)
	   (cat (completing-read prompt categories nil
				 (eq match-type 'merge) nil nil
				 ;; Unless we're adding a category via
				 ;; todos-add-category, set default
				 ;; for existing categories to the
				 ;; current category of the chosen
				 ;; file or else of the current file.
				 (if (and categories (not add))
				     (with-current-buffer
					 (find-file-noselect
					  (or file0
					      todos-current-todos-file
					      (todos-absolute-file-name
					       todos-default-todos-file)))
				       (todos-current-category))
				   ;; Trigger prompt for initial category.
				   "")))
	   (catfil (cdr (assoc cat completions)))
	   (str "Category \"%s\" from which file (TAB for choices)? "))
      ;; If we do category completion and the chosen category name
      ;; occurs in more than one file, prompt to choose one file.
      (unless (or file0 add (not catfil))
	(setq file0 (file-truename
		     (if (atom catfil)
			 catfil
		       (todos-absolute-file-name
			(completing-read (format str cat)
					 todos-category-completions-files))))))
      ;; Default to the current file.
      (unless file0 (setq file0 todos-current-todos-file))
      ;; First validate only a name passed interactively from
      ;; todos-add-category, which must be of a nonexisting category.
      (unless (and (assoc cat categories) (not add))
	;; Validate only against completion categories.
	(let ((todos-categories categories))
	  (setq cat (todos-validate-name cat 'category)))
	;; When user enters a nonexisting category name by jumping or
	;; moving, confirm that it should be added, then validate.
	(unless add
	  (if (y-or-n-p (format "Add new category \"%s\" to file \"%s\"? "
				cat (todos-short-file-name file0)))
	      (progn
		(when (assoc cat categories)
		  (let ((todos-categories categories))
		    (setq cat (todos-validate-name cat 'category))))
		;; Restore point and narrowing after adding new
		;; category, to avoid moving to beginning of file when
		;; moving marked items to a new category
		;; (todos-move-item).
		(save-excursion
		  (save-restriction
		    (todos-add-category file0 cat))))
	    ;; If we decide not to add a category, exit without returning.
	    (keyboard-quit))))
      (cons cat file0))))

(defun todos-validate-name (name type)
  "Prompt for new NAME for TYPE until it is valid, then return it.
TYPE can be either of the symbols `file' or `category'."
  (let ((categories todos-categories)
	(files (mapcar 'todos-short-file-name todos-files))
	prompt)
    (while
	(and (cond ((string= "" name)
		    (setq prompt
			  (cond ((eq type 'file)
				 (if files
				     "Enter a non-empty file name: "
				   ;; Empty string passed by todos-show to
				   ;; prompt for initial Todos file.
				   (concat "Initial file name ["
					   todos-initial-file "]: ")))
				((eq type 'category)
				 (if categories
				     "Enter a non-empty category name: "
				   ;; Empty string passed by todos-show to
				   ;; prompt for initial category of a new
				   ;; Todos file.
				   (concat "Initial category name ["
					   todos-initial-category "]: "))))))
		   ((string-match "\\`\\s-+\\'" name)
		    (setq prompt
			  "Enter a name that does not contain only white space: "))
		   ((and (eq type 'file) (member name files))
		    (setq prompt "Enter a non-existing file name: "))
		   ((and (eq type 'category) (assoc name categories))
		    (setq prompt "Enter a non-existing category name: ")))
	     (setq name (if (or (and (eq type 'file) files)
				(and (eq type 'category) categories))
			    (completing-read prompt (cond ((eq type 'file)
							   files)
							  ((eq type 'category)
							   categories)))
			  ;; Offer default initial name.
			  (completing-read prompt (if (eq type 'file)
						      files
						    categories)
					   nil nil (if (eq type 'file)
						       todos-initial-file
						     todos-initial-category))))))
    name))

;; Adapted from calendar-read-date and calendar-date-string.
(defun todos-read-date (&optional arg mo yr)
  "Prompt for Gregorian date and return it in the current format.

With non-nil ARG, prompt for and return only the date component
specified by ARG, which can be one of these symbols:
`month' (prompt for name, return name or number according to
value of `calendar-date-display-form'), `day' of month, or
`year'.  The value of each of these components can be `*',
indicating an unspecified month, day, or year.

When ARG is `day', non-nil arguments MO and YR determine the
number of the last the day of the month."
  (let (year monthname month day
	     dayname)			; Needed by calendar-date-display-form.
    (when (or (not arg) (eq arg 'year))
      (while (if (natnump year) (< year 1) (not (eq year '*)))
	(setq year (read-from-minibuffer
		    "Year (>0 or RET for this year or * for any year): "
		    nil nil t nil (number-to-string
				   (calendar-extract-year
				    (calendar-current-date)))))))
    (when (or (not arg) (eq arg 'month))
      (let* ((marray todos-month-name-array)
	     (mlist (append marray nil))
	     (mabarray todos-month-abbrev-array)
	     (mablist (append mabarray nil))
	     (completion-ignore-case todos-completion-ignore-case))
	(setq monthname (completing-read
			 "Month name (RET for current month, * for any month): "
	      		 ;; (mapcar 'list (append marray nil))
			 mlist nil t nil nil
	      		 (calendar-month-name (calendar-extract-month
	      				       (calendar-current-date)) t))
	      ;; month (cdr (assoc-string
	      ;; 		  monthname (calendar-make-alist marray nil nil
	      ;; 						 abbrevs))))))
	      month (1+ (- (length mlist)
			   (length (or (member monthname mlist)
				       (member monthname mablist))))))
	(setq monthname (aref mabarray (1- month)))))
    (when (or (not arg) (eq arg 'day))
      (let ((last (let ((mm (or month mo))
			(yy (or year yr)))
		    ;; If month is unspecified, use a month with 31
		    ;; days for checking day of month input.  Does
		    ;; Calendar do anything special when * is
		    ;; currently a shorter month?
		    (if (= mm 13) (setq mm 1))
		    ;; If year is unspecified, use a leap year to
		    ;; allow Feb. 29.
		    (if (eq year '*) (setq yy 2012))
		    (calendar-last-day-of-month mm yy))))
	(while (if (natnump day) (or (< day 1) (> day last)) (not (eq day '*)))
	  (setq day (read-from-minibuffer
		     (format "Day (1-%d or RET for today or * for any day): "
			     last)
		     nil nil t nil (number-to-string
				    (calendar-extract-day
				     (calendar-current-date))))))))
    ;; Stringify read values (monthname is already a string).
    (and year (setq year (if (eq year '*)
			     (symbol-name '*)
			   (number-to-string year))))
    (and day (setq day (if (eq day '*)
			   (symbol-name '*)
			 (number-to-string day))))
    (and month (setq month (if (eq month '*)
			       (symbol-name '*)
			     (number-to-string month))))
    (if arg
	(cond ((eq arg 'year) year)
	      ((eq arg 'day) day)
	      ((eq arg 'month)
	       (if (memq 'month calendar-date-display-form)
		   month
		 monthname)))
      (mapconcat 'eval calendar-date-display-form ""))))

(defun todos-read-dayname ()
  "Choose name of a day of the week with completion and return it."
  (let ((completion-ignore-case todos-completion-ignore-case))
    (completing-read "Enter a day name: "
		     (append calendar-day-name-array nil)
		     nil t)))
  
(defun todos-read-time ()
  "Prompt for and return a valid clock time as a string.

Valid time strings are those matching `diary-time-regexp'.
Typing `<return>' at the prompt returns the current time, if the
user option `todos-always-add-time-string' is non-nil, otherwise
the empty string (i.e., no time string)."
  (let (valid answer)
    (while (not valid)
      (setq answer (read-string "Enter a clock time: " nil nil
				(when todos-always-add-time-string
				  (substring (current-time-string) 11 16))))
      (when (or (string= "" answer)
		(string-match diary-time-regexp answer))
	(setq valid t)))
    answer))

;; ---------------------------------------------------------------------------
;;; Item filtering infrastructure

(defvar todos-multiple-filter-files nil
  "List of files selected from `todos-multiple-filter-files' widget.")

(defvar todos-multiple-filter-files-widget nil
  "Variable holding widget created by `todos-multiple-filter-files'.")

(defun todos-multiple-filter-files ()
  "Pop to a buffer with a widget for choosing multiple filter files."
  (require 'widget)
  (eval-when-compile
    (require 'wid-edit))
  (with-current-buffer (get-buffer-create "*Todos Filter Files*")
    (pop-to-buffer (current-buffer))
    (erase-buffer)
    (kill-all-local-variables)
    (widget-insert "Select files for generating the top priorities list.\n\n")
    (setq todos-multiple-filter-files-widget
	  (widget-create
	   `(set ,@(mapcar (lambda (x) (list 'const x))
			   (mapcar 'todos-short-file-name
				   (funcall todos-files-function))))))
    (widget-insert "\n")
    (widget-create 'push-button
		   :notify (lambda (widget &rest ignore)
			     (setq todos-multiple-filter-files 'quit)
			     (quit-window t)
			     (exit-recursive-edit))
		   "Cancel")
    (widget-insert "   ")
    (widget-create 'push-button
		   :notify (lambda (&rest ignore)
			     (setq todos-multiple-filter-files
				   (mapcar (lambda (f)
					     (file-truename
					      (concat todos-files-directory
						      f ".todo")))
					   (widget-value
					    todos-multiple-filter-files-widget)))
			     (quit-window t)
			     (exit-recursive-edit))
		   "Apply")
    (use-local-map widget-keymap)
    (widget-setup))
  (message "Click \"Apply\" after selecting files.")
  (recursive-edit))

(defun todos-filter-items (filter &optional new multifile)
  "Internal routine for displaying items that satisfy FILTER.
The values of FILTER can be `top' for top priority items, a cons
of `top' and a number passed by the caller, `diary' for diary
items, or `regexp' for items matching a regular expresion entered
by the user.  The items can be from any categories in the current
todo file or, with non-nil MULTIFILE, from several files.  If NEW
is nil, visit an appropriate file containing the list of filtered
items; if there is no such file, or with non-nil NEW, build the
list and display it.

See the document strings of the commands `todos-top-priorities',
`todos-diary-items', `todos-regexp-items', and those of the
corresponding multifile commands for further details. "
  (let* ((top (eq filter 'top))
	 (diary (eq filter 'diary))
	 (regexp (eq filter 'regexp))
	 (buf (cond (top todos-top-priorities-buffer)
		    (diary todos-diary-items-buffer)
		    (regexp todos-regexp-items-buffer)))
	 (flist (if multifile
		    (or todos-filter-files
			(progn (todos-multiple-filter-files)
			       todos-multiple-filter-files))
		  (list todos-current-todos-file)))
	 (multi (> (length flist) 1))
	 (fname (if (equal flist 'quit)
		    ;; Pressed `cancel' in t-m-f-f file selection dialog.
		    (keyboard-quit)
		  (concat todos-files-directory
			  (mapconcat 'todos-short-file-name flist "-")
			  (cond (top ".todt")
				(diary ".tody")
				(regexp ".todr")))))
	 (rxfiles (when regexp
		    (directory-files todos-files-directory t ".*\\.todr$" t)))
	 (file-exists (or (file-exists-p fname) rxfiles)))
    (cond ((and top new (natnump new))
	   (todos-filter-items-1 (cons 'top new) flist))
	  ((and (not new) file-exists)
	   (when (and rxfiles (> (length rxfiles) 1))
	     (let ((rxf (mapcar 'todos-short-file-name rxfiles)))
	       (setq fname (todos-absolute-file-name
			    (completing-read "Choose a regexp items file: "
					     rxf) 'regexp))))
	   (find-file fname)
	   (todos-prefix-overlays)
	   (todos-check-filtered-items-file))
	  (t
	   (todos-filter-items-1 filter flist)))
    (when (or new (not file-exists))
      (setq fname (replace-regexp-in-string "-" ", " fname))
      (rename-buffer (format (concat "%s for file" (if multi "s" "")
				   " \"%s\"") buf fname)))))

(defun todos-filter-items-1 (filter file-list)
  "Internal subroutine called by `todos-filter-items'.
The values of FILTER and FILE-LIST are passed from the caller."
  (let ((num (if (consp filter) (cdr filter) todos-show-priorities))
	(buf (get-buffer-create todos-filtered-items-buffer))
	(multifile (> (length file-list) 1))
	regexp fname bufstr cat beg end done)
    (if (null file-list)
	(error "No files have been chosen for filtering")
      (with-current-buffer buf
	(erase-buffer)
	(kill-all-local-variables)
	(todos-filtered-items-mode))
      (when (eq filter 'regexp)
	(setq regexp (read-string "Enter a regular expression: ")))
      (save-current-buffer
	(dolist (f file-list)
	  ;; Before inserting file contents into temp buffer, save a modified
	  ;; buffer visiting it.
	  (let ((bf (find-buffer-visiting f)))
	    (when (buffer-modified-p bf)
	      (with-current-buffer bf (save-buffer))))
	  (setq fname (todos-short-file-name f))
	  (with-temp-buffer
	    (when (and todos-filter-done-items (eq filter 'regexp))
	      ;; If there is a corresponding archive file for the Todos file,
	      ;; insert it first and add identifiers for todos-jump-to-item.
	      (let ((arch (concat (file-name-sans-extension f) ".toda")))
		(when (file-exists-p arch)
		  (insert-file-contents arch)
		  ;; Delete Todos archive file categories sexp.
		  (delete-region (line-beginning-position)
				 (1+ (line-end-position)))
		  (save-excursion
		    (while (not (eobp))
		      (when (re-search-forward
			     (concat (if todos-filter-done-items
					 (concat "\\(?:" todos-done-string-start
						 "\\|" todos-date-string-start
						 "\\)")
				       todos-date-string-start)
				     todos-date-pattern "\\(?: "
				     diary-time-regexp "\\)?"
				     (if todos-filter-done-items
					 "\\]"
				       (regexp-quote todos-nondiary-end)) "?")
			     nil t)
			(insert "(archive) "))
		      (forward-line))))))
	    (insert-file-contents f)
	    ;; Delete Todos file categories sexp.
	    (delete-region (line-beginning-position) (1+ (line-end-position)))
	    (let (fnum)
	      ;; Unless the number of top priorities to show was
	      ;; passed by the caller, the file-wide value from
	      ;; `todos-priorities-rules', if non-nil, overrides
	      ;; `todos-show-priorities'.
	      (unless (consp filter)
		(setq fnum (or (nth 1 (assoc f todos-priorities-rules))
			       todos-show-priorities)))
	      (while (re-search-forward
		      (concat "^" (regexp-quote todos-category-beg) "\\(.+\\)\n")
		      nil t)
		(setq cat (match-string 1))
		(let (cnum)
		  ;; Unless the number of top priorities to show was
		  ;; passed by the caller, the category-wide value
		  ;; from `todos-priorities-rules', if non-nil,
		  ;; overrides a non-nil file-wide value from
		  ;; `todos-priorities-rules' as well as
		  ;; `todos-show-priorities'.
		  (unless (consp filter)
		    (let ((cats (nth 2 (assoc f todos-priorities-rules))))
		      (setq cnum (or (cdr (assoc cat cats)) fnum))))
		  (delete-region (match-beginning 0) (match-end 0))
		  (setq beg (point))	; First item in the current category.
		  (setq end (if (re-search-forward
				 (concat "^" (regexp-quote todos-category-beg))
				 nil t)
				(match-beginning 0)
			      (point-max)))
		  (goto-char beg)
		  (setq done
			(if (re-search-forward
			     (concat "\n" (regexp-quote todos-category-done))
			     end t)
			    (match-beginning 0)
			  end))
		  (unless (and todos-filter-done-items (eq filter 'regexp))
		    ;; Leave done items.
		    (delete-region done end)
		    (setq end done))
		  (narrow-to-region beg end)	; Process only current category.
		  (goto-char (point-min))
		  ;; Apply the filter.
		  (cond ((eq filter 'diary)
			 (while (not (eobp))
			   (if (looking-at (regexp-quote todos-nondiary-start))
			       (todos-remove-item)
			     (todos-forward-item))))
			((eq filter 'regexp)
			 (while (not (eobp))
			   (if (looking-at todos-item-start)
			       (if (string-match regexp (todos-item-string))
				   (todos-forward-item)
				 (todos-remove-item))
			     ;; Kill lines that aren't part of a todo or done
			     ;; item (empty or todos-category-done).
			     (delete-region (line-beginning-position)
					    (1+ (line-end-position))))
			   ;; If last todo item in file matches regexp and
			   ;; there are no following done items,
			   ;; todos-category-done string is left dangling,
			   ;; because todos-forward-item jumps over it.
			   (if (and (eobp)
				    (looking-back
				     (concat (regexp-quote todos-done-string)
					     "\n")))
			       (delete-region (point) (progn
							(forward-line -2)
							(point))))))
			(t ; Filter top priority items.
			 (setq num (or cnum fnum num))
			 (unless (zerop num)
			   (todos-forward-item num))))
		  (setq beg (point))
		  ;; Delete non-top-priority items.
		  (unless (member filter '(diary regexp))
		    (delete-region beg end))
		  (goto-char (point-min))
		  ;; Add file (if using multiple files) and category tags to
		  ;; item.
		  (while (not (eobp))
		    (when (re-search-forward
			   (concat (if todos-filter-done-items
				       (concat "\\(?:" todos-done-string-start
					       "\\|" todos-date-string-start
					       "\\)")
				     todos-date-string-start)
				   todos-date-pattern "\\(?: " diary-time-regexp
				   "\\)?" (if todos-filter-done-items
					      "\\]"
					    (regexp-quote todos-nondiary-end))
				   "?")
			   nil t)
		      (insert " [")
		      (when (looking-at "(archive) ") (goto-char (match-end 0)))
		      (insert (if multifile (concat fname ":") "") cat "]"))
		    (forward-line))
		  (widen)))
		(setq bufstr (buffer-string))
		(with-current-buffer buf
		  (let (buffer-read-only)
		    (insert bufstr)))))))
      (set-window-buffer (selected-window) (set-buffer buf))
      (todos-prefix-overlays)
      (goto-char (point-min)))))

(defun todos-set-top-priorities (&optional arg)
  "Set number of top priorities shown by `todos-top-priorities'.
With non-nil ARG, set the number only for the current Todos
category; otherwise, set the number for all categories in the
current Todos file.

Calling this function via either of the commands
`todos-set-top-priorities-in-file' or
`todos-set-top-priorities-in-category' is the recommended way to
set the user customizable option `todos-priorities-rules'."
  (let* ((cat (todos-current-category))
	 (file todos-current-todos-file)
	 (rules todos-priorities-rules)
	 (frule (assoc-string file rules))
	 (crule (assoc-string cat (nth 2 frule)))
	 (crules (nth 2 frule))
	 (cur (or (if arg (cdr crule) (nth 1 frule))
		  todos-show-priorities))
	 (prompt (if arg (concat "Number of top priorities in this category"
				 " (currently %d): ")
		   (concat "Default number of top priorities per category"
				 " in this file (currently %d): ")))
	 (new -1)
	 nrule)
    (while (< new 0)
      (let ((cur0 cur))
	(setq new (read-number (format prompt cur0))
	      prompt "Enter a non-negative number: "
	      cur0 nil)))
    (setq nrule (if arg
		    (append (delete crule crules) (list (cons cat new)))
		  (append (list file new) (list crules))))
    (setq rules (cons (if arg
			  (list file cur nrule)
			nrule)
		      (delete frule rules)))
    (customize-save-variable 'todos-priorities-rules rules)
    (todos-prefix-overlays)))

(defconst todos-filtered-items-buffer "Todos filtered items"
  "Initial name of buffer in Todos Filter Items mode.")

(defconst todos-top-priorities-buffer "Todos top priorities"
  "Buffer type string for `todos-filter-items'.")

(defconst todos-diary-items-buffer "Todos diary items"
  "Buffer type string for `todos-filter-items'.")

(defconst todos-regexp-items-buffer "Todos regexp items"
  "Buffer type string for `todos-filter-items'.")

(defun todos-find-item (str)
  "Search for filtered item STR in its saved Todos file.
Return the list (FOUND FILE CAT), where CAT and FILE are the
item's category and file, and FOUND is a cons cell if the search
succeeds, whose car is the start of the item in FILE and whose
cdr is `done', if the item is now a done item, `changed', if its
text was truncated or augmented or, for a top priority item, if
its priority has changed, and `same' otherwise."
  (string-match (concat (if todos-filter-done-items
			    (concat "\\(?:" todos-done-string-start "\\|"
				    todos-date-string-start "\\)")
			  todos-date-string-start)
			todos-date-pattern "\\(?: " diary-time-regexp "\\)?"
			(if todos-filter-done-items
			    "\\]"
			  (regexp-quote todos-nondiary-end)) "?"
			"\\(?4: \\[\\(?3:(archive) \\)?\\(?2:.*:\\)?"
			"\\(?1:.*\\)\\]\\).*$") str)
  (let ((cat (match-string 1 str))
	(file (match-string 2 str))
	(archive (string= (match-string 3 str) "(archive) "))
	(filcat (match-string 4 str))
	(tpriority 1)
	(tpbuf (string-match "top" (buffer-name)))
	found)
    (setq str (replace-match "" nil nil str 4))
    (when tpbuf
      ;; Calculate priority of STR wrt its category.
      (save-excursion
	(while (search-backward filcat nil t)
	    (setq tpriority (1+ tpriority)))))
    (setq file (if file
		   (concat todos-files-directory (substring file 0 -1)
			   (if archive ".toda" ".todo"))
		 (if archive
		     (concat (file-name-sans-extension
			      todos-global-current-todos-file) ".toda")
		   todos-global-current-todos-file)))
    (find-file-noselect file)
    (with-current-buffer (find-buffer-visiting file)
      (save-restriction
	(widen)
	(goto-char (point-min))
	(let ((beg (re-search-forward
		    (concat "^" (regexp-quote (concat todos-category-beg cat))
			    "$")
		    nil t))
	      (done (save-excursion
		      (re-search-forward
		       (concat "^" (regexp-quote todos-category-done)) nil t)))
	      (end (save-excursion
		     (or (re-search-forward
			  (concat "^" (regexp-quote todos-category-beg))
			  nil t)
			 (point-max)))))
	  (setq found (when (search-forward str end t)
			(goto-char (match-beginning 0))))
	  (when found
	    (setq found
		  (cons found (if (> (point) done)
				  'done
				(let ((cpriority 1))
				  (when tpbuf
				    (save-excursion
				      ;; Not top item in category.
				      (while (> (point) (1+ beg))
					(let ((opoint (point)))
					  (todos-backward-item)
					  ;; Can't move backward beyond
					  ;; first item in file.
					  (unless (= (point) opoint)
					    (setq cpriority (1+ cpriority)))))))
				  (if (and (= tpriority cpriority)
					   ;; Proper substring is not the same.
					   (string= (todos-item-string)
						    str))
				      'same
				    'changed)))))))))
      (list found file cat)))

(defun todos-check-filtered-items-file ()
  "Check if filtered items file is up to date and a show suitable message."
  ;; (catch 'old
  (let ((count 0))
    (while (not (eobp))
      (let* ((item (todos-item-string))
	     (found (car (todos-find-item item))))
	(unless (eq (cdr found) 'same)
	  (save-excursion
	    (overlay-put (make-overlay (todos-item-start) (todos-item-end))
			 'face 'todos-search))
	  (setq count (1+ count))))
	  ;; (throw 'old (message "The marked item is not up to date.")))
      (todos-forward-item))
    (if (zerop count)
	(message "Filtered items file is up to date.")
      (message (concat "The highlighted item" (if (= count 1) " is " "s are ")
		       "not up to date."
		       ;; "\nType <return> on item for details."
		       )))))

(defun todos-filter-items-filename ()
  "Return absolute file name for saving this Filtered Items buffer."
  (let ((bufname (buffer-name)))
    (string-match "\"\\([^\"]+\\)\"" bufname)
    (let* ((filename-str (substring bufname (match-beginning 1) (match-end 1)))
	   (filename-base (replace-regexp-in-string ", " "-" filename-str))
	   (top-priorities (string-match "top priorities" bufname))
	   (diary-items (string-match "diary items" bufname))
	   (regexp-items (string-match "regexp items" bufname)))
      (when regexp-items
	(let ((prompt (concat "Enter a short identifying string"
			      " to make this file name unique: ")))
	  (setq filename-base (concat filename-base "-" (read-string prompt)))))
      (concat todos-files-directory filename-base
	      (cond (top-priorities ".todt")
		    (diary-items ".tody")
		    (regexp-items ".todr"))))))

(defun todos-save-filtered-items-buffer ()
  "Save current Filtered Items buffer to a file.
If the file already exists, overwrite it only on confirmation."
  (let ((filename (or (buffer-file-name) (todos-filter-items-filename))))
    (write-file filename t)))

;; ---------------------------------------------------------------------------
;;; Sorting and display routines for Todos Categories mode.

(defun todos-longest-category-name-length (categories)
  "Return the length of the longest name in list CATEGORIES."
  (let ((longest 0))
    (dolist (c categories longest)
      (setq longest (max longest (length c))))))

(defun todos-adjusted-category-label-length ()
  "Return adjusted length of category label button.
The adjustment ensures proper tabular alignment in Todos
Categories mode."
  (let* ((categories (mapcar 'car todos-categories))
	 (longest (todos-longest-category-name-length categories))
	 (catlablen (length todos-categories-category-label))
	 (lc-diff (- longest catlablen)))
    (if (and (natnump lc-diff)
	     (eq (logand lc-diff 1) 1))	; oddp from cl.el
	(1+ longest)
      (max longest catlablen))))

(defun todos-padded-string (str)
  "Return category name or label string STR padded with spaces.
The placement of the padding is determined by the value of user
option `todos-categories-align'."
  (let* ((len (todos-adjusted-category-label-length))
	 (strlen (length str))
	 (strlen-odd (eq (logand strlen 1) 1))
	 (padding (max 0 (/ (- len strlen) 2)))
	 (padding-left (cond ((eq todos-categories-align 'left) 0)
			     ((eq todos-categories-align 'center) padding)
			     ((eq todos-categories-align 'right)
			      (if strlen-odd (1+ (* padding 2)) (* padding 2)))))
	 (padding-right (cond ((eq todos-categories-align 'left)
			       (if strlen-odd (1+ (* padding 2)) (* padding 2)))
			      ((eq todos-categories-align 'center)
			       (if strlen-odd (1+ padding) padding))
			      ((eq todos-categories-align 'right) 0))))
    (concat (make-string padding-left 32) str (make-string padding-right 32))))

(defvar todos-descending-counts nil
  "List of keys for category counts sorted in descending order.")

(defun todos-sort (list &optional key)
  "Return a copy of LIST, possibly sorted according to KEY."
  (let* ((l (copy-sequence list))
	 (fn (if (eq key 'alpha)
		   (lambda (x) (upcase x)) ; Alphabetize case insensitively.
		 (lambda (x) (todos-get-count key x))))
	 ;; Keep track of whether the last sort by key was descending or
	 ;; ascending.
	 (descending (member key todos-descending-counts))
	 (cmp (if (eq key 'alpha)
		  'string<
		(if descending '< '>)))
	 (pred (lambda (s1 s2) (let ((t1 (funcall fn (car s1)))
				     (t2 (funcall fn (car s2))))
				 (funcall cmp t1 t2)))))
    (when key
      (setq l (sort l pred))
      ;; Switch between descending and ascending sort order.
      (if descending
	  (setq todos-descending-counts
		(delete key todos-descending-counts))
	(push key todos-descending-counts)))
    l))

(defun todos-display-sorted (type)
  "Keep point on the TYPE count sorting button just clicked."
  (let ((opoint (point)))
    (todos-update-categories-display type)
    (goto-char opoint)))

(defun todos-label-to-key (label)
  "Return symbol for sort key associated with LABEL."
  (let (key)
    (cond ((string= label todos-categories-category-label)
	   (setq key 'alpha))
	  ((string= label todos-categories-todo-label)
	   (setq key 'todo))
	  ((string= label todos-categories-diary-label)
	   (setq key 'diary))
	  ((string= label todos-categories-done-label)
	   (setq key 'done))
	  ((string= label todos-categories-archived-label)
	   (setq key 'archived)))
    key))

(defun todos-insert-sort-button (label)
  "Insert button for displaying categories sorted by item counts.
LABEL determines which type of count is sorted."
  (setq str (if (string= label todos-categories-category-label)
		(todos-padded-string label)
	      label))
  (setq beg (point))
  (setq end (+ beg (length str)))
  (insert-button str 'face nil
		 'action
		 `(lambda (button)
		    (let ((key (todos-label-to-key ,label)))
		      (if (and (member key todos-descending-counts)
			       (eq key 'alpha))
			  (progn
			    ;; If display is alphabetical, switch back to
			    ;; category priority order.
			    (todos-display-sorted nil)
			    (setq todos-descending-counts
				  (delete key todos-descending-counts)))
			(todos-display-sorted key)))))
  (setq ovl (make-overlay beg end))
  (overlay-put ovl 'face 'todos-button))

(defun todos-total-item-counts ()
  "Return a list of total item counts for the current file."
  (mapcar (lambda (i) (apply '+ (mapcar (lambda (l) (aref l i))
					(mapcar 'cdr todos-categories))))
	  (list 0 1 2 3)))

(defvar todos-categories-category-number 0
  "Variable for numbering categories in Todos Categories mode.")

(defun todos-insert-category-line (cat &optional nonum)
  "Insert button with category CAT's name and item counts.
With non-nil argument NONUM show only these; otherwise, insert a
number in front of the button indicating the category's priority.
The number and the category name are separated by the string
which is the value of the user option
`todos-categories-number-separator'."
  (let ((archive (member todos-current-todos-file todos-archives))
	(num todos-categories-category-number)
	(str (todos-padded-string cat))
	(opoint (point)))
    (setq num (1+ num) todos-categories-category-number num)
    (insert-button
     (concat (if nonum
		 (make-string (+ 4 (length todos-categories-number-separator))
			      32)
	       (format " %3d%s" num todos-categories-number-separator))
	     str
	     (mapconcat (lambda (elt)
			  (concat
			   (make-string (1+ (/ (length (car elt)) 2)) 32) ; label
			   (format "%3d" (todos-get-count (cdr elt) cat)) ; count
			   ;; Add an extra space if label length is odd
			   ;; (using def of oddp from cl.el).
			   (if (eq (logand (length (car elt)) 1) 1) " ")))
			(if archive
			    (list (cons todos-categories-done-label 'done))
			  (list (cons todos-categories-todo-label 'todo)
				(cons todos-categories-diary-label 'diary)
				(cons todos-categories-done-label 'done)
				(cons todos-categories-archived-label
				      'archived)))
			  "")
	     " ") ; So highlighting of last column is consistent with the others.
     'face (if (and todos-skip-archived-categories
		    (zerop (todos-get-count 'todo cat))
		    (zerop (todos-get-count 'done cat))
		    (not (zerop (todos-get-count 'archived cat))))
	       'todos-archived-only
	     nil)
     'action `(lambda (button) (let ((buf (current-buffer)))
				 (todos-jump-to-category nil ,cat)
				 (kill-buffer buf))))
    ;; Highlight the sorted count column.
    (let* ((beg (+ opoint 7 (length str)))
	   end ovl)
      (cond ((eq nonum 'todo)
	     (setq beg (+ beg 1 (/ (length todos-categories-todo-label) 2))))
	    ((eq nonum 'diary)
	     (setq beg (+ beg 1 (length todos-categories-todo-label)
			   2 (/ (length todos-categories-diary-label) 2))))
	    ((eq nonum 'done)
	     (setq beg (+ beg 1 (length todos-categories-todo-label)
			   2 (length todos-categories-diary-label)
			   2 (/ (length todos-categories-done-label) 2))))
	    ((eq nonum 'archived)
	     (setq beg (+ beg 1 (length todos-categories-todo-label)
			   2 (length todos-categories-diary-label)
			   2 (length todos-categories-done-label)
			   2 (/ (length todos-categories-archived-label) 2)))))
      (unless (= beg (+ opoint 7 (length str))) ; Don't highlight categories.
	(setq end (+ beg 4))
	(setq ovl (make-overlay beg end))
	(overlay-put ovl 'face 'todos-sorted-column)))
    (newline)))

(defun todos-display-categories-1 ()
  "Prepare buffer for displaying table of categories and item counts."
  (unless (eq major-mode 'todos-categories-mode)
    (setq todos-global-current-todos-file
	  (or todos-current-todos-file
	      (todos-absolute-file-name todos-default-todos-file)))
    (set-window-buffer (selected-window)
		       (set-buffer (get-buffer-create todos-categories-buffer)))
    (kill-all-local-variables)
    (todos-categories-mode)
    (let ((archive (member todos-current-todos-file todos-archives))
	  buffer-read-only) 
      (erase-buffer)
      (insert (format (concat "Category counts for Todos "
			      (if archive "archive" "file")
			      " \"%s\".")
		      (todos-short-file-name todos-current-todos-file)))
      (newline 2)
      ;; Make space for the column of category numbers.
      (insert (make-string (+ 4 (length todos-categories-number-separator)) 32))
      ;; Add the category and item count buttons (if this is the list of
      ;; categories in an archive, show only done item counts).
      (todos-insert-sort-button todos-categories-category-label)
      (if archive
	  (progn
	    (insert (make-string 3 32))
	    (todos-insert-sort-button todos-categories-done-label))
	(insert (make-string 3 32))
	(todos-insert-sort-button todos-categories-todo-label)
	(insert (make-string 2 32))
	(todos-insert-sort-button todos-categories-diary-label)
	(insert (make-string 2 32))
	(todos-insert-sort-button todos-categories-done-label)
	(insert (make-string 2 32))
	(todos-insert-sort-button todos-categories-archived-label))
      (newline 2))))

(defun todos-update-categories-display (sortkey)
  ""
  (let* ((cats0 todos-categories)
	 (cats (todos-sort cats0 sortkey))
	 (archive (member todos-current-todos-file todos-archives))
	 (todos-categories-category-number 0)
	 ;; Find start of Category button if we just entered Todos Categories
	 ;; mode.
	 (pt (if (eq (point) (point-max))
		 (save-excursion
		   (forward-line -2)
		   (goto-char (next-single-char-property-change
			       (point) 'face nil (line-end-position))))))
	 (buffer-read-only))
    (forward-line 2)
    (delete-region (point) (point-max))
    ;; Fill in the table with buttonized lines, each showing a category and
    ;; its item counts.
    (mapc (lambda (cat) (todos-insert-category-line cat sortkey))
	  (mapcar 'car cats))
    (newline)
    ;; Add a line showing item count totals.
    (insert (make-string (+ 4 (length todos-categories-number-separator)) 32)
	    (todos-padded-string todos-categories-totals-label)
	    (mapconcat
	     (lambda (elt)
	       (concat
		(make-string (1+ (/ (length (car elt)) 2)) 32)
		(format "%3d" (nth (cdr elt) (todos-total-item-counts)))
		;; Add an extra space if label length is odd (using
		;; definition of oddp from cl.el).
		(if (eq (logand (length (car elt)) 1) 1) " ")))
	     (if archive
		 (list (cons todos-categories-done-label 2))
	       (list (cons todos-categories-todo-label 0)
		     (cons todos-categories-diary-label 1)
		     (cons todos-categories-done-label 2)
		     (cons todos-categories-archived-label 3)))
	     ""))
    ;; Put cursor on Category button initially.
    (if pt (goto-char pt))
    (setq buffer-read-only t)))

;; ---------------------------------------------------------------------------
;;; Routines for generating Todos insertion commands and key bindings

;; Can either of these be included in Emacs?  The originals are GFDL'd.

;; Slightly reformulated from
;; http://rosettacode.org/wiki/Power_set#Common_Lisp.
(defun powerset-recursive (l)
  (cond ((null l)
	 (list nil))
	(t
	 (let ((prev (powerset-recursive (cdr l))))
	   (append (mapcar (lambda (elt) (cons (car l) elt))
			   prev)
		   prev)))))

;; Elisp implementation of http://rosettacode.org/wiki/Power_set#C
(defun powerset-bitwise (l)
  (let ((binnum (lsh 1 (length l)))
	 pset elt)
    (dotimes (i binnum)
      (let ((bits i)
	    (ll l))
	(while (not (zerop bits))
	  (let ((arg (pop ll)))
	    (unless (zerop (logand bits 1))
	      (setq elt (append elt (list arg))))
	    (setq bits (lsh bits -1))))
	(setq pset (append pset (list elt)))
	(setq elt nil)))
    pset))

;; (defalias 'todos-powerset 'powerset-recursive)
(defalias 'todos-powerset 'powerset-bitwise)

;; Return list of lists of non-nil atoms produced from ARGLIST.  The elements
;; of ARGLIST may be atoms or lists.
(defun todos-gen-arglists (arglist)
  (let (arglists)
    (while arglist
      (let ((arg (pop arglist)))
	(cond ((symbolp arg)
	       (setq arglists (if arglists
				  (mapcar (lambda (l) (push arg l)) arglists)
				(list (push arg arglists)))))
	      ((listp arg)
	       (setq arglists
		     (mapcar (lambda (a)
			       (if (= 1 (length arglists))
				   (apply (lambda (l) (push a l)) arglists)
				 (mapcar (lambda (l) (push a l)) arglists)))
			     arg))))))
    (setq arglists (mapcar 'reverse (apply 'append (mapc 'car arglists))))))

(defvar todos-insertion-commands-args-genlist
  '(diary nonmarking (calendar date dayname) time (here region))
  "Generator list for argument lists of Todos insertion commands.")

(defvar todos-insertion-commands-args
  (let ((argslist (todos-gen-arglists todos-insertion-commands-args-genlist))
	res new)
    (setq res (remove-duplicates
	       (apply 'append (mapcar 'todos-powerset argslist)) :test 'equal))
    (dolist (l res)
      (unless (= 5 (length l))
	(let ((v (make-vector 5 nil)) elt)
	  (while l
	    (setq elt (pop l))
	    (cond ((eq elt 'diary)
		   (aset v 0 elt))
		  ((eq elt 'nonmarking)
		   (aset v 1 elt))
		  ((or (eq elt 'calendar)
		       (eq elt 'date)
		       (eq elt 'dayname))
		   (aset v 2 elt))
		  ((eq elt 'time)
		   (aset v 3 elt))
		  ((or (eq elt 'here)
		       (eq elt 'region))
		   (aset v 4 elt))))
	  (setq l (append v nil))))
      (setq new (append new (list l))))
    new)
  "List of all argument lists for Todos insertion commands.")

(defun todos-insertion-command-name (arglist)
  "Generate Todos insertion command name from ARGLIST."
  (replace-regexp-in-string
   "-\\_>" ""
   (replace-regexp-in-string
    "-+" "-"
    (concat "todos-item-insert-"
    ;; (concat "todos-insert-item-"
	    (mapconcat (lambda (e) (if e (symbol-name e))) arglist "-")))))

(defvar todos-insertion-commands-names
  (mapcar (lambda (l)
	   (todos-insertion-command-name l))
	  todos-insertion-commands-args)
  "List of names of Todos insertion commands.")

(defmacro todos-define-insertion-command (&rest args)
  (let ((name (intern (todos-insertion-command-name args)))
	(arg0 (nth 0 args))
	(arg1 (nth 1 args))
	(arg2 (nth 2 args))
	(arg3 (nth 3 args))
	(arg4 (nth 4 args)))
    `(defun ,name (&optional arg &rest args)
       "Todos item insertion command generated from ARGS."
       (interactive (list current-prefix-arg))
       (todos-insert-item arg ',arg0 ',arg1 ',arg2 ',arg3 ',arg4))))

(defvar todos-insertion-commands
  (mapcar (lambda (c)
	    (eval `(todos-define-insertion-command ,@c)))
	  todos-insertion-commands-args)
  "List of Todos insertion commands.")

(defvar todos-insertion-commands-arg-key-list
  '(("diary" "y" "yy")
    ("nonmarking" "k" "kk")
    ("calendar" "c" "cc")
    ("date" "d" "dd")
    ("dayname" "n" "nn")
    ("time" "t" "tt")
    ("here" "h" "h")
    ("region" "r" "r"))
  "")    

(defun todos-insertion-key-bindings (map)
  ""
  (dolist (c todos-insertion-commands)
    (let* ((key "")
	   (cname (symbol-name c)))
      (mapc (lambda (l)
	      (let ((arg (nth 0 l))
		    (key1 (nth 1 l))
		    (key2 (nth 2 l)))
		(if (string-match (concat (regexp-quote arg) "\\_>") cname)
		    (setq key (concat key key2)))
		(if (string-match (concat (regexp-quote arg) ".+") cname)
		    (setq key (concat key key1)))))
	    todos-insertion-commands-arg-key-list)
      (if (string-match (concat (regexp-quote "todos-item-insert") "\\_>") cname)
      ;; (if (string-match (concat (regexp-quote "todos-insert-item") "\\_>") cname)
	  (setq key (concat key "i")))
      (define-key map key c))))

(defvar todos-insertion-map
  (let ((map (make-keymap)))
    (todos-insertion-key-bindings map)
    (define-key map "p" 'todos-copy-item)
    map)
  "Keymap for Todos mode insertion commands.")

;; ---------------------------------------------------------------------------
;;; Key maps and menus

(defvar todos-key-bindings
  `(
    ;;               display
    ("Cd"	     . todos-display-categories) ;FIXME: Fc todos-file-categories?
    ("H"	     . todos-highlight-item)
    ("N"	     . todos-hide-show-item-numbering)
    ("D"	     . todos-hide-show-date-time)
    ("*"	     . todos-mark-unmark-item)
    ("C*"	     . todos-mark-category)
    ("Cu"	     . todos-unmark-category)
    ("PP"	     . todos-print)
    ("PF"	     . todos-print-to-file)
    ("v"	     . todos-hide-show-done-items)
    ("V"	     . todos-show-done-only)
    ("As"	     . todos-show-archive)
    ("Ac"	     . todos-choose-archive)
    ;; ("Y"	     . todos-diary-items)
    ("Fe"	     . todos-edit-multiline)
    ("Fh"	     . todos-highlight-item)
    ("Fn"	     . todos-hide-show-item-numbering)
    ("Fd"	     . todos-hide-show-date-time)
    ("Ftt"	     . todos-top-priorities)
    ("Ftm"	     . todos-top-priorities-multifile)
    ("Fts"	     . todos-set-top-priorities-in-file)
    ("Cts"	     . todos-set-top-priorities-in-category)
    ("Fyy"	     . todos-diary-items)
    ("Fym"	     . todos-diary-items-multifile)
    ("Fxx"	     . todos-regexp-items)
    ("Fxm"	     . todos-regexp-items-multifile)
    ;;               navigation		        
    ("f"	     . todos-forward-category)
    ("b"	     . todos-backward-category)
    ("t"             . todos-show)
    ("j"	     . todos-jump-to-category)
    ("n"	     . todos-forward-item)
    ("p"	     . todos-backward-item)
    ("S"	     . todos-search)
    ("X"	     . todos-clear-matches)
    ;;               editing			        
    ("Fa"	     . todos-add-file)
    ("Ca"	     . todos-add-category)
    ("Cr"	     . todos-rename-category)
    ("Cg"	     . todos-merge-category)
    ("Cm"	     . todos-move-category)
    ("Ck"	     . todos-delete-category)
    ("d"	     . todos-item-done)
    ("ee"	     . todos-edit-item)
    ("em"	     . todos-edit-multiline-item)
    ("eh"	     . todos-edit-item-header)
    ("edc"	     . todos-edit-item-date-from-calendar)
    ("edt"	     . todos-edit-item-date-to-today)
    ("edn"	     . todos-edit-item-date-day-name)
    ("edy"	     . todos-edit-item-date-year)
    ("edm"	     . todos-edit-item-date-month)
    ("edd"	     . todos-edit-item-date-day)
    ("et"	     . todos-edit-item-time)
    ("eyy"	     . todos-edit-item-diary-inclusion)
    ;; (""	     . todos-edit-category-diary-inclusion)
    ("eyn"	     . todos-edit-item-diary-nonmarking)
    ;;(""	     . todos-edit-category-diary-nonmarking)
    ("ec"	     . todos-done-item-add-edit-or-delete-comment)
    ("i"	     . ,todos-insertion-map)
    ("k"	     . todos-delete-item) ;FIXME: not single letter?
    ("m"	     . todos-move-item)
    ("r"	     . todos-raise-item-priority)
    ("l"	     . todos-lower-item-priority)
    ("#"	     . todos-set-item-priority)
    ("u"	     . todos-item-undo)
    ("Ad"	     . todos-archive-done-item)  ;FIXME: ad
    ("AD"	     . todos-archive-category-done-items) ;FIXME: aD or C-u ad ?
    ("s"	     . todos-save)
    ("q"	     . todos-quit)
    ([remap newline] . newline-and-indent)
   )
  "Alist pairing keys defined in Todos modes and their bindings.")

(defvar todos-mode-map
  (let ((map (make-keymap)))
    ;; Don't suppress digit keys, so they can supply prefix arguments.
    (suppress-keymap map)
    (dolist (ck todos-key-bindings)
      (define-key map (car ck) (cdr ck)))
    map)
  "Todos mode keymap.")

(easy-menu-define
  todos-menu todos-mode-map "Todos Menu"
  '("Todos"
    ("Navigation"
     ["Next Item"            todos-forward-item t]
     ["Previous Item"        todos-backward-item t]
     "---"
     ["Next Category"        todos-forward-category t]
     ["Previous Category"    todos-backward-category t]
     ["Jump to Category"     todos-jump-to-category t]
     "---"
     ["Search Todos File"    todos-search t]
     ["Clear Highlighting on Search Matches" todos-category-done t])
    ("Display"
     ["List Current Categories" todos-display-categories t]
     ;; ["List Categories Alphabetically" todos-display-categories-alphabetically t]
     ["Turn Item Highlighting on/off" todos-highlight-item t]
     ["Turn Item Numbering on/off" todos-hide-show-item-numbering t]
     ["Turn Item Time Stamp on/off" todos-hide-show-date-time t]
     ["View/Hide Done Items" todos-hide-show-done-items t]
     "---"
     ["View Diary Items" todos-diary-items t]
     ["View Top Priority Items" todos-top-priorities t]
     ["View Multifile Top Priority Items" todos-top-priorities-multifile t]
     "---"
     ["Print Category"     todos-print t])
    ("Editing"
     ["Insert New Item"      todos-insert-item t]
     ["Insert Item Here"     todos-insert-item-here t]
     ("More Insertion Commands")
     ["Edit Item"            todos-edit-item t]
     ["Edit Multiline Item"  todos-edit-multiline t]
     ["Edit Item Header"     todos-edit-item-header t]
     ["Edit Item Date"       todos-edit-item-date t]
     ["Edit Item Time"       todos-edit-item-time t]
     "---"
     ["Lower Item Priority"  todos-lower-item-priority t]
     ["Raise Item Priority"  todos-raise-item-priority t]
     ["Set Item Priority" todos-set-item-priority t]
     ["Move (Recategorize) Item" todos-move-item t]
     ["Delete Item"          todos-delete-item t]
     ["Undo Done Item" todos-item-undo t]
     ["Mark/Unmark Item for Diary" todos-toggle-item-diary-inclusion t]
     ["Mark/Unmark Items for Diary" todos-edit-item-diary-inclusion t]
     ["Mark & Hide Done Item" todos-item-done t]
     ["Archive Done Items" todos-archive-category-done-items t]
     "---"
     ["Add New Todos File" todos-add-file t]
     ["Add New Category" todos-add-category t]
     ["Delete Current Category" todos-delete-category t]
     ["Rename Current Category" todos-rename-category t]
     "---"
     ["Save Todos File"      todos-save t]
     )
    "---"
    ["Quit"                 todos-quit t]
    ))

(defvar todos-archive-mode-map
  (let ((map (make-sparse-keymap)))
    (suppress-keymap map t)
    ;; navigation commands
    (define-key map "f" 'todos-forward-category)
    (define-key map "b" 'todos-backward-category)
    (define-key map "j" 'todos-jump-to-category)
    (define-key map "n" 'todos-forward-item)
    (define-key map "p" 'todos-backward-item)
    ;; display commands
    (define-key map "Cd" 'todos-display-categories)
    (define-key map "H" 'todos-highlight-item)
    (define-key map "N" 'todos-hide-show-item-numbering)
    (define-key map "*"	'todos-mark-unmark-item)
    (define-key map "C*" 'todos-mark-category)
    (define-key map "Cu" 'todos-unmark-category)
    ;; (define-key map "" 'todos-hide-show-date-time)
    (define-key map "P" 'todos-print)
    (define-key map "q" 'todos-quit)
    (define-key map "s" 'todos-save)
    (define-key map "S" 'todos-search)
    (define-key map "t" 'todos-show)
    (define-key map "u" 'todos-unarchive-items)
    map)
  "Todos Archive mode keymap.")

(defvar todos-edit-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "\C-x\C-q" 'todos-edit-quit)
    (define-key map [remap newline] 'newline-and-indent)
    map)
  "Todos Edit mode keymap.")

(defvar todos-categories-mode-map
  (let ((map (make-sparse-keymap)))
    (suppress-keymap map t)
    ;; (define-key map "c" 'todos-display-categories-numberically-or-alphabetically)
    (define-key map "c" 'todos-display-categories-alphabetically-or-by-priority)
    (define-key map "t" 'todos-display-categories-sorted-by-todo)
    (define-key map "y" 'todos-display-categories-sorted-by-diary)
    (define-key map "d" 'todos-display-categories-sorted-by-done)
    (define-key map "a" 'todos-display-categories-sorted-by-archived)
    (define-key map "#" 'todos-set-category-priority)
    (define-key map "l" 'todos-lower-category-priority)
    (define-key map "+" 'todos-lower-category-priority)
    (define-key map "r" 'todos-raise-category-priority)
    (define-key map "-" 'todos-raise-category-priority)
    (define-key map "n" 'todos-forward-button) ; todos-next-button
    (define-key map "p" 'todos-backward-button) ; todos-previous-button
    (define-key map [tab] 'todos-forward-button)
    (define-key map [backtab] 'todos-backward-button)
    (define-key map "q" 'todos-quit)
    ;; (define-key map "A" 'todos-add-category)
    ;; (define-key map "D" 'todos-delete-category)
    ;; (define-key map "R" 'todos-rename-category)
    map)
  "Todos Categories mode keymap.")

(defvar todos-filtered-items-mode-map
  (let ((map (make-keymap)))
    (suppress-keymap map t)
    ;; navigation commands
    (define-key map "j" 'todos-jump-to-item)
    (define-key map [remap newline] 'todos-jump-to-item)
    (define-key map "n" 'todos-forward-item)
    (define-key map "p" 'todos-backward-item)
    (define-key map "H" 'todos-highlight-item)
    (define-key map "N" 'todos-hide-show-item-numbering)
    (define-key map "D" 'todos-hide-show-date-time)
    (define-key map "P" 'todos-print)
    (define-key map "q" 'todos-quit)
    (define-key map "s" 'todos-save)
    ;; editing commands
    (define-key map "l" 'todos-lower-item-priority)
    (define-key map "r" 'todos-raise-item-priority)
    (define-key map "#" 'todos-set-item-priority)
    map)
  "Todos Top Priorities mode keymap.")

;; ---------------------------------------------------------------------------
;;; Mode definitions

(defun todos-modes-set-1 ()
  ""
  (set (make-local-variable 'font-lock-defaults) '(todos-font-lock-keywords t))
  (set (make-local-variable 'indent-line-function) 'todos-indent)
  (when todos-wrap-lines (funcall todos-line-wrapping-function)))

(defun todos-modes-set-2 ()
  ""
  (add-to-invisibility-spec 'todos)
  (setq buffer-read-only t)
  (set (make-local-variable 'hl-line-range-function)
       (lambda() (when (todos-item-end)
		   (cons (todos-item-start) (todos-item-end))))))

(defun todos-modes-set-3 ()
  ""
  (set (make-local-variable 'todos-categories) (todos-set-categories))
  (set (make-local-variable 'todos-category-number) 1)
  (add-hook 'find-file-hook 'todos-display-as-todos-file nil t))

(put 'todos-mode 'mode-class 'special)

(define-derived-mode todos-mode special-mode "Todos"
  "Major mode for displaying, navigating and editing Todo lists.

\\{todos-mode-map}"
  (easy-menu-add todos-menu)
  (todos-modes-set-1)
  (todos-modes-set-2)
  (todos-modes-set-3)
  ;; Initialize todos-current-todos-file.
  (when (member (file-truename (buffer-file-name))
		(funcall todos-files-function))
    (set (make-local-variable 'todos-current-todos-file)
  	 (file-truename (buffer-file-name))))
  (set (make-local-variable 'todos-show-done-only) nil)
  (set (make-local-variable 'todos-categories-with-marks) nil)
  (add-hook 'find-file-hook 'todos-add-to-buffer-list nil t)
  (add-hook 'post-command-hook 'todos-update-buffer-list nil t)
  (when todos-show-current-file
    (add-hook 'pre-command-hook 'todos-show-current-file nil t))
  (add-hook 'window-configuration-change-hook
	    'todos-reset-and-enable-done-separator nil t)
  (add-hook 'kill-buffer-hook 'todos-reset-global-current-todos-file nil t))

(put 'todos-archive-mode 'mode-class 'special)

;; If todos-mode is parent, all todos-mode key bindings appear to be
;; available in todos-archive-mode (e.g. shown by C-h m).
(define-derived-mode todos-archive-mode special-mode "Todos-Arch"
  "Major mode for archived Todos categories.

\\{todos-archive-mode-map}"
  (todos-modes-set-1)
  (todos-modes-set-2)
  (todos-modes-set-3)
  (set (make-local-variable 'todos-current-todos-file)
       (file-truename (buffer-file-name)))
  (set (make-local-variable 'todos-show-done-only) t))

(defun todos-mode-external-set ()
  ""
  (set (make-local-variable 'todos-current-todos-file)
       todos-global-current-todos-file)
  (let ((cats (with-current-buffer
		  ;; Can't use find-buffer-visiting when
		  ;; `todos-display-categories' is called on first
		  ;; invocation of `todos-show', since there is then
		  ;; no buffer visiting the current file.
		  (find-file-noselect todos-current-todos-file 'nowarn)
		(or todos-categories
		    ;; In Todos Edit mode todos-categories is now nil
		    ;; since it uses same buffer as Todos mode but
		    ;; doesn't have the latter's local variables.
		    (save-excursion
		      (goto-char (point-min))
		      (read (buffer-substring-no-properties
			     (line-beginning-position)
			     (line-end-position))))))))
    (set (make-local-variable 'todos-categories) cats)))

(define-derived-mode todos-edit-mode text-mode "Todos-Ed"
  "Major mode for editing multiline Todo items.

\\{todos-edit-mode-map}"
  (todos-modes-set-1)
  (todos-mode-external-set)
  (setq buffer-read-only nil))

(put 'todos-categories-mode 'mode-class 'special)

(define-derived-mode todos-categories-mode special-mode "Todos-Cats"
  "Major mode for displaying and editing Todos categories.

\\{todos-categories-mode-map}"
  (todos-mode-external-set))

(put 'todos-filtered-items-mode 'mode-class 'special)

(define-derived-mode todos-filtered-items-mode special-mode "Todos-Fltr"
  "Mode for displaying and reprioritizing top priority Todos.

\\{todos-filtered-items-mode-map}"
  (todos-modes-set-1)
  (todos-modes-set-2))

;; ---------------------------------------------------------------------------
;;; Todos Commands

;; ---------------------------------------------------------------------------
;;; Entering and Exiting

;;;###autoload
(defun todos-show (&optional solicit-file)
  "Visit a Todos file and display one of its categories.

When invoked in Todos mode, prompt for which todo file to visit.
When invoked outside of Todos mode with non-nil prefix argument
SOLICIT-FILE prompt for which todo file to visit; otherwise visit
`todos-default-todos-file'.  Subsequent invocations from outside
of Todos mode revisit this file or, with option
`todos-show-current-file' non-nil (the default), whichever Todos
file was last visited.

Calling this command before any Todos file exists prompts for a
file name and an initial category (defaulting to
`todos-initial-file' and `todos-initial-category'), creates both
of these, visits the file and displays the category.

The first invocation of this command on an existing Todos file
interacts with the option `todos-show-first': if its value is
`first' (the default), show the first category in the file; if
its value is `table', show the table of categories in the file;
if its value is one of `top', `diary' or `regexp', show the
corresponding saved top priorities, diary items, or regexp items
file, if any.  Subsequent invocations always show the file's
current (i.e., last displayed) category.

In Todos mode just the category's unfinished todo items are shown
by default.  The done items are hidden, but typing
`\\[todos-hide-show-done-items]' displays them below the todo
items.  With non-nil user option `todos-show-with-done' both todo
and done items are always shown on visiting a category.

Invoking this command in Todos Archive mode visits the
corresponding Todos file, displaying the corresponding category."
  (interactive "P")
  (let* ((cat)
	 (show-first todos-show-first)
	 (file (cond ((or (eq major-mode 'todos-mode)
			  solicit-file)
		      (if (funcall todos-files-function)
			  (todos-read-file-name "Choose a Todos file to visit: "
						nil t)
			(error "There are no Todos files")))
		     ((and (eq major-mode 'todos-archive-mode)
			   ;; Called noninteractively via todos-quit from
			   ;; Todos Categories mode to return to archive file.
			   (called-interactively-p 'any))
		      (setq cat (todos-current-category))
		      (concat (file-name-sans-extension todos-current-todos-file)
			      ".todo"))
		     (t
		      (or todos-current-todos-file
			  (and todos-show-current-file
			       todos-global-current-todos-file)
			  (todos-absolute-file-name todos-default-todos-file)
			  (todos-add-file))))))
    (unless (member file todos-visited)
      ;; Can't setq t-c-t-f here, otherwise wrong file shown when
      ;; todos-show is called from todos-display-categories.
      (let ((todos-current-todos-file file))
	(cond ((eq todos-show-first 'table)
	       (todos-display-categories))
	      ((memq todos-show-first '(top diary regexp))
	       (let* ((shortf (todos-short-file-name file))
		      (fi-file (todos-absolute-file-name
				shortf todos-show-first)))
		 (when (eq todos-show-first 'regexp)
		   (let ((rxfiles (directory-files todos-files-directory t
						   ".*\\.todr$" t)))
		     (when (and rxfiles (> (length rxfiles) 1))
		       (let ((rxf (mapcar 'todos-short-file-name rxfiles)))
			 (setq fi-file (todos-absolute-file-name
					(completing-read
					 "Choose a regexp items file: "
					 rxf) 'regexp))))))
		 (if (file-exists-p fi-file)
		     (set-window-buffer
		      (selected-window)
		      (set-buffer (find-file-noselect fi-file 'nowarn)))
		   (message "There is no %s file for %s"
			    (cond ((eq todos-show-first 'top)
				   "top priorities")
				  ((eq todos-show-first 'diary)
				   "diary items")
				  ((eq todos-show-first 'regexp)
				   "regexp items"))
			    shortf)
		   (setq todos-show-first 'first)))))))
    (when (or (member file todos-visited)
	      (eq todos-show-first 'first))
      (set-window-buffer (selected-window)
			 (set-buffer (find-file-noselect file 'nowarn)))
      ;; If called from archive file, show corresponding
      ;; category in Todos file, if it exists.
      (when (assoc cat todos-categories)
	(setq todos-category-number (todos-category-number cat)))
      ;; If this is a new Todos file, add its first category.
      (when (zerop (buffer-size))
	(setq todos-category-number
	      (todos-add-category todos-current-todos-file "")))
      (save-excursion (todos-category-select)))
    (setq todos-show-first show-first)
    (add-to-list 'todos-visited file)))

(defun todos-display-categories ()
  "Display a table of the current file's categories and item counts.

In the initial display the categories are numbered, indicating
their current order for navigating by \\[todos-forward-category]
and \\[todos-backward-category].  You can persistantly change the
order of the category at point by typing
\\[todos-raise-category-priority] or
\\[todos-lower-category-priority].

The labels above the category names and item counts are buttons,
and clicking these changes the display: sorted by category name
or by the respective item counts (alternately descending or
ascending).  In these displays the categories are not numbered
and \\[todos-raise-category-priority] and
\\[todos-lower-category-priority] are
disabled.  (Programmatically, the sorting is triggered by passing
a non-nil SORTKEY argument.)

In addition, the lines with the category names and item counts
are buttonized, and pressing one of these button jumps to the
category in Todos mode (or Todos Archive mode, for categories
containing only archived items, provided user option
`todos-skip-archived-categories' is non-nil.  These categories
are shown in `todos-archived-only' face."
  (interactive)
  (todos-display-categories-1)
  (let (sortkey)
    (todos-update-categories-display sortkey)))

(defun todos-display-categories-alphabetically-or-by-priority ()
  ""
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (forward-line 2)
    (if (member 'alpha todos-descending-counts)
	(progn
	  (todos-update-categories-display nil)
	  (setq todos-descending-counts
		(delete 'alpha todos-descending-counts)))
      (todos-update-categories-display 'alpha))))

(defun todos-display-categories-sorted-by-todo ()
  ""
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (forward-line 2)
    (todos-update-categories-display 'todo)))

(defun todos-display-categories-sorted-by-diary ()
  ""
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (forward-line 2)
    (todos-update-categories-display 'diary)))

(defun todos-display-categories-sorted-by-done ()
  ""
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (forward-line 2)
    (todos-update-categories-display 'done)))

(defun todos-display-categories-sorted-by-archived ()
  ""
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (forward-line 2)
    (todos-update-categories-display 'archived)))

(defun todos-show-archive (&optional ask)
  "Visit the archive of the current Todos category, if it exists.
If the category has no archived items, prompt to visit the
archive anyway.  If there is no archive for this file or with
non-nil argument ASK, prompt to visit another archive.

The buffer showing the archive is in Todos Archive mode.  The
first visit in a session displays the first category in the
archive, subsequent visits return to the last category
displayed."
  (interactive)
  (let* ((cat (todos-current-category))
	 (count (todos-get-count 'archived cat))
	 (archive (concat (file-name-sans-extension todos-current-todos-file)
			  ".toda"))
	 place)
    (setq place (cond (ask 'other-archive)
		      ((file-exists-p archive) 'this-archive)
		      (t (when (y-or-n-p (concat "This file has no archive; "
						 "visit another archive? "))
			   'other-archive))))
    (when (eq place 'other-archive)
      (setq archive (todos-read-file-name "Choose a Todos archive: " t t)))
    (when (and (eq place 'this-archive) (zerop count))
      (setq place (when (y-or-n-p
			  (concat "This category has no archived items;"
				  " visit archive anyway? "))
		     'other-cat)))
    (when place
      (set-window-buffer (selected-window)
			 (set-buffer (find-file-noselect archive)))
      (if (member place '(other-archive other-cat))
	  (setq todos-category-number 1)
	(todos-category-number cat))
      (todos-category-select))))

(defun todos-choose-archive ()
  "Choose an archive and visit it."
  (interactive)
  (todos-show-archive t))

(defun todos-save ()
  "Save the current Todos file."
  (interactive)
  (cond ((eq major-mode 'todos-filtered-items-mode)
	 (todos-check-filtered-items-file)
	 (todos-save-filtered-items-buffer))
	(t
	 (save-buffer))))

(defun todos-quit ()
  "Exit the current Todos-related buffer.
Depending on the specific mode, this either kills the buffer or
buries it and restores state as needed."
  (interactive)
  (cond ((eq major-mode 'todos-categories-mode)
	 ;; Postpone killing buffer till after calling todos-show, to
	 ;; prevent killing todos-mode buffer.
	 (let ((buf (current-buffer)))
	   (setq todos-descending-counts nil)
	   ;; Ensure todos-show calls todos-display-categories only on
	   ;; first invocation per file.
	   (when (eq todos-show-first 'table)
	     (add-to-list 'todos-visited todos-current-todos-file))
	   (todos-show)
	   (kill-buffer buf)))
	((eq major-mode 'todos-filtered-items-mode)
	 (kill-buffer)
	 (unless (eq major-mode 'todos-mode) (todos-show)))
	((member major-mode (list 'todos-mode 'todos-archive-mode))
	 ;; Have to write previously nonexistant archives to file, and might
	 ;; as well save Todos file also.
	 (todos-save)
	 (bury-buffer))))

(defun todos-print (&optional to-file)
  "Produce a printable version of the current Todos buffer.
This converts overlays and soft line wrapping and, depending on
the value of `todos-print-function', includes faces.  With
non-nil argument TO-FILE write the printable version to a file;
otherwise, send it to the default printer."
  (interactive)
  (let ((buf todos-print-buffer)
	(header (cond
		 ((eq major-mode 'todos-mode)
		  (concat "Todos File: "
			  (todos-short-file-name todos-current-todos-file)
			  "\nCategory: " (todos-current-category)))
		 ((eq major-mode 'todos-filtered-items-mode)
		  "Todos Top Priorities")))
	(prefix (propertize (concat todos-prefix " ")
			    'face 'todos-prefix-string))
	(num 0)
	(fill-prefix (make-string todos-indent-to-here 32))
	(content (buffer-string))
	file)
    (with-current-buffer (get-buffer-create buf)
      (insert content)
      (goto-char (point-min))
      (while (not (eobp))
	(let ((beg (point))
	      (end (save-excursion (todos-item-end))))
	  (when todos-number-priorities
	    (setq num (1+ num))
	    (setq prefix (propertize (concat (number-to-string num) " ")
				     'face 'todos-prefix-string)))
	  (insert prefix)
	  (fill-region beg end))
	;; Calling todos-forward-item infloops at todos-item-start due to
	;; non-overlay prefix, so search for item start instead.
	(if (re-search-forward todos-item-start nil t)
	    (beginning-of-line)
	  (goto-char (point-max))))
      (if (re-search-backward (concat "^" (regexp-quote todos-category-done))
			      nil t)
	  (replace-match todos-done-separator))
      (goto-char (point-min))
      (insert header)
      (newline 2)
      (if to-file
	  (let ((file (read-file-name "Print to file: ")))
	    (funcall todos-print-function file))
	(funcall todos-print-function)))
    (kill-buffer buf)))

(defun todos-print-to-file ()
  "Save printable version of this Todos buffer to a file."
  (interactive)
  (todos-print t))

(defun todos-convert-legacy-files ()
  "Convert legacy Todo files to the current Todos format.
The files `todo-file-do' and `todo-file-done' are converted and
saved (the latter as a Todos Archive file) with a new name in
`todos-files-directory'.  See also the documentation string of
`todos-todo-mode-date-time-regexp' for further details."
  (interactive)
  (if (fboundp 'todo-mode)
      (require 'todo-mode)
    (error "Void function `todo-mode'"))
  ;; Convert `todo-file-do'.
  (if (file-exists-p todo-file-do)
      (let ((default "todo-do-conv")
	    file archive-sexp)
	(with-temp-buffer
	  (insert-file-contents todo-file-do)
	  (let ((end (search-forward ")" (line-end-position) t))
		(beg (search-backward "(" (line-beginning-position) t)))
	    (setq todo-categories
		  (read (buffer-substring-no-properties beg end))))
	  (todo-mode)
	  (delete-region (line-beginning-position) (1+ (line-end-position)))
	  (while (not (eobp))
	    (cond
	     ((looking-at (regexp-quote (concat todo-prefix todo-category-beg)))
	      (replace-match todos-category-beg))
	     ((looking-at (regexp-quote todo-category-end))
	      (replace-match ""))
	     ((looking-at (regexp-quote (concat todo-prefix " "
						todo-category-sep)))
	      (replace-match todos-category-done))
	     ((looking-at (concat (regexp-quote todo-prefix) " "
				  todos-todo-mode-date-time-regexp " "
				  (regexp-quote todo-initials) ":"))
	      (todos-convert-legacy-date-time)))
	    (forward-line))
	  (setq file (concat todos-files-directory
			     (read-string
			      (format "Save file as (default \"%s\"): " default)
			      nil nil default)
			     ".todo"))
	  (write-region (point-min) (point-max) file nil 'nomessage nil t))
	(with-temp-buffer
	  (insert-file-contents file)
	  (let ((todos-categories (todos-make-categories-list t)))
	    (todos-update-categories-sexp))
	  (write-region (point-min) (point-max) file nil 'nomessage))
	;; Convert `todo-file-done'.
	(when (file-exists-p todo-file-done)
	  (with-temp-buffer
	    (insert-file-contents todo-file-done)
	    (let ((beg (make-marker))
		  (end (make-marker))
		  cat cats comment item)
	      (while (not (eobp))
		(when (looking-at todos-todo-mode-date-time-regexp)
		  (set-marker beg (point))
		  (todos-convert-legacy-date-time)
		  (set-marker end (point))
		  (goto-char beg)
		  (insert "[" todos-done-string)
		  (goto-char end)
		  (insert "]")
		  (forward-char)
		  (when (looking-at todos-todo-mode-date-time-regexp)
		    (todos-convert-legacy-date-time))
		  (when (looking-at (concat " " (regexp-quote todo-initials) ":"))
		    (replace-match "")))
		(if (re-search-forward
		     (concat "^" todos-todo-mode-date-time-regexp) nil t)
		    (goto-char (match-beginning 0))
		  (goto-char (point-max)))
		(backward-char)
		(when (looking-back "\\[\\([^][]+\\)\\]")
		  (setq cat (match-string 1))
		  (goto-char (match-beginning 0))
		  (replace-match ""))
		;; If the item ends with a non-comment parenthesis not
		;; followed by a period, we lose (but we inherit that problem
		;; from todo-mode.el).
		(when (looking-back "(\\(.*\\)) ")
		  (setq comment (match-string 1))
		  (replace-match "")
		  (insert "[" todos-comment-string ": " comment "]"))
		(set-marker end (point))
		(if (member cat cats)
		    ;; If item is already in its category, leave it there.
		    (unless (save-excursion
			      (re-search-backward
			       (concat "^" (regexp-quote todos-category-beg)
				       "\\(.*\\)$") nil t)
			      (string= (match-string 1) cat))
		      ;; Else move it to its category.
		      (setq item (buffer-substring-no-properties beg end))
		      (delete-region beg (1+ end))
		      (set-marker beg (point))
		      (re-search-backward
		       (concat "^" (regexp-quote (concat todos-category-beg cat))
			       "$")
		       nil t)
		      (forward-line)
		      (if (re-search-forward
			   (concat "^" (regexp-quote todos-category-beg)
				   "\\(.*\\)$") nil t)
			  (progn (goto-char (match-beginning 0))
				 (newline)
				 (forward-line -1))
			(goto-char (point-max)))
		      (insert item "\n")
		      (goto-char beg))
		  (push cat cats)
		  (goto-char beg)
		  (insert todos-category-beg cat "\n\n" todos-category-done "\n"))
		(forward-line))
	      (set-marker beg nil)
	      (set-marker end nil))
	    (setq file (concat (file-name-sans-extension file) ".toda"))
	    (write-region (point-min) (point-max) file nil 'nomessage nil t))
	  (with-temp-buffer
	    (insert-file-contents file)
	    (let ((todos-categories (todos-make-categories-list t)))
	      (todos-update-categories-sexp))
	    (write-region (point-min) (point-max) file nil 'nomessage)
	    (setq archive-sexp (read (buffer-substring-no-properties
				      (line-beginning-position)
				      (line-end-position)))))
	  (setq file (concat (file-name-sans-extension file) ".todo"))
	  ;; Update categories sexp of converted Todos file again, adding
	  ;; counts of archived items.
	  (with-temp-buffer
	    (insert-file-contents file)
	    (let ((sexp (read (buffer-substring-no-properties
			       (line-beginning-position)
			       (line-end-position)))))
	      (dolist (cat sexp)
		(let ((archive-cat (assoc (car cat) archive-sexp)))
		  (if archive-cat
		      (aset (cdr cat) 3 (aref (cdr archive-cat) 2)))))
	      (delete-region (line-beginning-position) (line-end-position))
	      (prin1 sexp (current-buffer)))
	    (write-region (point-min) (point-max) file nil 'nomessage)))
	  (todos-reevaluate-filelist-defcustoms)
	(message "Format conversion done."))
    (error "No legacy Todo file exists")))

;; ---------------------------------------------------------------------------
;;; Navigation Commands

(defun todos-forward-category (&optional back)
  "Visit the numerically next category in this Todos file.
If the current category is the highest numbered, visit the first
category.  With non-nil argument BACK, visit the numerically
previous category (the highest numbered one, if the current
category is the first)."
  (interactive)
  (setq todos-category-number
        (1+ (mod (- todos-category-number (if back 2 0))
		 (length todos-categories))))
  (when todos-skip-archived-categories
    (while (and (zerop (todos-get-count 'todo))
		(zerop (todos-get-count 'done))
		(not (zerop (todos-get-count 'archived))))
      (setq todos-category-number
	    (apply (if back '1- '1+) (list todos-category-number)))))
  (todos-category-select)
  (goto-char (point-min)))

(defun todos-backward-category ()
  "Visit the numerically previous category in this Todos file.
If the current category is the highest numbered, visit the first
category."
  (interactive)
  (todos-forward-category t))

;;;###autoload
(defun todos-jump-to-category (&optional file cat)
  "Prompt for a category in a Todos file and jump to it.

With prefix argument FILE, prompt for a specific Todos file and
choose (with TAB completion) a category in it to jump to;
otherwise, choose and jump to any category in either the current
Todos file or a file in `todos-category-completions-files'.

You can also enter a non-existing category name, triggering a
prompt whether to add a new category by that name; on
confirmation it is added and jumped to.

Noninteractively, jump directly to the category named by argument
CAT; this is used in Todos Categories mode."
  (interactive "P")
  ;; If invoked outside of Todos mode and there is not yet any Todos
  ;; file, initialize one.
  (if (null todos-files)
      (todos-show)
    (let ((file0 (when cat		; We're in Todos Categories mode.
		   ;; With non-nil `todos-skip-archived-categories'
		   ;; jump to archive file of a category with only
		   ;; archived items.
		   (if (and todos-skip-archived-categories
			    (zerop (todos-get-count 'todo cat))
			    (zerop (todos-get-count 'done cat))
			    (not (zerop (todos-get-count 'archived cat))))
		       (concat (file-name-sans-extension
				todos-current-todos-file) ".toda")
		     ;; Otherwise, jump to current todos file.
		     todos-current-todos-file)))
	  (cat+file (unless cat
		      (todos-read-category "Jump to category: " nil file))))
      (setq category (or cat (car cat+file)))
      (unless cat (setq file0 (cdr cat+file)))
      (with-current-buffer (find-file-noselect file0 'nowarn)
	(setq todos-current-todos-file file0)
	;; If called from Todos Categories mode, clean up before jumping.
	(if (string= (buffer-name) todos-categories-buffer)
	    (kill-buffer))
	(set-window-buffer (selected-window)
			   (set-buffer (find-buffer-visiting file0)))
	(unless todos-global-current-todos-file
	  (setq todos-global-current-todos-file todos-current-todos-file))
	(todos-category-number category)
	(todos-category-select)
	(goto-char (point-min))))))

(defun todos-jump-to-item ()
  "Jump to the file and category of the filtered item at point."
  (interactive)
  (let* ((str (todos-item-string))
	 (buf (current-buffer))
	 (res (todos-find-item str))
	 (found (nth 0 res))
	 (file (nth 1 res))
	 (cat (nth 2 res)))
    (if (not found)
	(message "Category %s does not contain this item." cat)
      (kill-buffer buf)
      (set-window-buffer (selected-window)
			 (set-buffer (find-buffer-visiting file)))
      (setq todos-current-todos-file file)
      (setq todos-category-number (todos-category-number cat))
      (let ((todos-show-with-done (if (or todos-filter-done-items
					  (eq (cdr found) 'done))
				      t
				    todos-show-with-done)))
	(todos-category-select))
      (goto-char (car found)))))

(defun todos-forward-item (&optional count)
  "Move point down to start of item with next lower priority.
With positive numerical prefix COUNT, move point COUNT items
downward.

If the category's done items are hidden, this command also moves
point to the empty line below the last todo item from any higher
item in the category, i.e., when invoked with or without a prefix
argument.  If the category's done items are visible, this command
called with a prefix argument only moves point to a lower item,
e.g., with point on the last todo item and called with prefix 1,
it moves point to the first done item; but if called with point
on the last todo item without a prefix argument, it moves point
the the empty line above the done items separator."
  (interactive "P")
  ;; It's not worth the trouble to allow prefix arg value < 1, since we have
  ;; the corresponding command.
  (if (and count (> 1 count))
      (error "This command only accepts a positive numerical prefix argument")
    (let* ((not-done (not (or (todos-done-item-p) (looking-at "^$"))))
	   (start (line-end-position)))
      (goto-char start)
      (if (re-search-forward todos-item-start nil t (or count 1))
	  (goto-char (match-beginning 0))
	(goto-char (point-max)))
      ;; If points advances by one from a todo to a done item, go back to the
      ;; space above todos-done-separator, since that is a legitimate place to
      ;; insert an item.  But skip this space if count > 1, since that should
      ;; only stop on an item.
      (when (and not-done (todos-done-item-p) (not count))
	;; (if (or (not count) (= count 1))
	    (re-search-backward "^$" start t)))));)
    ;; FIXME: The preceding sexp is insufficient when buffer is not narrowed,
    ;; since there could be no done items in this category, so the search puts
    ;; us on first todo item of next category.  Does this ever happen?  If so:
    ;; (let ((opoint) (point))
    ;;   (forward-line -1)
    ;;   (when (or (not count) (= count 1))
    ;; 	(cond ((looking-at (concat "^" (regexp-quote todos-category-beg)))
    ;; 	       (forward-line -2))
    ;; 	      ((looking-at (concat "^" (regexp-quote todos-category-done)))
    ;; 	       (forward-line -1))
    ;; 	      (t
    ;; 	       (goto-char opoint)))))))

(defun todos-backward-item (&optional count)
  "Move point up to start of item with next higher priority.
With positive numerical prefix COUNT, move point COUNT items
upward.

If the category's done items are visible, this command called
with a prefix argument only moves point to a higher item, e.g.,
with point on the first done item and called with prefix 1, it
moves to the last todo item; but if called with point on the
first done item without a prefix argument, it moves point the the
empty line above the done items separator."
  (interactive "P")
  ;; Avoid moving to bob if on the first item but not at bob.
  (when (> (line-number-at-pos) 1)
    ;; It's not worth the trouble to allow prefix arg value < 1, since we have
    ;; the corresponding command.
    (if (and count (> 1 count))
	(error "This command only accepts a positive numerical prefix argument")
      (let* ((done (todos-done-item-p)))
	(todos-item-start)
	(unless (bobp)
	  (re-search-backward todos-item-start nil t (or count 1)))
	;; Unless this is a regexp filtered items buffer (which can contain
	;; intermixed todo and done items), if points advances by one from a
	;; done to a todo item, go back to the space above
	;; todos-done-separator, since that is a legitimate place to insert an
	;; item.  But skip this space if count > 1, since that should only
	;; stop on an item.
	(when (and done (not (todos-done-item-p)) (not count)
					;(or (not count) (= count 1))
		   (not (equal (buffer-name) todos-regexp-items-buffer)))
	  (re-search-forward (concat "^" (regexp-quote todos-category-done))
			     nil t)
	  (forward-line -1))))))

(defun todos-forward-button (n &optional wrap display-message)
  ""
  (interactive "p\nd\nd")
  (forward-button n wrap display-message)
  (and (bolp) (button-at (point))
       ;; Align with beginning of category label.
       (forward-char (+ 4 (length todos-categories-number-separator)))))

(defun todos-backward-button (n &optional wrap display-message)
  ""
  (interactive "p\nd\nd")
  (backward-button n wrap display-message)
  (and (bolp) (button-at (point))
       ;; Align with beginning of category label.
       (forward-char (+ 4 (length todos-categories-number-separator)))))

(defun todos-search ()
  "Search for a regular expression in this Todos file.
The search runs through the whole file and encompasses all and
only todo and done items; it excludes category names.  Multiple
matches are shown sequentially, highlighted in `todos-search'
face."
  (interactive)
  (let ((regex (read-from-minibuffer "Enter a search string (regexp): "))
	(opoint (point))
	matches match cat in-done ov mlen msg)
    (widen)
    (goto-char (point-min))
    (while (not (eobp))
      (setq match (re-search-forward regex nil t))
      (goto-char (line-beginning-position))
      (unless (or (equal (point) 1)
		  (looking-at (concat "^" (regexp-quote todos-category-beg))))
	(if match (push match matches)))
      (forward-line))
    (setq matches (reverse matches))
    (if matches
	(catch 'stop
	  (while matches
	    (setq match (pop matches))
	    (goto-char match)
	    (todos-item-start)
	    (when (looking-at todos-done-string-start)
	      (setq in-done t))
	    (re-search-backward (concat "^" (regexp-quote todos-category-beg)
					"\\(.*\\)\n") nil t)
	    (setq cat (match-string-no-properties 1))
	    (todos-category-number cat)
	    (todos-category-select)
	    (if in-done
		(unless todos-show-with-done (todos-hide-show-done-items)))
	    (goto-char match)
	    (setq ov (make-overlay (- (point) (length regex)) (point)))
	    (overlay-put ov 'face 'todos-search)
	    (when matches
	      (setq mlen (length matches))
	      (if (y-or-n-p
		   (if (> mlen 1)
		       (format "There are %d more matches; go to next match? "
			       mlen)
		     "There is one more match; go to it? "))
		  (widen)
		(throw 'stop (setq msg (if (> mlen 1)
					   (format "There are %d more matches."
						   mlen)
					 "There is one more match."))))))
	  (setq msg "There are no more matches."))
      (todos-category-select)
      (goto-char opoint)
      (message "No match for \"%s\"" regex))
    (when msg
      (if (y-or-n-p (concat msg "\nUnhighlight matches? "))
	  (todos-clear-matches)
	(message "You can unhighlight the matches later by typing %s"
		 (key-description (car (where-is-internal
					'todos-clear-matches))))))))

(defun todos-clear-matches ()
  "Remove highlighting on matches found by todos-search."
  (interactive)
  (remove-overlays 1 (1+ (buffer-size)) 'face 'todos-search))

;; ---------------------------------------------------------------------------
;;; Display Commands

(defun todos-hide-show-item-numbering ()
  ""
  (interactive)
  (todos-reset-prefix 'todos-number-priorities (not todos-number-priorities)))

(defun todos-hide-show-done-items ()
  "Show hidden or hide visible done items in current category."
  (interactive)
  (if (zerop (todos-get-count 'done (todos-current-category)))
      (message "There are no done items in this category.")
    (let ((opoint (point)))
      (goto-char (point-min))
      (let* ((shown (re-search-forward todos-done-string-start nil t))
	     (todos-show-with-done (not shown)))
	(todos-category-select)
	(goto-char opoint)
	;; If start of done items sections is below the bottom of the
	;; window, make it visible.
	(unless shown
	  (setq shown (progn
			(goto-char (point-min))
			(re-search-forward todos-done-string-start nil t)))
	  (if (not (pos-visible-in-window-p shown))
	      (recenter)
	    (goto-char opoint)))))))

(defun todos-show-done-only ()
  "Switch between displaying only done or only todo items."
  (interactive)
  (setq todos-show-done-only (not todos-show-done-only))
  (todos-category-select))

(defun todos-highlight-item ()
  "Highlight or unhighlight the todo item the cursor is on."
  (interactive)
  (require 'hl-line)
  (if hl-line-mode
      (hl-line-mode -1)
    (hl-line-mode 1)))

(defun todos-hide-show-date-time ()
  "Hide or show date-time header of todo items in the current file."
  (interactive)
  (save-excursion
    (save-restriction
      (goto-char (point-min))
      (if (todos-get-overlay 'header)
	  (remove-overlays 1 (1+ (buffer-size)) 'todos 'header)
	(widen)
	(goto-char (point-min))
	(while (not (eobp))
	  (when (re-search-forward
		 (concat todos-date-string-start todos-date-pattern
			 "\\( " diary-time-regexp "\\)?"
			 (regexp-quote todos-nondiary-end) "? ")
		 nil t)
	    (unless (save-match-data (todos-done-item-p))
	      (setq ov (make-overlay (match-beginning 0) (match-end 0) nil t))
	      (overlay-put ov 'todos 'header)
	      (overlay-put ov 'display "")))
	  (todos-forward-item))))))

(defun todos-mark-unmark-item (&optional n)
  "Mark item with `todos-item-mark' if unmarked, otherwise unmark it.
With a positive numerical prefix argument N, change the
marking of the next N items."
  (interactive "p")
  (unless (> n 1) (setq n 1))
  (dotimes (i n)
    (let* ((cat (todos-current-category))
	   (marks (assoc cat todos-categories-with-marks))
	   (ov (todos-get-overlay 'prefix))
	   (pref (overlay-get ov 'before-string)))
      (if (todos-marked-item-p)
	  (progn
	    (overlay-put ov 'before-string (substring pref 1))
	    (if (= (cdr marks) 1)	; Deleted last mark in this category.
		(setq todos-categories-with-marks
		      (assq-delete-all cat todos-categories-with-marks))
	      (setcdr marks (1- (cdr marks)))))
	(overlay-put ov 'before-string (concat todos-item-mark pref))
	(if marks
	    (setcdr marks (1+ (cdr marks)))
	  (push (cons cat 1) todos-categories-with-marks))))
    (todos-forward-item)))

(defun todos-mark-category ()
  "Mark all visiblw items in this category with `todos-item-mark'."
  (interactive)
  (let* ((cat (todos-current-category))
	 (marks (assoc cat todos-categories-with-marks)))
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
	(let* ((ov (todos-get-overlay 'prefix))
	       (pref (overlay-get ov 'before-string)))
	  (unless (todos-marked-item-p)
	    (overlay-put ov 'before-string (concat todos-item-mark pref))
	    (if marks
		(setcdr marks (1+ (cdr marks)))
	      (push (cons cat 1) todos-categories-with-marks))))
	(todos-forward-item)))))

(defun todos-unmark-category ()
  "Remove `todos-item-mark' from all visible items in this category."
  (interactive)
  (let* ((cat (todos-current-category))
	 (marks (assoc cat todos-categories-with-marks)))
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
	(let* ((ov (todos-get-overlay 'prefix))
	       ;; No overlay on empty line between todo and done items.
	       (pref (when ov (overlay-get ov 'before-string))))
	  (when (todos-marked-item-p)
	    (overlay-put ov 'before-string (substring pref 1)))
	  (todos-forward-item))))
    (setq todos-categories-with-marks (delq marks todos-categories-with-marks))))

;; ---------------------------------------------------------------------------
;;; Item filtering commands

(defun todos-set-top-priorities-in-file ()
  "Set number of top priorities for this file.
See `todos-set-top-priorities' for more details."
  (interactive)
  (todos-set-top-priorities))

(defun todos-set-top-priorities-in-category ()
  "Set number of top priorities for this category.
See `todos-set-top-priorities' for more details."
  (interactive)
  (todos-set-top-priorities t))

(defun todos-top-priorities (&optional arg)
  "Display a list of top priority items from different categories.
The categories can be any of those in the current Todos file.

With numerical prefix ARG show at most ARG top priority items
from each category.  With `C-u' as prefix argument show the
numbers of top priority items specified by category in
`todos-priorities-rules', if this has an entry for the file(s);
otherwise show `todos-show-priorities' items per category in the
file(s).  With no prefix argument, if a top priorities file for
the current Todos file has previously been saved (see
`todos-save-filtered-items-buffer'), visit this file; if there is
no such file, build the list as with prefix argument `C-u'.

  The prefix ARG regulates how many top priorities from
each category to show, as described above."
  (interactive "P")
  (todos-filter-items 'top arg))

(defun todos-top-priorities-multifile (&optional arg)
  "Display a list of top priority items from different categories.
The categories are a subset of the categories in the files listed
in `todos-filter-files', or if this nil, in the files chosen from
a file selection dialog that pops up in this case.

With numerical prefix ARG show at most ARG top priority items
from each category in each file.  With `C-u' as prefix argument
show the numbers of top priority items specified in
`todos-priorities-rules', if this is non-nil; otherwise show
`todos-show-priorities' items per category.  With no prefix
argument, if a top priorities file for the chosen Todos files
exists (see `todos-save-filtered-items-buffer'), visit this file;
if there is no such file, do the same as with prefix argument
`C-u'."
  (interactive "P")
  (todos-filter-items 'top arg t))

(defun todos-diary-items (&optional arg)
  "Display a list of todo diary items from different categories.
The categories can be any of those in the current Todos file.

Called with no prefix argument, if a diary items file for the
current Todos file has previously been saved (see
`todos-save-filtered-items-buffer'), visit this file; if there is
no such file, build the list of diary items.  Called with a
prefix argument, build the list even if there is a saved file of
diary items."
  (interactive "P")
  (todos-filter-items 'diary arg))

(defun todos-diary-items-multifile (&optional arg)
  "Display a list of todo diary items from different categories.
The categories are a subset of the categories in the files listed
in `todos-filter-files', or if this nil, in the files chosen from
a file selection dialog that pops up in this case.

Called with no prefix argument, if a diary items file for the
chosen Todos files has previously been saved (see
`todos-save-filtered-items-buffer'), visit this file; if there is
no such file, build the list of diary items.  Called with a
prefix argument, build the list even if there is a saved file of
diary items."
  (interactive "P")
  (todos-filter-items 'diary arg t))

(defun todos-regexp-items (&optional arg)
  "Prompt for a regular expression and display items that match it.
The matches can be from any categories in the current Todos file
and with non-nil option `todos-filter-done-items', can include
not only todo items but also done items, including those in
Archive files.

Called with no prefix argument, if a regexp items file for the
current Todos file has previously been saved (see
`todos-save-filtered-items-buffer'), visit this file; if there is
no such file, build the list of regexp items.  Called with a
prefix argument, build the list even if there is a saved file of
regexp items."
  (interactive "P")
  (todos-filter-items 'regexp arg))

(defun todos-regexp-items-multifile (&optional arg)
  "Prompt for a regular expression and display items that match it.
The matches can be from any categories in the files listed in
`todos-filter-files', or if this nil, in the files chosen from a
file selection dialog that pops up in this case.  With non-nil
option `todos-filter-done-items', the matches can include not
only todo items but also done items, including those in Archive
files.

Called with no prefix argument, if a regexp items file for the
current Todos file has previously been saved (see
`todos-save-filtered-items-buffer'), visit this file; if there is
no such file, build the list of regexp items.  Called with a
prefix argument, build the list even if there is a saved file of
regexp items."
  (interactive "P")
  (todos-filter-items 'regexp arg t))

;; ---------------------------------------------------------------------------
;;; Editing Commands

(defun todos-add-file ()
  "Name and add a new Todos file.
Interactively, prompt for a category and display it.
Noninteractively, return the name of the new file."
  (interactive)
  (let ((prompt (concat "Enter name of new Todos file "
			"(TAB or SPC to see current names): "))
	file)
    (setq file (todos-read-file-name prompt))
    (with-current-buffer (get-buffer-create file)
      (erase-buffer)
      (write-region (point-min) (point-max) file nil 'nomessage nil t)
      (kill-buffer file))
    (todos-reevaluate-filelist-defcustoms)
    (if (called-interactively-p)
	(progn
	  (set-window-buffer (selected-window)
			     (set-buffer (find-file-noselect file)))
	  (setq todos-current-todos-file file)
	  (todos-show))
      file)))

;;; Category editing commands

(defun todos-add-category (&optional file cat)
  "Add a new category to a Todos file.

Called interactively with prefix argument FILE, prompt for a file
and then for a new category to add to that file, otherwise prompt
just for a category to add to the current Todos file.  After adding
the category, visit it in Todos mode.

Non-interactively, add category CAT to file FILE; if FILE is nil,
add CAT to the current Todos file.  After adding the category,
return the new category number."
  (interactive "P")
  (let (catfil file0)
    ;; If cat is passed from caller, don't prompt, unless it is "",
    ;; which means the file was just added and has no category yet.
    (if (and cat (> (length cat) 0))
	(setq file0 (or (and (stringp file) file)
			todos-current-todos-file))
      (setq catfil (todos-read-category "Enter a new category name: "
					'add (when (called-interactively-p 'any)
					       file))
	    cat (car catfil)
	    file0 (if (called-interactively-p 'any)
		      (cdr catfil)
		    file)))
    (find-file file0)
    (let ((counts (make-vector 4 0))	; [todo diary done archived]
	  (num (1+ (length todos-categories)))
	  (buffer-read-only nil))
      (setq todos-current-todos-file file0)
      (setq todos-categories (append todos-categories
				     (list (cons cat counts))))
      (widen)
      (goto-char (point-max))
      (save-excursion			; Save point for todos-category-select.
	(insert todos-category-beg cat "\n\n" todos-category-done "\n"))
      (todos-update-categories-sexp)
      ;; If invoked by user, display the newly added category, if
      ;; called programmatically return the category number to the
      ;; caller.
      (if (called-interactively-p 'any)
	  (progn
	    (setq todos-category-number num)
	    (todos-category-select))
	num))))

(defun todos-rename-category ()
  "Rename current Todos category.
If this file has an archive containing this category, rename the
category there as well."
  (interactive)
  (let* ((cat (todos-current-category))
	 (new (read-from-minibuffer (format "Rename category \"%s\" to: " cat))))
    (setq new (todos-validate-name new 'category))
    (let* ((ofile todos-current-todos-file)
	   (archive (concat (file-name-sans-extension ofile) ".toda"))
	   (buffers (append (list ofile)
			    (unless (zerop (todos-get-count 'archived cat))
			      (list archive)))))
      (dolist (buf buffers)
	(with-current-buffer (find-file-noselect buf)
	  (let (buffer-read-only)
	    (setq todos-categories (todos-set-categories))
	    (save-excursion
	      (save-restriction
		(setcar (assoc cat todos-categories) new)
		(widen)
		(goto-char (point-min))
		(todos-update-categories-sexp)
		(re-search-forward (concat (regexp-quote todos-category-beg)
					   "\\(" (regexp-quote cat) "\\)\n")
				   nil t)
		(replace-match new t t nil 1)))))))
    (force-mode-line-update))
  (save-excursion (todos-category-select)))

(defun todos-delete-category (&optional arg)
  "Delete current Todos category provided it is empty.
With ARG non-nil delete the category unconditionally,
i.e. including all existing todo and done items."
  (interactive "P")
  (let* ((file todos-current-todos-file)
	 (cat (todos-current-category))
	 (todo (todos-get-count 'todo cat))
	 (done (todos-get-count 'done cat))
	 (archived (todos-get-count 'archived cat)))
    (if (and (not arg)
	     (or (> todo 0) (> done 0)))
	(message "%s" (substitute-command-keys
		       (concat "To delete a non-empty category, "
			       "type C-u \\[todos-delete-category].")))
      (when (cond ((= (length todos-categories) 1)
		   (y-or-n-p (concat "This is the only category in this file; "
				     "deleting it will also delete the file.\n"
				     "Do you want to proceed? ")))
		  ((> archived 0)
		   (y-or-n-p (concat "This category has archived items; "
				     "the archived category will remain\n"
				     "after deleting the todo category.  "
				     "Do you still want to delete it\n"
				     "(see `todos-skip-archived-categories' "
				     "for another option)? ")))
		  (t
		   (y-or-n-p (concat "Permanently remove category \"" cat
				     "\"" (and arg " and all its entries")
				     "? "))))
	(widen)
	(let ((buffer-read-only)
	      (beg (re-search-backward
		    (concat "^" (regexp-quote (concat todos-category-beg cat))
			    "\n") nil t))
	      (end (if (re-search-forward
			(concat "\n\\(" (regexp-quote todos-category-beg)
				".*\n\\)") nil t)
		       (match-beginning 1)
		     (point-max))))
	  (remove-overlays beg end)
	  (delete-region beg end)
	  (if (= (length todos-categories) 1)
	      ;; If deleted category was the only one, delete the file.
	      (progn
		(todos-reevaluate-filelist-defcustoms)
		;; Skip confirming killing the archive buffer if it has been
		;; modified and not saved.
		(set-buffer-modified-p nil)
		(delete-file file)
		(kill-buffer)
		(message "Deleted Todos file %s." file))
	    (setq todos-categories (delete (assoc cat todos-categories)
					       todos-categories))
	    (todos-update-categories-sexp)
	    (setq todos-category-number
		  (1+ (mod todos-category-number (length todos-categories))))
	    (todos-category-select)
	    (goto-char (point-min))
	    (message "Deleted category %s." cat)))))))

(defun todos-move-category ()
  "Move current category to a different Todos file.
If current category has archived items, also move those to the
archive of the file moved to, creating it if it does not exist."
  (interactive)
  (when (or (> (length todos-categories) 1)
	    (y-or-n-p (concat "This is the only category in this file; "
			      "moving it will also delete the file.\n"
			      "Do you want to proceed? ")))
    (let* ((ofile todos-current-todos-file)
	   (cat (todos-current-category))
	   (nfile (todos-read-file-name
		   "Choose a Todos file to move this category to: " nil t))
	   (archive (concat (file-name-sans-extension ofile) ".toda"))
	   (buffers (append (list ofile)
			    (unless (zerop (todos-get-count 'archived cat))
			      (list archive))))
	   new)
      (while (equal (file-truename nfile) (file-truename ofile))
	(setq nfile (todos-read-file-name
		     "Choose a file distinct from this file: " nil t)))
      (dolist (buf buffers)
	(with-current-buffer (find-file-noselect buf)
	  (widen)
	  (goto-char (point-max))
	  (let* ((beg (re-search-backward
		       (concat "^" (regexp-quote (concat todos-category-beg cat))
			       "$")
		       nil t))
		 (end (if (re-search-forward
			   (concat "^" (regexp-quote todos-category-beg))
			   nil t 2)
			  (match-beginning 0)
			(point-max)))
		 (content (buffer-substring-no-properties beg end))
		 (counts (cdr (assoc cat todos-categories)))
		 buffer-read-only)
	    ;; Move the category to the new file.  Also update or create
	    ;; archive file if necessary.
	    (with-current-buffer
		(find-file-noselect
		 ;; Regenerate todos-archives in case there
		 ;; is a newly created archive.
		 (if (member buf (funcall todos-files-function t))
		     (concat (file-name-sans-extension nfile) ".toda")
		   nfile))
	      (let* ((nfile-short (todos-short-file-name nfile))
		     (prompt (concat
			      (format "Todos file \"%s\" already has "
				      nfile-short)
			      (format "the category \"%s\";\n" cat)
			      "enter a new category name: "))
		     buffer-read-only)
		(widen)
		(goto-char (point-max))
		(insert content)
		;; If the file moved to has a category with the same
		;; name, rename the moved category.
		(when (assoc cat todos-categories)
		  (unless (member (file-truename (buffer-file-name))
				  (funcall todos-files-function t))
		    (setq new (read-from-minibuffer prompt))
		    (setq new (todos-validate-name new 'category))))
		;; Replace old with new name in Todos and archive files.
		(when new
		  (goto-char (point-max))
		  (re-search-backward
		   (concat "^" (regexp-quote todos-category-beg)
			   "\\(" (regexp-quote cat) "\\)$") nil t)
		  (replace-match new nil nil nil 1)))
	      (setq todos-categories
		    (append todos-categories (list (cons new counts))))
	      (todos-update-categories-sexp)
	      ;; If archive was just created, save it to avoid "File
	      ;; <xyz> no longer exists!" message on invoking
	      ;; `todos-view-archived-items'.
	      (unless (file-exists-p (buffer-file-name))
		(save-buffer))
	      (todos-category-number (or new cat))
	      (todos-category-select))
	    ;; Delete the category from the old file, and if that was the
	    ;; last category, delete the file.  Also handle archive file
	    ;; if necessary.
	    (remove-overlays beg end)
	    (delete-region beg end)
	    (goto-char (point-min))
	    ;; Put point after todos-categories sexp.
	    (forward-line)
	    (if (eobp)		; Aside from sexp, file is empty.
		(progn
		  ;; Skip confirming killing the archive buffer.
		  (set-buffer-modified-p nil)
		  (delete-file todos-current-todos-file)
		  (kill-buffer)
		  (when (member todos-current-todos-file todos-files)
		    (todos-reevaluate-filelist-defcustoms)))
	      (setq todos-categories (delete (assoc cat todos-categories)
						 todos-categories))
	      (todos-update-categories-sexp)
	      (todos-category-select)))))
      (set-window-buffer (selected-window)
			 (set-buffer (find-file-noselect nfile)))
      (todos-category-number (or new cat))
      (todos-category-select))))

(defun todos-merge-category (&optional file)
  "Merge current category into another existing category.

With prefix argument FILE, prompt for a specific Todos file and
choose (with TAB completion) a category in it to merge into;
otherwise, choose and merge into a category in either the
current Todos file or a file in `todos-category-completions-files'.

After merging, the current category's todo and done items are
appended to the chosen goal category's todo and done items,
respectively.  The goal category becomes the current category,
and the previous current category is deleted.

If both the first and goal categories also have archived items,
the former are merged to the latter.  If only the first category
has archived items, the archived category is renamed to the goal
category."
  (interactive "P")
  (let* ((tfile todos-current-todos-file)
	 (archive (concat (file-name-sans-extension (if file gfile tfile))
			  ".toda"))
	 (cat (todos-current-category))
	 (cat+file (todos-read-category "Merge into category: " 'merge file))
	 (goal (car cat+file))
	 (gfile  (cdr cat+file))
	 archived-count here)
    ;; Merge in todo file.
    (with-current-buffer (get-buffer (find-file-noselect tfile))
      (widen)
      (let* ((buffer-read-only nil)
	     (cbeg (progn
		     (re-search-backward
		      (concat "^" (regexp-quote todos-category-beg)) nil t)
		     (point-marker)))
	     (tbeg (progn (forward-line) (point-marker)))
	     (dbeg (progn
		     (re-search-forward
		      (concat "^" (regexp-quote todos-category-done)) nil t)
		     (forward-line) (point-marker)))
	     ;; Omit empty line between todo and done items.
	     (tend (progn (forward-line -2) (point-marker)))
	     (cend (progn
		     (if (re-search-forward
			  (concat "^" (regexp-quote todos-category-beg)) nil t)
			 (progn
			   (goto-char (match-beginning 0))
			   (point-marker))
		       (point-max-marker))))
	     (todo (buffer-substring-no-properties tbeg tend))
	     (done (buffer-substring-no-properties dbeg cend)))
	(goto-char (point-min))
	;; Merge any todo items.
	(unless (zerop (length todo))
	  (re-search-forward
	   (concat "^" (regexp-quote (concat todos-category-beg goal)) "$")
	   nil t)
	  (re-search-forward
	   (concat "^" (regexp-quote todos-category-done)) nil t)
	  (forward-line -1)
	  (setq here (point-marker))
	  (insert todo)
	  (todos-update-count 'todo (todos-get-count 'todo cat) goal))
	;; Merge any done items.
	(unless (zerop (length done))
	  (goto-char (if (re-search-forward
			  (concat "^" (regexp-quote todos-category-beg)) nil t)
			 (match-beginning 0)
		       (point-max)))
	  (when (zerop (length todo)) (setq here (point-marker)))
	  (insert done)
	  (todos-update-count 'done (todos-get-count 'done cat) goal))
	(remove-overlays cbeg cend)
	(delete-region cbeg cend)
	(setq todos-categories (delete (assoc cat todos-categories)
				       todos-categories))
	(todos-update-categories-sexp)
	(mapc (lambda (m) (set-marker m nil)) (list cbeg tbeg dbeg tend cend))))
    (when (file-exists-p archive)
      ;; Merge in archive file.  
      (with-current-buffer (get-buffer (find-file-noselect archive))
	(widen)
	(goto-char (point-min))
	(let ((buffer-read-only nil)
	      (cbeg (save-excursion
		      (when (re-search-forward
			     (concat "^" (regexp-quote
					  (concat todos-category-beg cat)) "$")
			     nil t)
			(goto-char (match-beginning 0))
			(point-marker))))
	      (gbeg (save-excursion
		      (when (re-search-forward
			     (concat "^" (regexp-quote
					  (concat todos-category-beg goal)) "$")
			     nil t)
			(goto-char (match-beginning 0))
			(point-marker))))
	      cend carch)
	  (when cbeg
	    (setq archived-count (todos-get-count 'done cat))
	    (setq cend (save-excursion
			 (if (re-search-forward
			      (concat "^" (regexp-quote todos-category-beg))
			      nil t)
			     (match-beginning 0)
			   (point-max))))
	    (setq carch (save-excursion (goto-char cbeg) (forward-line)
			  (buffer-substring-no-properties (point) cend)))
	    ;; If both categories of the merge have archived items, merge the
	    ;; source items to the goal items, else "merge" by renaming the
	    ;; source category to goal.
	    (if gbeg
		(progn
		  (goto-char (if (re-search-forward
				  (concat "^" (regexp-quote todos-category-beg))
				  nil t)
				 (match-beginning 0)
			       (point-max)))
		  (insert carch)
		  (remove-overlays cbeg cend)
		  (delete-region cbeg cend))
	      (goto-char cbeg)
	      (search-forward cat)
	      (replace-match goal))
	    (setq todos-categories (todos-make-categories-list t))
	    (todos-update-categories-sexp)))))
    (with-current-buffer (get-file-buffer tfile)
      (when archived-count
	(unless (zerop archived-count)
	  (todos-update-count 'archived archived-count goal)
	  (todos-update-categories-sexp)))
      (todos-category-number goal)
      ;; If there are only merged done items, show them.
      (let ((todos-show-with-done (zerop (todos-get-count 'todo goal))))
	(todos-category-select)
	;; Put point on the first merged item.
	(goto-char here)))
    (set-marker here nil)))

(defun todos-set-category-priority (&optional arg)
  "Change priority of category at point in Todos Categories buffer.

With ARG nil, prompt for the new priority number.  Alternatively,
the new priority can be provided by a numerical prefix ARG.
Otherwise, if ARG is either of the symbols `raise' or `lower',
raise or lower the category's priority by one."
  (interactive "P")  
  (let ((curnum (save-excursion
		  ;; Get the number representing the priority of the category
		  ;; on the current line.
		  (forward-line 0) (skip-chars-forward " ") (number-at-point))))
    (when curnum		; Do nothing if we're not on a category line.
      (let* ((maxnum (length todos-categories))
	     (prompt (format "Set category priority (1-%d): " maxnum))
	     (col (current-column))
	     (buffer-read-only nil)
	     (priority (cond ((and (eq arg 'raise) (> curnum 1))
			      (1- curnum))
			     ((and (eq arg 'lower) (< curnum maxnum))
			      (1+ curnum))))
	     candidate)
	(while (not priority)
	  (setq candidate (or arg (read-number prompt)))
	  (setq arg nil)
	  (setq prompt
		(cond ((or (< candidate 1) (> candidate maxnum))
		       (format "Priority must be an integer between 1 and %d: "
			       maxnum))
		      ((= candidate curnum)
		       "Choose a different priority than the current one: ")))
	  (unless prompt (setq priority candidate)))
	(let* ((lower (< curnum priority)) ; Priority is being lowered.
	       (head (butlast todos-categories
			      (apply (if lower 'identity '1+)
				     (list (- maxnum priority)))))
	       (tail (nthcdr (apply (if lower 'identity '1-) (list priority))
			     todos-categories))
	       ;; Category's name and items counts list.
	       (catcons (nth (1- curnum) todos-categories))
	       (todos-categories (nconc head (list catcons) tail))
	       newcats)
	  (when lower (setq todos-categories (nreverse todos-categories)))
	  (setq todos-categories (delete-dups todos-categories))
	  (when lower (setq todos-categories (nreverse todos-categories)))
	  (setq newcats todos-categories)
	  (kill-buffer)
	  (with-current-buffer (find-buffer-visiting todos-current-todos-file)
	    (setq todos-categories newcats)
	    (todos-update-categories-sexp))
	  (todos-display-categories)
	  (forward-line (1+ priority))
	  (forward-char col))))))

(defun todos-raise-category-priority ()
  "Raise priority of category at point in Todos Categories buffer."
  (interactive)
  (todos-set-category-priority 'raise))

(defun todos-lower-category-priority ()
  "Lower priority of category at point in Todos Categories buffer."
  (interactive)
  (todos-set-category-priority 'lower))

;; ---------------------------------------------------------------------------
;;; Item editing commands

;;;###autoload
(defun todos-insert-item (&optional arg diary nonmarking date-type time
				    region-or-here)
  "Add a new Todo item to a category.
\(See the note at the end of this document string about key
bindings and convenience commands derived from this command.)

With no (or nil) prefix argument ARG, add the item to the current
category; with one prefix argument (C-u), prompt for a category
from the current Todos file; with two prefix arguments (C-u C-u),
first prompt for a Todos file, then a category in that file.  If
a non-existing category is entered, ask whether to add it to the
Todos file; if answered affirmatively, add the category and
insert the item there.

When argument DIARY is non-nil, this overrides the intent of the
user option `todos-include-in-diary' for this item: if
`todos-include-in-diary' is nil, include the item in the Fancy
Diary display, and if it is non-nil, exclude the item from the
Fancy Diary display.  When DIARY is nil, `todos-include-in-diary'
has its intended effect.

When the item is included in the Fancy Diary display and the
argument NONMARKING is non-nil, this overrides the intent of the
user option `todos-diary-nonmarking' for this item: if
`todos-diary-nonmarking' is nil, append `diary-nonmarking-symbol'
to the item, and if it is non-nil, omit `diary-nonmarking-symbol'.

The argument DATE-TYPE determines the content of the item's
mandatory date header string and how it is added:
- If DATE-TYPE is the symbol `calendar', the Calendar pops up and
  when the user puts the cursor on a date and hits RET, that
  date, in the format set by `calendar-date-display-form',
  becomes the date in the header.
- If DATE-TYPE is a string matching the regexp
  `todos-date-pattern', that string becomes the date in the
  header.  This case is for the command
  `todos-insert-item-from-calendar' which is called from the
  Calendar.
- If DATE-TYPE is the symbol `date', the header contains the date
  in the format set by `calendar-date-display-form', with year,
  month and day individually prompted for (month with tab
  completion).
- If DATE-TYPE is the symbol `dayname' the header contains a
  weekday name instead of a date, prompted for with tab
  completion.
- If DATE-TYPE has any other value (including nil or none) the
  header contains the current date (in the format set by
  `calendar-date-display-form').

With non-nil argument TIME prompt for a time string, which must
match `diary-time-regexp'.  Typing `<return>' at the prompt
returns the current time, if the user option
`todos-always-add-time-string' is non-nil, otherwise the empty
string (i.e., no time string).  If TIME is absent or nil, add or
omit the current time string according as
`todos-always-add-time-string' is non-nil or nil, respectively.

The argument REGION-OR-HERE determines the source and location of
the new item:
- If the REGION-OR-HERE is the symbol `here', prompt for the text
  of the new item and, if the command was invoked in the current
  category, insert it directly above the todo item at
  point (hence lowering the priority of the remaining items), or
  if point is on the empty line below the last todo item, insert
  the new item there.  If point is in the done items section of
  the category, insert the new item as the first todo item in the
  category.  Likewise, if the command with `here' is invoked
  outside of the current category, jump to the chosen category
  and insert the new item as the first item in the category.
- If REGION-OR-HERE is the symbol `region', use the region of the
  current buffer as the text of the new item, depending on the
  value of user option `todos-use-only-highlighted-region': if
  this is non-nil, then use the region only when it is
  highlighted; otherwise, use the region regardless of
  highlighting.  An error is signalled if there is no region in
  the current buffer.  Prompt for the item's priority in the
  category (an integer between 1 and one more than the number of
  items in the category), and insert the item accordingly.
- If REGION-OR-HERE has any other value (in particular, nil or
  none), prompt for the text and the item's priority, and insert
  the item accordingly.

To facilitate using these arguments when inserting a new todo
item, convenience commands have been defined for all admissible
combinations together with mnenomic key bindings based on on the
name of the arguments and their order in the command's argument
list: diar_y_ - nonmar_k_ing - _c_alendar or _d_ate or day_n_ame
- _t_ime - _r_egion or _h_ere.  These key combinations are
appended to the basic insertion key (i) and keys that allow a
following key must be doubled when used finally.  For example,
`iyh' will insert a new item with today's date, marked according
to the DIARY argument described above, and with priority
according to the HERE argument; while `iyy' does the same except
the priority is not given by HERE but by prompting."
;;   An alternative interface for customizing key
;; binding is also provided with the function
;; `todos-insertion-bindings'."		;FIXME
  (interactive "P")
  ;; If invoked outside of Todos mode and there is not yet any Todos
  ;; file, initialize one.
  (if (null todos-files)
      (todos-show)
    (let ((region (eq region-or-here 'region))
	  (here (eq region-or-here 'here)))
      (when region
	(let (use-empty-active-region)
	  (unless (and todos-use-only-highlighted-region (use-region-p))
	    (error "There is no active region"))))
      (let* ((obuf (current-buffer))
	     (ocat (todos-current-category))
	     (opoint (point))
	     (todos-mm (eq major-mode 'todos-mode))
	     (cat+file (cond ((equal arg '(4))
			      (todos-read-category "Insert in category: "))
			     ((equal arg '(16))
			      (todos-read-category "Insert in category: "
						   nil 'file))
			     (t
			      (cons (todos-current-category)
				    (or todos-current-todos-file
					(and todos-show-current-file
					     todos-global-current-todos-file)
					(todos-absolute-file-name
					 todos-default-todos-file))))))
	     (cat (car cat+file))
	     (file (cdr cat+file))
	     (new-item (if region
			   (buffer-substring-no-properties
			    (region-beginning) (region-end))
			 (read-from-minibuffer "Todo item: ")))
	     (date-string (cond
			   ((eq date-type 'date)
			    (todos-read-date))
			   ((eq date-type 'dayname)
			    (todos-read-dayname))
			   ((eq date-type 'calendar)
			    (setq todos-date-from-calendar t)
			    (or (todos-set-date-from-calendar)
				;; If user exits Calendar before choosing
				;; a date, cancel item insertion.
				(keyboard-quit)))
			   ((and (stringp date-type)
				 (string-match todos-date-pattern date-type))
			    (setq todos-date-from-calendar date-type)
			    (todos-set-date-from-calendar))
			   (t
			    (calendar-date-string (calendar-current-date) t t))))
	     (time-string (or (and time (todos-read-time))
			      (and todos-always-add-time-string
				   (substring (current-time-string) 11 16)))))
	(setq todos-date-from-calendar nil)
	(find-file-noselect file 'nowarn)
	(set-window-buffer (selected-window)
			   (set-buffer (find-buffer-visiting file)))
	;; If this command was invoked outside of a Todos buffer, the
	;; call to todos-current-category above returned nil.  If we
	;; just entered Todos mode now, then cat was set to the file's
	;; first category, but if todos-mode was already enabled, cat
	;; did not get set, so we have to set it explicitly.
	(unless cat
	  (setq cat (todos-current-category)))
	(setq todos-current-todos-file file)
	(unless todos-global-current-todos-file
	  (setq todos-global-current-todos-file todos-current-todos-file))
	(let ((buffer-read-only nil)
	      (called-from-outside (not (and todos-mm (equal cat ocat))))
	      done-only item-added)
	  (setq new-item
		;; Add date, time and diary marking as required.
		(concat (if (not (and diary (not todos-include-in-diary)))
			    todos-nondiary-start
			  (when (and nonmarking (not todos-diary-nonmarking))
			    diary-nonmarking-symbol))
			date-string (when (and time-string ; Can be empty string.
					       (not (zerop (length time-string))))
				      (concat " " time-string))
			(when (not (and diary (not todos-include-in-diary)))
			  todos-nondiary-end)
			" " new-item))
	  ;; Indent newlines inserted by C-q C-j if nonspace char follows.
	  (setq new-item (replace-regexp-in-string
			  "\\(\n\\)[^[:blank:]]"
			  (concat "\n" (make-string todos-indent-to-here 32))
			  new-item nil nil 1))
	  (unwind-protect
	      (progn
		;; Make sure the correct category is selected.  There
		;; are two cases: (i) we just visited the file, so no
		;; category is selected yet, or (ii) we invoked
		;; insertion "here" from outside the category we want
		;; to insert in (with priority insertion, category
		;; selection is done by todos-set-item-priority).
		(when (or (= (- (point-max) (point-min)) (buffer-size))
			  (and here called-from-outside))
		  (todos-category-number cat)
		  (todos-category-select))
		;; If only done items are displayed in category,
		;; toggle to todo items before inserting new item.
		(when (save-excursion
			(goto-char (point-min))
			(looking-at todos-done-string-start))
		  (setq done-only t)
		  (todos-show-done-only))
		(if here
		    (progn
		      ;; If command was invoked with point in done
		      ;; items section or outside of the current
		      ;; category, can't insert "here", so to be
		      ;; useful give new item top priority.
		      (when (or (todos-done-item-section-p)
				called-from-outside
				done-only)
			(goto-char (point-min)))
		      (todos-insert-with-overlays new-item))
		  (todos-set-item-priority new-item cat t))
		(setq item-added t))
	    ;; If user cancels before setting priority, restore
	    ;; display.
	    (unless item-added
	      (if ocat
		  (progn
		    (unless (equal cat ocat)
		      (todos-category-number ocat)
		      (todos-category-select))
		    (and done-only (todos-show-done-only)))
		(set-window-buffer (selected-window) (set-buffer obuf)))
	      (goto-char opoint))
	    ;; If the todo items section is not visible when the
	    ;; insertion command is called (either because only done
	    ;; items were shown or because the category was not in the
	    ;; current buffer), then if the item is inserted at the
	    ;; end of the category, point is at eob and eob at
	    ;; window-start, so that higher priority todo items are
	    ;; out of view.  So we recenter to make sure the todo
	    ;; items are displayed in the window.
	    (when item-added (recenter)))
	  (todos-update-count 'todo 1)
	  (if (or diary todos-include-in-diary) (todos-update-count 'diary 1))
	  (todos-update-categories-sexp))))))

(defun todos-copy-item ()
  "Copy item at point and insert the copy as a new item."
  (interactive)
  (unless (or (todos-done-item-p) (looking-at "^$"))
    (let ((copy (todos-item-string))
	  (diary-item (todos-diary-item-p)))
      (todos-set-item-priority copy (todos-current-category) t)
      (todos-update-count 'todo 1)
      (when diary-item (todos-update-count 'diary 1))
      (todos-update-categories-sexp))))

(defvar todos-date-from-calendar nil
  "Helper variable for setting item date from the Emacs Calendar.")

(defun todos-set-date-from-calendar ()
  "Return string of date chosen from Calendar."
  (cond ((and (stringp todos-date-from-calendar)
	      (string-match todos-date-pattern todos-date-from-calendar))
	 todos-date-from-calendar)
	(todos-date-from-calendar
	 (let (calendar-view-diary-initially-flag)
	   (calendar)) 			; *Calendar* is now current buffer.
	 (define-key calendar-mode-map [remap newline] 'exit-recursive-edit)
	 ;; If user exits Calendar before choosing a date, clean up properly.
	 (define-key calendar-mode-map
	   [remap calendar-exit] (lambda ()
				    (interactive)
				    (progn
				      (calendar-exit)
				      (exit-recursive-edit))))
	 (message "Put cursor on a date and type <return> to set it.")
	 (recursive-edit)
	 (unwind-protect
	     (when (equal (buffer-name) calendar-buffer)
	       (setq todos-date-from-calendar
		     (calendar-date-string (calendar-cursor-to-date t) t t))
	       (calendar-exit)
	       todos-date-from-calendar)
	   (define-key calendar-mode-map [remap newline] nil)
	   (define-key calendar-mode-map [remap calendar-exit] nil)
	   (unless (zerop (recursion-depth)) (exit-recursive-edit))
	   (when (stringp todos-date-from-calendar)
	     todos-date-from-calendar)))))

(defun todos-delete-item ()
  "Delete at least one item in this category.

If there are marked items, delete all of these; otherwise, delete
the item at point."
  (interactive)
  (let (ov)
    (unwind-protect
	(let* ((cat (todos-current-category))
	       (marked (assoc cat todos-categories-with-marks))
	       (item (unless marked (todos-item-string)))
	       (answer (if marked
			   (y-or-n-p "Permanently delete all marked items? ")
			 (when item
			   (setq ov (make-overlay
				     (save-excursion (todos-item-start))
				     (save-excursion (todos-item-end))))
			   (overlay-put ov 'face 'todos-search)
			   (y-or-n-p (concat "Permanently delete this item? ")))))
	       buffer-read-only)
	  (when answer
	    (and marked (goto-char (point-min)))
	    (catch 'done
	      (while (not (eobp))
		(if (or (and marked (todos-marked-item-p)) item)
		    (progn
		      (if (todos-done-item-p)
			  (todos-update-count 'done -1)
			(todos-update-count 'todo -1 cat)
			(and (todos-diary-item-p) (todos-update-count 'diary -1)))
		      (if ov (delete-overlay ov))
		      (todos-remove-item)
		      ;; Don't leave point below last item.
		      (and item (bolp) (eolp) (< (point-min) (point-max))
			   (todos-backward-item))
		      (when item 
			(throw 'done (setq item nil))))
		  (todos-forward-item))))
	    (when marked
	      (setq todos-categories-with-marks
		    (assq-delete-all cat todos-categories-with-marks)))
	    (todos-update-categories-sexp)
	    (todos-prefix-overlays)))
      (if ov (delete-overlay ov)))))

(defun todos-edit-item (&optional arg)
  "Edit the Todo item at point.

With non-nil prefix argument ARG, include the item's date/time
header, making it also editable; otherwise, include only the item
content.

If the item consists of only one logical line, edit it in the
minibuffer; otherwise, edit it in Todos Edit mode."
  (interactive "P")
  (when (todos-item-string)
    (let* ((opoint (point))
	   (start (todos-item-start))
	   (item-beg (progn
		       (re-search-forward
			(concat todos-date-string-start todos-date-pattern
				"\\( " diary-time-regexp "\\)?"
				(regexp-quote todos-nondiary-end) "?")
			(line-end-position) t)
		       (1+ (- (point) start))))
	   (header (substring (todos-item-string) 0 item-beg))
	   (item (if arg (todos-item-string)
		   (substring (todos-item-string) item-beg)))
	   (multiline (> (length (split-string item "\n")) 1))
	   (buffer-read-only nil))
      (if multiline
	  (todos-edit-multiline-item)
	(let ((new (concat (if arg "" header)
			   (read-string "Edit: " (if arg
						     (cons item item-beg)
						   (cons item 0))))))
	  (when arg
	    (while (not (string-match (concat todos-date-string-start
					      todos-date-pattern) new))
	      (setq new (read-from-minibuffer
			 "Item must start with a date: " new))))
	  ;; Ensure lines following hard newlines are indented.
	  (setq new (replace-regexp-in-string
		     "\\(\n\\)[^[:blank:]]"
		     (concat "\n" (make-string todos-indent-to-here 32)) new
		     nil nil 1))
	  ;; If user moved point during editing, make sure it moves back.
	  (goto-char opoint)
	  (todos-remove-item)
	  (todos-insert-with-overlays new)
	  (move-to-column item-beg))))))

(defun todos-edit-multiline-item ()
  "Edit current Todo item in Todos Edit mode.
Use of newlines invokes `todos-indent' to insure compliance with
the format of Diary entries."
  (interactive)
  (let ((buf todos-edit-buffer))
    (set-window-buffer (selected-window)
		       (set-buffer (make-indirect-buffer (buffer-name) buf)))
    (narrow-to-region (todos-item-start) (todos-item-end))
    (todos-edit-mode)
    (message "%s" (substitute-command-keys
		   (concat "Type \\[todos-edit-quit] "
			   "to return to Todos mode.\n")))))

(defun todos-edit-multiline (&optional item) ;FIXME: not item editing command
  ""					;FIXME
  (interactive)
  (widen)
  (todos-edit-mode)
  (remove-overlays)
  (message "%s" (substitute-command-keys
		 (concat "Type \\[todos-edit-quit] to check file format "
			 "validity and return to Todos mode.\n"))))

(defun todos-edit-quit ()
  "Return from Todos Edit mode to Todos mode.
If the item contains hard line breaks, make sure the following
lines are indented by `todos-indent-to-here' to conform to diary
format.

If the whole file was in Todos Edit mode, check before returning
whether the file is still a valid Todos file and if so, also
recalculate the Todos categories sexp, in case changes were made
in the number or names of categories."
  (interactive)
  (if (> (buffer-size) (- (point-max) (point-min)))
      (let ((item (buffer-string))
	    (regex "\\(\n\\)[^[:blank:]]"))
	;; Ensure lines following hard newlines are indented.
	(when (string-match regex (buffer-string))
	  (replace-regexp-in-string
	   regex (concat "\n" (make-string todos-indent-to-here 32))
	   nil nil 1)
	  (delete-region (point-min) (point-max))
	  (insert item))
	(kill-buffer))
      (when (todos-check-format)
	;; FIXME: separate out sexp check?
	;; If manual editing makes e.g. item counts change, have to
	;; call this to update todos-categories, but it restores
	;; category order to list order.
	;; (todos-repair-categories-sexp)
	;; Compare (todos-make-categories-list t) with sexp and if
	;; different ask (todos-update-categories-sexp) ?
	(todos-mode)
	(let* ((cat-beg (concat "^" (regexp-quote todos-category-beg)
				"\\(.*\\)$"))
	       (curline (buffer-substring-no-properties
			 (line-beginning-position) (line-end-position)))
	       (cat (cond ((string-match cat-beg curline)
			   (match-string-no-properties 1 curline))
			  ((or (re-search-backward cat-beg nil t)
			       (re-search-forward cat-beg nil t))
			   (match-string-no-properties 1)))))
	  (todos-category-number cat)
	  (todos-category-select)
	  (goto-char (point-min))))))

(defun todos-edit-item-header-1 (what &optional inc)
  "Function underlying commands to edit item date/time header.

The argument WHAT (passed by invoking commands) specifies what
part of the header to edit; possible values are these symbols:
`date', to edit the year, month, and day of the date string;
`time', to edit just the time string; `calendar', to select the
date from the Calendar; `today', to set the date to today's date;
`dayname', to set the date string to the name of a day or to
change the day name; and `year', `month' or `day', to edit only
these respective parts of the date string (`day' is the number of
the given day of the month, and `month' is either the name of the
given month or its number, depending on the value of
`calendar-date-display-form').

The optional argument INC is a positive or negative integer
\(passed by invoking commands as a numerical prefix argument)
that in conjunction with the WHAT values `year', `month' or
`day', increments or decrements the specified date string
component by the specified number of suitable units, i.e., years,
months, or days, with automatic adjustment of the other date
string components as necessary.

If there are marked items, apply the same edit to all of these;
otherwise, edit just the item at point."
  (let* ((cat (todos-current-category))
	 (marked (assoc cat todos-categories-with-marks))
	 (first t)
	 (todos-date-from-calendar t)
	 (buffer-read-only nil)
	 ndate ntime year monthname month day
	 dayname)	; Needed by calendar-date-display-form.
    (save-excursion
      (or (and marked (goto-char (point-min))) (todos-item-start))
      (catch 'end
	(while (not (eobp))
	  (and marked
	       (while (not (todos-marked-item-p))
		 (todos-forward-item)
		 (and (eobp) (throw 'end nil))))
	  (re-search-forward (concat todos-date-string-start "\\(?1:"
				     todos-date-pattern
				     "\\)\\(?2: " diary-time-regexp "\\)?"
				     (regexp-quote todos-nondiary-end) "?")
			     (line-end-position) t)
	  (let* ((odate (match-string-no-properties 1))
		 (otime (match-string-no-properties 2))
		 (omonthname (match-string-no-properties 6))
		 (omonth (match-string-no-properties 7))
		 (oday (match-string-no-properties 8))
		 (oyear (match-string-no-properties 9))
		 (tmn-array todos-month-name-array)
		 (mlist (append tmn-array nil))
		 (tma-array todos-month-abbrev-array)
		 (mablist (append tma-array nil))
		 (yy (and oyear (unless (string= oyear "*")
				  (string-to-number oyear))))
		 (mm (or (and omonth (unless (string= omonth "*")
				       (string-to-number omonth)))
			 (1+ (- (length mlist)
				(length (or (member omonthname mlist)
					    (member omonthname mablist)))))))
		 (dd (and oday (unless (string= oday "*")
				 (string-to-number oday)))))
	    ;; If there are marked items, use only the first to set
	    ;; header changes, and apply these to all marked items.
	    (when first
	      (cond
	       ((eq what 'date)
		(setq ndate (todos-read-date)))
	       ((eq what 'calendar)
		(setq ndate (save-match-data (todos-set-date-from-calendar))))
	       ((eq what 'today)
		(setq ndate (calendar-date-string (calendar-current-date) t t)))
	       ((eq what 'dayname)
		(setq ndate (todos-read-dayname)))
	       ((eq what 'time)
		(setq ntime (save-match-data (todos-read-time)))
		(when (> (length ntime) 0)
		  (setq ntime (concat " " ntime))))
	       ;; When date string consists only of a day name,
	       ;; passing other date components is a NOP.
	       ((and (memq what '(year month day))
		     (not (or oyear omonth oday))))
	       ((eq what 'year)
		(setq day oday
		      monthname omonthname
		      month omonth
		      year (cond ((not current-prefix-arg)
				  (todos-read-date 'year))
				 ((string= oyear "*")
				  (error "Cannot increment *"))
				 (t
				  (number-to-string (+ yy inc))))))
	       ((eq what 'month)
		(setf day oday
		      year oyear
		      (if (memq 'month calendar-date-display-form)
			  month
			monthname)
		      (cond ((not current-prefix-arg)
			     (todos-read-date 'month))
			    ((or (string= omonth "*") (= mm 13))
			     (error "Cannot increment *"))
			    (t
			     (let ((mminc (+ mm inc))) 
			       ;; Increment or decrement month by INC
			       ;; modulo 12.
			       (setq mm (% mminc 12))
			       ;; If result is 0, make month December.
			       (setq mm (if (= mm 0) 12 (abs mm)))
			       ;; Adjust year if necessary.
			       (setq year (or (and (cond ((> mminc 12)
							  (+ yy (/ mminc 12)))
							 ((< mminc 1)
							  (- yy (/ mminc 12) 1))
							 (t yy))
						   (number-to-string yy))
					      oyear)))
			     ;; Return the changed numerical month as
			     ;; a string or the corresponding month name.
			     (if omonth
				 (number-to-string mm)
			       (aref tma-array (1- mm))))))
		(let ((yy (string-to-number year)) ; 0 if year is "*".
		      ;; When mm is 13 (corresponding to "*" as value
		      ;; of month), this raises an args-out-of-range
		      ;; error in calendar-last-day-of-month, so use 1
		      ;; (corresponding to January) to get 31 days.
		      (mm (if (= mm 13) 1 mm)))
		  (if (> (string-to-number day)
			 (calendar-last-day-of-month mm yy))
		      (error "%s %s does not have %s days"
			     (aref tmn-array (1- mm))
			     (if (= mm 2) yy "") day))))
	       ((eq what 'day)
		(setq year oyear
		      month omonth
		      monthname omonthname
		      day (cond
			   ((not current-prefix-arg)
			    (todos-read-date 'day mm oyear))
			   ((string= oday "*")
			    (error "Cannot increment *"))
			   ((or (string= omonth "*") (string= omonthname "*"))
			    (setq dd (+ dd inc))
			    (if (> dd 31)
				(error "A month cannot have more than 31 days")
			      (number-to-string dd)))
			   ;; Increment or decrement day by INC,
			   ;; adjusting month and year if necessary
			   ;; (if year is "*" assume current year to
			   ;; calculate adjustment).
			   (t
			    (let* ((yy (or yy (calendar-extract-year
					       (calendar-current-date))))
				   (date (calendar-gregorian-from-absolute
					  (+ (calendar-absolute-from-gregorian
					      (list mm dd yy)) inc)))
				   (adjmm (nth 0 date)))
			      ;; Set year and month(name) to adjusted values.
			      (unless (string= year "*")
				(setq year (number-to-string (nth 2 date))))
			      (if month
				  (setq month (number-to-string adjmm))
				(setq monthname (aref tma-array (1- adjmm))))
			      ;; Return changed numerical day as a string.
			      (number-to-string (nth 1 date)))))))))
	    ;; If new year, month or day date string components were
	    ;; calculated, rebuild the whole date string from them.
	    (when (memq what '(year month day))
	      (if (or oyear omonth omonthname oday)
		  (setq ndate (mapconcat 'eval calendar-date-display-form ""))
		(message "Cannot edit date component of empty date string")))
	    (when ndate (replace-match ndate nil nil nil 1))
	    ;; Add new time string to the header, if it was supplied.
	    (when ntime
	      (if otime
		  (replace-match ntime nil nil nil 2)
		(goto-char (match-end 1))
		(insert ntime)))
	    (setq todos-date-from-calendar nil)
	    (setq first nil))
	  ;; Apply the changes to the first marked item header to the
	  ;; remaining marked items.  If there are no marked items,
	  ;; we're finished.
	  (if marked
	      (todos-forward-item)
	    (goto-char (point-max))))))))

(defun todos-edit-item-header ()
  "Interactively edit at least the date of item's date/time header.
If user option `todos-always-add-time-string' is non-nil, also
edit item's time string."
  (interactive)
  (todos-edit-item-header-1 'date)
  (when todos-always-add-time-string
    (todos-edit-item-time)))

(defun todos-edit-item-time ()
  "Interactively edit the time string of item's date/time header."
  (interactive)
  (todos-edit-item-header-1 'time))

(defun todos-edit-item-date-from-calendar ()
  "Interactively edit item's date using the Calendar."
  (interactive)
  (todos-edit-item-header-1 'calendar))

(defun todos-edit-item-date-to-today ()
  "Set item's date to today's date."
  (interactive)
  (todos-edit-item-header-1 'today))

(defun todos-edit-item-date-day-name ()
  "Replace item's date with the name of a day of the week."
  (interactive)
  (todos-edit-item-header-1 'dayname))

(defun todos-edit-item-date-year (&optional inc)
  "Interactively edit the year of item's date string.
With prefix argument INC a positive or negative integer,
increment or decrement the year by INC."
  (interactive "p")
  (todos-edit-item-header-1 'year inc))

(defun todos-edit-item-date-month (&optional inc)
  "Interactively edit the month of item's date string.
With prefix argument INC a positive or negative integer,
increment or decrement the month by INC."
  (interactive "p")
  (todos-edit-item-header-1 'month inc))

(defun todos-edit-item-date-day (&optional inc)
  "Interactively edit the day of the month of item's date string.
With prefix argument INC a positive or negative integer,
increment or decrement the day by INC."
  (interactive "p")
  (todos-edit-item-header-1 'day inc))

(defun todos-edit-item-diary-inclusion ()
  "Change diary status of one or more todo items in this category.
That is, insert `todos-nondiary-marker' if the candidate items
lack this marking; otherwise, remove it.

If there are marked todo items, change the diary status of all
and only these, otherwise change the diary status of the item at
point."
  (interactive)
  (let ((buffer-read-only)
	(marked (assoc (todos-current-category)
		       todos-categories-with-marks)))
    (catch 'stop
      (save-excursion
	(when marked (goto-char (point-min)))
	(while (not (eobp))
	  (if (todos-done-item-p)
	      (throw 'stop (message "Done items cannot be edited"))
	    (unless (and marked (not (todos-marked-item-p)))
	      (let* ((beg (todos-item-start))
		     (lim (save-excursion (todos-item-end)))
		     (end (save-excursion
			    (or (todos-time-string-matcher lim)
				(todos-date-string-matcher lim)))))
		(if (looking-at (regexp-quote todos-nondiary-start))
		    (progn
		      (replace-match "")
		      (search-forward todos-nondiary-end (1+ end) t)
		      (replace-match "")
		      (todos-update-count 'diary 1))
		  (when end
		    (insert todos-nondiary-start)
		    (goto-char (1+ end))
		    (insert todos-nondiary-end)
		    (todos-update-count 'diary -1)))))
	    (unless marked (throw 'stop nil))
	    (todos-forward-item)))))
    (todos-update-categories-sexp)))

(defun todos-edit-category-diary-inclusion (arg)
  "Make all items in this category diary items.
With prefix ARG, make all items in this category non-diary
items."
  (interactive "P")
  (save-excursion
    (goto-char (point-min))
    (let ((todo-count (todos-get-count 'todo))
	  (diary-count (todos-get-count 'diary))
	  (buffer-read-only))
      (catch 'stop
	(while (not (eobp))
	  (if (todos-done-item-p)	; We've gone too far.
	      (throw 'stop nil)
	    (let* ((beg (todos-item-start))
		   (lim (save-excursion (todos-item-end)))
		   (end (save-excursion
			  (or (todos-time-string-matcher lim)
			      (todos-date-string-matcher lim)))))
	      (if arg
		  (unless (looking-at (regexp-quote todos-nondiary-start))
		    (insert todos-nondiary-start)
		    (goto-char (1+ end))
		    (insert todos-nondiary-end))
		(when (looking-at (regexp-quote todos-nondiary-start))
		  (replace-match "")
		  (search-forward todos-nondiary-end (1+ end) t)
		  (replace-match "")))))
	  (todos-forward-item))
	(unless (if arg (zerop diary-count) (= diary-count todo-count))
	  (todos-update-count 'diary (if arg
				      (- diary-count)
				    (- todo-count diary-count))))
	(todos-update-categories-sexp)))))

(defun todos-edit-item-diary-nonmarking ()
  "Change non-marking of one or more diary items in this category.
That is, insert `diary-nonmarking-symbol' if the candidate items
lack this marking; otherwise, remove it.

If there are marked todo items, change the non-marking status of
all and only these, otherwise change the non-marking status of
the item at point."
  (interactive)
  (let ((buffer-read-only)
	(marked (assoc (todos-current-category)
		       todos-categories-with-marks)))
    (catch 'stop
      (save-excursion
	(when marked (goto-char (point-min)))
	(while (not (eobp))
	  (if (todos-done-item-p)
	      (throw 'stop (message "Done items cannot be edited"))
	    (unless (and marked (not (todos-marked-item-p)))
	      (todos-item-start)
	      (unless (looking-at (regexp-quote todos-nondiary-start))
		(if (looking-at (regexp-quote diary-nonmarking-symbol))
		    (replace-match "")
		  (insert diary-nonmarking-symbol))))
	    (unless marked (throw 'stop nil))
	    (todos-forward-item)))))))

(defun todos-edit-category-diary-nonmarking (arg)
  "Add `diary-nonmarking-symbol' to all diary items in this category.
With prefix ARG, remove `diary-nonmarking-symbol' from all diary
items in this category."
  (interactive "P")
  (save-excursion
    (goto-char (point-min))
    (let (buffer-read-only)
      (catch 'stop
      (while (not (eobp))
	(if (todos-done-item-p)		; We've gone too far.
	    (throw 'stop nil)
	  (unless (looking-at (regexp-quote todos-nondiary-start))
	    (if arg
		(when (looking-at (regexp-quote diary-nonmarking-symbol))
		  (replace-match ""))
	      (unless (looking-at (regexp-quote diary-nonmarking-symbol))
		(insert diary-nonmarking-symbol))))
	(todos-forward-item)))))))

(defun todos-set-item-priority (&optional item cat new arg)
  "Prompt for and set ITEM's priority in CATegory.

Interactively, ITEM is the todo item at point, CAT is the current
category, and the priority is a number between 1 and the number
of items in the category.  Non-interactively, non-nil NEW means
ITEM is a new item and the lowest priority is one more than the
number of items in CAT.

The new priority is set either interactively by prompt or by a
numerical prefix argument, or noninteractively by argument ARG,
whose value can be either of the symbols `raise' or `lower',
meaning to raise or lower the item's priority by one."
  (interactive)				;FIXME: Prefix arg?
  (unless (and (called-interactively-p 'any)
	       (or (todos-done-item-p) (looking-at "^$")))
    (let* ((item (or item (todos-item-string)))
	   (marked (todos-marked-item-p))
	   (cat (or cat (cond ((eq major-mode 'todos-mode)
			       (todos-current-category))
			      ((eq major-mode 'todos-filtered-items-mode)
			       (let* ((regexp1
				       (concat todos-date-string-start
					       todos-date-pattern
					       "\\( " diary-time-regexp "\\)?"
					       (regexp-quote todos-nondiary-end)
					       "?\\(?1: \\[\\(.+:\\)?.+\\]\\)")))
				 (save-excursion
				   (re-search-forward regexp1 nil t)
				   (match-string-no-properties 1)))))))
	   curnum
	   (todo (cond ((or (eq arg 'raise) (eq arg 'lower)
			    (eq major-mode 'todos-filtered-items-mode))
			(save-excursion
			  (let ((curstart (todos-item-start))
				(count 0))
			    (goto-char (point-min))
			    (while (looking-at todos-item-start)
			      (setq count (1+ count))
			      (when (= (point) curstart) (setq curnum count))
			      (todos-forward-item))
			    count)))
		       ((eq major-mode 'todos-mode)
			(todos-get-count 'todo cat))))
	   (maxnum (if new (1+ todo) todo))
	   (prompt (format "Set item priority (1-%d): " maxnum))
	   (priority (cond ((and (not arg) (numberp current-prefix-arg))
			    current-prefix-arg)
			   ((and (eq arg 'raise) (>= curnum 1))
			    (1- curnum))
			   ((and (eq arg 'lower) (<= curnum maxnum))
			    (1+ curnum))))
	   candidate
	   buffer-read-only)
      (unless (and priority
		   (or (and (eq arg 'raise) (zerop priority))
		       (and (eq arg 'lower) (> priority maxnum))))
	;; When moving item to another category, show the category before
	;; prompting for its priority.
	(unless (or arg (called-interactively-p 'any))
	  (todos-category-number cat)
	  ;; If done items in category are visible, keep them visible.
	  (let ((done todos-show-with-done))
	    (when (> (buffer-size) (- (point-max) (point-min)))
	      (save-excursion
		(goto-char (point-min))
		(setq done (re-search-forward todos-done-string-start nil t))))
	    (let ((todos-show-with-done done))
	      (todos-category-select))))
	;; Prompt for priority only when the category has at least one todo item.
	(when (> maxnum 1)
	  (while (not priority)
	    (setq candidate (read-number prompt))
	    (setq prompt (when (or (< candidate 1) (> candidate maxnum))
			   (format "Priority must be an integer between 1 and %d.\n"
				   maxnum)))
	    (unless prompt (setq priority candidate))))
	;; In Top Priorities buffer, an item's priority can be changed
	;; wrt items in another category, but not wrt items in the same
	;; category.
	(when (eq major-mode 'todos-filtered-items-mode)
	  (let* ((regexp2 (concat todos-date-string-start todos-date-pattern
				  "\\( " diary-time-regexp "\\)?"
				  (regexp-quote todos-nondiary-end)
				  "?\\(?1:" (regexp-quote cat) "\\)"))
		 (end (cond ((< curnum priority)
			     (save-excursion (todos-item-end)))
			    ((> curnum priority)
			     (save-excursion (todos-item-start)))))
		 (match (save-excursion
			  (cond ((< curnum priority)
				 (todos-forward-item (1+ (- priority curnum)))
				 (when (re-search-backward regexp2 end t)
				   (match-string-no-properties 1)))
				((> curnum priority)
				 (todos-backward-item (- curnum priority))
				 (when (re-search-forward regexp2 end t)
				   (match-string-no-properties 1)))))))
	    (when match
	      (error (concat "Cannot reprioritize items from the same "
			     "category in this mode, only in Todos mode")))))
	;; Interactively or with non-nil ARG, relocate the item within its
	;; category.
	(when (or arg (called-interactively-p 'any))
	  (todos-remove-item))
	(goto-char (point-min))
	(when priority
	  (unless (= priority 1)
	    (todos-forward-item (1- priority))
	    ;; When called from todos-item-undo and the highest priority
	    ;; is chosen, this advances point to the first done item, so
	    ;; move it up to the empty line above the done items
	    ;; separator.
	    (when (looking-back (concat "^"
					(regexp-quote todos-category-done) "\n"))
	      (todos-backward-item))))
	(todos-insert-with-overlays item)
	;; If item was marked, restore the mark.
	(and marked
	     (let* ((ov (todos-get-overlay 'prefix))
		    (pref (overlay-get ov 'before-string)))
	       (overlay-put ov 'before-string (concat todos-item-mark pref))))))))

(defun todos-raise-item-priority ()
  "Raise priority of current item by moving it up by one item."
  (interactive)
  (todos-set-item-priority nil nil nil 'raise))

(defun todos-lower-item-priority ()
  "Lower priority of current item by moving it down by one item."
  (interactive)
  (todos-set-item-priority nil nil nil 'lower))

(defun todos-move-item (&optional file)
  "Move at least one todo or done item to another category.
If there are marked items, move all of these; otherwise, move
the item at point.

With prefix argument FILE, prompt for a specific Todos file and
choose (with TAB completion) a category in it to move the item or
items to; otherwise, choose and move to any category in either
the current Todos file or one of the files in
`todos-category-completions-files'.  If the chosen category is
not an existing categories, then it is created and the item(s)
become(s) the first entry/entries in that category.

With moved Todo items, prompt to set the priority in the category
moved to (with multiple todos items, the one that had the highest
priority in the category moved from gets the new priority and the
rest of the moved todo items are inserted in sequence below it).
Moved done items are appended to the end of the done items
section in the category moved to."
  (interactive "P")
  (let* ((cat1 (todos-current-category))
	 (marked (assoc cat1 todos-categories-with-marks)))
    ;; NOP if point is not on an item and there are no marked items.
    (unless (and (looking-at "^$")
		 (not marked))
      (let* ((buffer-read-only)
	     (file1 todos-current-todos-file)
	     (num todos-category-number)
	     (item (todos-item-string))
	     (diary-item (todos-diary-item-p))
	     (done-item (and (todos-done-item-p) (concat item "\n")))
	     (omark (save-excursion (todos-item-start) (point-marker)))
	     (todo 0)
	     (diary 0)
	     (done 0)
	     ov cat+file cat2 file2 moved nmark todo-items done-items)
	(unwind-protect
	    (progn
	      (unless marked
		(setq ov (make-overlay (save-excursion (todos-item-start))
				       (save-excursion (todos-item-end))))
		(overlay-put ov 'face 'todos-search))
	      (setq cat+file (let ((pl (if (and marked (> (cdr marked) 1))
					   "s" "")))
			       (todos-read-category (concat "Move item" pl
							    " to category: ")
						    nil file))
		    cat2 (car cat+file)
		    file2 (cdr cat+file)))
	  (if ov (delete-overlay ov)))
	(set-buffer (find-buffer-visiting file1))
	(if marked
	    (progn
	      (goto-char (point-min))
	      (while (not (eobp))
		(when (todos-marked-item-p)
		  (if (todos-done-item-p)
		      (setq done-items (concat done-items
					       (todos-item-string) "\n")
			    done (1+ done))
		    (setq todo-items (concat todo-items
					     (todos-item-string) "\n")
			  todo (1+ todo))
		    (when (todos-diary-item-p)
		      (setq diary (1+ diary)))))
		(todos-forward-item))
	      ;; Chop off last newline of multiple todo item string,
	      ;; since it will be reinserted when setting priority
	      ;; (but with done items priority is not set, so keep
	      ;; last newline).
	      (and todo-items
		   (setq todo-items (substring todo-items 0 -1))))
	  (if (todos-done-item-p)
	      (setq done 1)
	    (setq todo 1)
	    (when (todos-diary-item-p) (setq diary 1))))
	(set-window-buffer (selected-window)
			   (set-buffer (find-file-noselect file2 'nowarn)))
	(unwind-protect
	    (progn
	      (when (or todo-items (and item (not done-item)))
		(todos-set-item-priority (or todo-items item) cat2 t))
	      ;; Move done items en bloc to end of done item section.
	      (when (or done-items done-item)
		(todos-category-number cat2)
		(widen)
		(goto-char (point-min))
		(re-search-forward (concat "^" (regexp-quote
						(concat todos-category-beg cat2))
					   "$")
				   nil t)
		(goto-char (if (re-search-forward
				(concat "^" (regexp-quote todos-category-beg))
				nil t)
			       (match-beginning 0)
			     (point-max)))
		(insert (or done-items done-item)))
	      (setq moved t))
	  (cond
	   ;; Move succeeded, so remove item from starting category,
	   ;; update item counts and display the category containing
	   ;; the moved item.
	   (moved
	    (setq nmark (point-marker))
	    (when todo (todos-update-count 'todo todo))
	    (when diary (todos-update-count 'diary diary))
	    (when done (todos-update-count 'done done))
	    (todos-update-categories-sexp)
	    (with-current-buffer (find-buffer-visiting file1)
	      (save-excursion
		(save-restriction
		  (widen)
		  (goto-char omark)
		  (if marked
		      (let (beg end)
			(setq item nil)
			(re-search-backward
			 (concat "^" (regexp-quote todos-category-beg)) nil t)
			(forward-line)
			(setq beg (point))
			(setq end (if (re-search-forward
				       (concat "^" (regexp-quote
						    todos-category-beg)) nil t)
				      (match-beginning 0)
				    (point-max)))
			(goto-char beg)
			(while (< (point) end)
			  (if (todos-marked-item-p)
			      (todos-remove-item)
			    (todos-forward-item)))
			(setq todos-categories-with-marks
			      (assq-delete-all cat1 todos-categories-with-marks)))
		    (if ov (delete-overlay ov))
		    (todos-remove-item))))
	      (when todo (todos-update-count 'todo (- todo) cat1))
	      (when diary (todos-update-count 'diary (- diary) cat1))
	      (when done (todos-update-count 'done (- done) cat1))
	      (todos-update-categories-sexp))
	    (set-window-buffer (selected-window)
			       (set-buffer (find-file-noselect file2 'nowarn)))
	    (setq todos-category-number (todos-category-number cat2))
	    (let ((todos-show-with-done (or done-items done-item)))
	      (todos-category-select))
	    (goto-char nmark)
	    ;; If item is moved to end of (just first?) category, make
	    ;; sure the items above it are displayed in the window.
	    (recenter))
	   ;; User quit before setting priority of todo item(s), so
	   ;; return to starting category.
	   (t
	    (todos-category-number cat1)
	    (todos-category-select)
	    (goto-char omark))))))))

(defun todos-item-done (&optional arg)
  "Tag a todo item in this category as done and relocate it.

With prefix argument ARG prompt for a comment and append it to
the done item; this is only possible if there are no marked
items.  If there are marked items, tag all of these with
`todos-done-string' plus the current date and, if
`todos-always-add-time-string' is non-nil, the current time;
otherwise, just tag the item at point.  Items tagged as done are
relocated to the category's (by default hidden) done section.  If
done items are visible on invoking this command, they remain
visible."
  (interactive "P")
  (let* ((cat (todos-current-category))
	 (marked (assoc cat todos-categories-with-marks)))
    (unless (or (todos-done-item-p) 
		;; Point is between todo and done items.
		(and (looking-at "^$") (not marked)))
      (let* ((date-string (calendar-date-string (calendar-current-date) t t))
	     (time-string (if todos-always-add-time-string
			      (concat " " (substring (current-time-string) 11 16))
			    ""))
	     (done-prefix (concat "[" todos-done-string date-string time-string
				  "] "))
	     (comment (and arg (read-string "Enter a comment: ")))
	     (item-count 0)
	     (diary-count 0)
	     (show-done (save-excursion
			  (goto-char (point-min))
			  (re-search-forward todos-done-string-start nil t)))
	     (buffer-read-only nil)
	     item done-item opoint)
	;; Don't add empty comment to done item.
	(setq comment (unless (zerop (length comment))
			(concat " [" todos-comment-string ": " comment "]")))
	(and marked (goto-char (point-min)))
	(catch 'done
	  ;; Stop looping when we hit the empty line below the last
	  ;; todo item (this is eobp if only done items are hidden).
	  (while (not (looking-at "^$")) ;(not (eobp))
	    (if (or (not marked) (and marked (todos-marked-item-p)))
		(progn
		  (setq item (todos-item-string))
		  (setq done-item (concat done-item done-prefix item
					  comment (and marked "\n")))
		  (setq item-count (1+ item-count))
		  (when (todos-diary-item-p)
		    (setq diary-count (1+ diary-count)))
		  (todos-remove-item)
		  (unless marked (throw 'done nil)))
	      (todos-forward-item))))
	(when marked
	  ;; Chop off last newline of done item string.
	  (setq done-item (substring done-item 0 -1))
	  (setq todos-categories-with-marks
		(assq-delete-all cat todos-categories-with-marks)))
	(save-excursion
	  (widen)
	  (re-search-forward
	   (concat "^" (regexp-quote todos-category-done)) nil t)
	  (forward-char)
	  (when show-done (setq opoint (point)))
	  (insert done-item "\n"))
	(todos-update-count 'todo (- item-count))
	(todos-update-count 'done item-count)
	(todos-update-count 'diary (- diary-count))
	(todos-update-categories-sexp)
	(let ((todos-show-with-done show-done))
	  (todos-category-select)
	  ;; When done items are shown, put cursor on first just done item.
	  (when opoint (goto-char opoint)))))))

(defun todos-done-item-add-edit-or-delete-comment (&optional arg)
  "Add a comment to this done item or edit an existing comment.
With prefix ARG delete an existing comment."
  (interactive "P")
  (when (todos-done-item-p)
    (let ((item (todos-item-string))
	  (opoint (point))
	  (end (save-excursion (todos-item-end)))
	  comment buffer-read-only)
      (save-excursion
	(todos-item-start)
	(if (re-search-forward (concat " \\["
				       (regexp-quote todos-comment-string)
				       ": \\([^]]+\\)\\]") end t)
	    (if arg
		(when (y-or-n-p "Delete comment? ")
		  (delete-region (match-beginning 0) (match-end 0)))
	      (setq comment (read-string "Edit comment: "
					 (cons (match-string 1) 1)))
	      (replace-match comment nil nil nil 1))
	  (setq comment (read-string "Enter a comment: "))
	  ;; If user moved point during editing, make sure it moves back.
	  (goto-char opoint)
	  (todos-item-end)
	  (insert " [" todos-comment-string ": " comment "]"))))))

(defun todos-item-undo ()
  "Restore this done item to the todo section of this category.
If done item has a comment, ask whether to omit the comment from
the restored item."			;FIXME: marked done items
  (interactive)
  (let* ((cat (todos-current-category))
	 (marked (assoc cat todos-categories-with-marks)))
    (when (or marked (todos-done-item-p))
      (let ((buffer-read-only)
	    (bufmod (buffer-modified-p))
	    (opoint (point))
	    (orig-mrk (progn (todos-item-start) (point-marker)))
	    (orig-item (todos-item-string))
	    (first 'first)
	    (item-count 0)
	    (diary-count 0)
	    start end item undone)
	(and marked (goto-char (point-min)))
	(catch 'done
	  (while (not (eobp))
	    (if (or (not marked) (and marked (todos-marked-item-p)))
		(if (not (todos-done-item-p))
		    (error "Only done items can be undone")
		  (todos-item-start)
		  ;; Find the end of the date string added upon tagging item as
		  ;; done.
		  (setq start (search-forward "] "))
		  (setq item-count (1+ item-count))
		  (unless (looking-at (regexp-quote todos-nondiary-start))
		    (setq diary-count (1+ diary-count)))
		  (setq end (save-excursion (todos-item-end)))
		  ;; Ask (once) whether to omit done item's comment.  If
		  ;; affirmed, omit subsequent comments without asking.
		  (when (re-search-forward
			 (concat " \\[" (regexp-quote todos-comment-string)
				 ": [^]]+\\]") end t)
		    (if (eq first 'first)
			(setq first
			      (if (eq todos-undo-item-omit-comment 'ask)
				  (when (y-or-n-p
					 "Omit comment from restored item? ")
				    'omit)
				(when todos-undo-item-omit-comment 'omit)))
		      t)
		    (when (eq first 'omit)
		      (delete-region (match-beginning 0) (match-end 0))
		      (setq end (point))))
		  (setq item (concat item
				     (buffer-substring-no-properties start end)
				     (when marked "\n")))
		  (todos-remove-item)
		  (unless marked (throw 'done nil)))
	      (todos-forward-item))))
	(if marked
	    (progn
	      (setq todos-categories-with-marks
		    (assq-delete-all cat todos-categories-with-marks))
	      ;; Insert undone items that were marked at end of todo item list.
	      (goto-char (point-min))
	      (re-search-forward (concat "^" (regexp-quote todos-category-done))
				 nil t)
	      (forward-line -1)
	      (insert item)
	      (todos-update-count 'todo item-count)
	      (todos-update-count 'done (- item-count))
	      (when diary-count (todos-update-count 'diary diary-count))
	      (todos-update-categories-sexp)
	      (let ((todos-show-with-done (> (todos-get-count 'done) 0)))
		(todos-category-select)))
	  ;; With an unmarked undone item, prompt for its priority.  If user
	  ;; cancels before setting new priority, then leave the done item
	  ;; unchanged.
	  (unwind-protect
	      (progn
		(todos-set-item-priority item (todos-current-category) t)
		(setq undone t
		      opoint (point))
		(todos-update-count 'todo 1)
		(todos-update-count 'done -1)
		(and (todos-diary-item-p) (todos-update-count 'diary 1))
		(todos-update-categories-sexp)
		(let ((todos-show-with-done (> (todos-get-count 'done) 0)))
		  (todos-category-select)
		  ;; Put the cursor on the undone item.
		  (goto-char opoint)))
	    (unless undone
	      (let ((todos-show-with-done t))
		(widen)
		(goto-char orig-mrk)
		(todos-insert-with-overlays orig-item)
		(set-buffer-modified-p bufmod)
		(todos-category-select))
		(goto-char opoint))))
	(set-marker orig-mrk nil)))))

(defun todos-archive-done-item (&optional all)
  "Archive at least one done item in this category.

If there are marked done items (and no marked todo items),
archive all of these; otherwise, with non-nil argument ALL,
archive all done items in this category; otherwise, archive the
done item at point.

If the archive of this file does not exist, it is created.  If
this category does not exist in the archive, it is created."
  (interactive)
  (when (eq major-mode 'todos-mode)
    (if (and all (zerop (todos-get-count 'done)))
	(message "No done items in this category")
      (catch 'end
	(let* ((cat (todos-current-category))
	       (tbuf (current-buffer))
	       (marked (assoc cat todos-categories-with-marks))
	       (afile (concat (file-name-sans-extension
			       todos-current-todos-file) ".toda"))
	       (archive (if (file-exists-p afile)
			    (find-file-noselect afile t)
			  (get-buffer-create afile)))
	       (item (and (todos-done-item-p) (concat (todos-item-string) "\n")))
	       (count 0)
	       (opoint (unless (todos-done-item-p) (point)))
	       marked-items beg end all-done
	       buffer-read-only)
	  (cond
	   (marked
	    (save-excursion
	      (goto-char (point-min))
	      (while (not (eobp))
		(when (todos-marked-item-p)
		  (if (not (todos-done-item-p))
		      (throw 'end (message "Only done items can be archived"))
		    (setq marked-items
			  (concat marked-items (todos-item-string) "\n"))
		    (setq count (1+ count))))
		(todos-forward-item))))
	   (all
	    (if (y-or-n-p "Archive all done items in this category? ")
		(save-excursion
		  (save-restriction
		    (goto-char (point-min))
		    (widen)
		    (setq beg (progn
				(re-search-forward todos-done-string-start nil t)
				(match-beginning 0))
			  end (if (re-search-forward
				   (concat "^" (regexp-quote todos-category-beg))
				   nil t)
				  (match-beginning 0)
				(point-max))
			  all-done (buffer-substring-no-properties beg end)
			  count (todos-get-count 'done))
		    ;; Restore starting point, unless it was on a done
		    ;; item, since they will all be deleted.
		    (when opoint (goto-char opoint))))
	      (throw 'end nil))))
	  (if (not (or marked all item))
	      (throw 'end (message "Only done items can be archived"))
	    (with-current-buffer archive
	      (unless buffer-file-name (erase-buffer))
	      (let (buffer-read-only)
		(widen)
		(goto-char (point-min))
		(if (and (re-search-forward
			  (concat "^" (regexp-quote
				       (concat todos-category-beg cat)) "$")
			  nil t)
			 (re-search-forward (regexp-quote todos-category-done)
					    nil t))
		    ;; Start of done items section in existing category.
		    (forward-char)
		  (todos-add-category nil cat)
		  ;; Start of done items section in new category.
		  (goto-char (point-max)))
		(insert (cond (marked marked-items)
			      (all all-done)
			      (item)))
		(todos-update-count 'done (if (or marked all) count 1) cat)
		(todos-update-categories-sexp)
		;; If archive is new, save to file now (using write-region in
		;; order not to get prompted for file to save to), to let
		;; auto-mode-alist take effect below.
		(unless buffer-file-name
		  (write-region nil nil afile)
		  (kill-buffer))))
	    (with-current-buffer tbuf
	      (cond ((or marked
			 ;; If we're archiving all done items, can't
			 ;; first archive item point was on, since
			 ;; that will short-circuit the rest.
			 (and item (not all)))
		     (and marked (goto-char (point-min)))
		     (catch 'done
		       (while (not (eobp))
			 (if (or (and marked (todos-marked-item-p)) item)
			     (progn
			       (todos-remove-item)
			       (todos-update-count 'done -1)
			       (todos-update-count 'archived 1)
			       ;; Don't leave point below last item.
			       (and item (bolp) (eolp) (< (point-min) (point-max))
				    (todos-backward-item))
			       (when item 
				 (throw 'done (setq item nil))))
			   (todos-forward-item)))))
		    (all
		     (save-excursion
		       (save-restriction
			 ;; Make sure done items are accessible.
			 (widen)
			 (remove-overlays beg end)
			 (delete-region beg end)
			 (todos-update-count 'done (- count))
			 (todos-update-count 'archived count)))))
	      (when marked
		(setq todos-categories-with-marks
		      (assq-delete-all cat todos-categories-with-marks)))
	      (todos-update-categories-sexp)
	      (todos-prefix-overlays)))
	  (find-file afile)
	  (todos-category-number cat)
	  (todos-category-select)
	  (split-window-below)
	  (set-window-buffer (selected-window) tbuf)
	  ;; Make todo file current to select category.
	  (find-file (buffer-file-name tbuf))
	  ;; Make sure done item separator is hidden (if done items
	  ;; were initially visible).
	  (let (todos-show-with-done) (todos-category-select)))))))

(defun todos-archive-category-done-items ()
  "Move all done items in this category to its archive."
  (interactive)
  (todos-archive-done-item t))

(defun todos-unarchive-items ()
  "Unarchive at least one item in this archive category.
If there are marked items, unarchive all of these; otherwise,
unarchive the item at point.

Unarchived items are restored as done items to the corresponding
category in the Todos file, inserted at the end of done items
section.  If all items in the archive category have been
restored, the category is deleted from the archive.  If this was
the only category in the archive, the archive file is deleted."
  (interactive)
  (when (eq major-mode 'todos-archive-mode)
    (let* ((cat (todos-current-category))
	   (tbuf (find-file-noselect
		  (concat (file-name-sans-extension todos-current-todos-file)
			  ".todo") t))
	   (marked (assoc cat todos-categories-with-marks))
	   (item (concat (todos-item-string) "\n"))
	   (marked-count 0)
	   marked-items
	   buffer-read-only)
      (when marked
	(save-excursion
	  (goto-char (point-min))
	  (while (not (eobp))
	    (when (todos-marked-item-p)
	      (setq marked-items (concat marked-items (todos-item-string) "\n"))
	      (setq marked-count (1+ marked-count)))
	    (todos-forward-item))))
      ;; Restore items to end of category's done section and update counts.
      (with-current-buffer tbuf
	(let (buffer-read-only newcat)
	  (widen)
	  (goto-char (point-min))
	  ;; Find the corresponding todo category, or if there isn't
	  ;; one, add it.
	  (unless (re-search-forward
		   (concat "^" (regexp-quote (concat todos-category-beg cat))
			   "$") nil t)
	    (todos-add-category nil cat)
	    (setq newcat t)
	    ;; Put point below newly added category beginning,
	    ;; otherwise the following search wrongly succeeds.
	    (forward-line))
	  ;; Go to end of category's done section.
	  (if (re-search-forward (concat "^" (regexp-quote todos-category-beg))
				 nil t)
	      (goto-char (match-beginning 0))
	    (goto-char (point-max)))
	  (cond (marked
		 (insert marked-items)
		 (todos-update-count 'done marked-count cat)
		 (unless newcat		; Newly added category has no archive.
		   (todos-update-count 'archived (- marked-count) cat)))
		(t
		 (insert item)
		 (todos-update-count 'done 1 cat)
		 (unless newcat		; Newly added category has no archive.
		   (todos-update-count 'archived -1 cat))))
	  (todos-update-categories-sexp)))
      ;; Delete restored items from archive.
      (when marked
	(setq item nil)
	(goto-char (point-min)))
      (catch 'done
	(while (not (eobp))
	  (if (or (todos-marked-item-p) item)
	      (progn
		(todos-remove-item)
		(when item
		  (throw 'done (setq item nil))))
	    (todos-forward-item))))
      (todos-update-count 'done (if marked (- marked-count) -1) cat)
      ;; If that was the last category in the archive, delete the whole file.
      (if (= (length todos-categories) 1)
	  (progn
	    (delete-file todos-current-todos-file)
	    ;; Kill the archive buffer silently.
	    (set-buffer-modified-p nil)
	    (kill-buffer))
	;; Otherwise, if the archive category is now empty, delete it.
	(when (eq (point-min) (point-max))
	  (widen)
	  (let ((beg (re-search-backward
		      (concat "^" (regexp-quote todos-category-beg) cat "$")
		      nil t))
		(end (if (re-search-forward
			  (concat "^" (regexp-quote todos-category-beg))
			  nil t 2)
			 (match-beginning 0)
		       (point-max))))
	    (remove-overlays beg end)
	    (delete-region beg end)
	    (setq todos-categories (delete (assoc cat todos-categories)
					   todos-categories))
	    (todos-update-categories-sexp))))
      ;; Visit category in Todos file and show restored done items.
      (let ((tfile (buffer-file-name tbuf))
	    (todos-show-with-done t))
	(set-window-buffer (selected-window)
			   (set-buffer (find-file-noselect tfile)))
	(todos-category-number cat)
	(todos-category-select)
	(message "Items unarchived.")))))

(provide 'todos)

;;; todos.el ends here

;; FIXME: remove when part of Emacs
;; ---------------------------------------------------------------------------
(add-to-list 'auto-mode-alist '("\\.todo\\'" . todos-mode))
(add-to-list 'auto-mode-alist '("\\.toda\\'" . todos-archive-mode))
(add-to-list 'auto-mode-alist '("\\.tod[tyr]\\'" . todos-filtered-items-mode))

;;; Addition to calendar.el
;; FIXME: autoload when key-binding is defined in calendar.el
(defun todos-insert-item-from-calendar (&optional arg)
  ""
  (interactive "P")
  (setq todos-date-from-calendar
	(calendar-date-string (calendar-cursor-to-date t) t t))
  (calendar-exit)
  (todos-show)
  (todos-insert-item arg nil nil todos-date-from-calendar))

(define-key calendar-mode-map "it" 'todos-insert-item-from-calendar)

;;; necessitated adaptations to diary-lib.el

;; (defun diary-goto-entry (button)
;;   "Jump to the diary entry for the BUTTON at point."
;;   (let* ((locator (button-get button 'locator))
;;          (marker (car locator))
;;          markbuf file opoint)
;;     ;; If marker pointing to diary location is valid, use that.
;;     (if (and marker (setq markbuf (marker-buffer marker)))
;;         (progn
;;           (pop-to-buffer markbuf)
;;           (goto-char (marker-position marker)))
;;       ;; Marker is invalid (eg buffer has been killed, as is the case with
;;       ;; included diary files).
;;       (or (and (setq file (cadr locator))
;;                (file-exists-p file)
;;                (find-file-other-window file)
;;                (progn
;;                  (when (eq major-mode (default-value 'major-mode)) (diary-mode))
;; 		 (when (eq major-mode 'todos-mode) (widen))
;;                  (goto-char (point-min))
;;                  (when (re-search-forward (format "%s.*\\(%s\\)"
;; 						  (regexp-quote (nth 2 locator))
;; 						  (regexp-quote (nth 3 locator)))
;; 					  nil t)
;; 		   (goto-char (match-beginning 1))
;; 		   (when (eq major-mode 'todos-mode)
;; 		     (setq opoint (point))
;; 		     (re-search-backward (concat "^"
;; 						 (regexp-quote todos-category-beg)
;; 						 "\\(.*\\)\n")
;; 					 nil t)
;; 		     (todos-category-number (match-string 1))
;; 		     (todos-category-select)
;; 		     (goto-char opoint)))))
;;           (message "Unable to locate this diary entry")))))
