;;; .emacs --- Emacs Initialization File -*- lexical-binding: t; -*-

;;; Commentary:

;;; Code:

(require 'package)

(setq package-user-dir (expand-file-name ".packages"))

(setq package-archives
      '(("melpa" . "https://melpa.org/packages/")
        ("gnu" . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")))

(package-initialize)

(unless package-archive-contents
  (package-refresh-contents))

(package-install 'htmlize)
(package-install 'org)
(package-install 'org-contrib)
(package-install 'ox-rss)
(package-install 'simple-httpd)
(package-install 'standard-themes)

;;; .emacs ends here
