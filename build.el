;;; build.el --- Site Build Script -*- lexical-binding: t; -*-

;;; Commentary:

;;; Code:

(push (expand-file-name "./contrib") load-path)

(require 'cl-lib)

(require 'org)
(require 'ox-html-stable-ids)
(require 'ox-publish)
(require 'ox-rss)

(require 'simple-httpd)

(setq confirm-kill-processes nil)
(setq debug-on-error t)
(setq make-backup-files nil)

(load-theme 'standard-light :no-confirm)

;; General Helpers

(defun site--read-files (&rest paths)
  "Read contents of files at PATHS and return the concatenated contents."
  (mapconcat #'site--read-file paths nil))

(defun site--read-file (path)
  "Read contents of file at PATH."
  (with-temp-buffer
    (insert-file-contents (expand-file-name path site--source-directory))
    (buffer-string)))

(defun site--filter-local-links (link backend info)
  "LINK BACKEND INFO; Convert all /index.html links to /."
  (if (org-export-derived-backend-p backend 'html)
      (replace-regexp-in-string "/index.html" "/" link)))

(defun site--format-date-string (date)
  "Format DATE."
  (format-time-string site--date-format-string date))

;; Posts: Helpers

(defun site--org-html-publish-post-to-html (plist filename pub-dir)
  "PLIST FILENAME PUB-DIR."
  (let* ((format-string (format "Published %s" site--date-format-string))
         (time (org-publish-find-date filename (cons 'tmp plist)))
         (subtitle (format-time-string format-string time)))
    (plist-put plist :subtitle subtitle))
  (org-html-publish-to-html plist filename pub-dir))

;; Posts: Sitemap Helpers

(defun site--publish-sitemap-filename-only (publishing-function plist filename pub-dir)
  "PUBLISHING-FUNCTION PLIST FILENAME PUB-DIR."
  (let* ((base-directory (plist-get plist :base-directory))
         (sitemap-filename (plist-get plist :sitemap-filename))
         (absolute-sitemap-filename (expand-file-name sitemap-filename base-directory)))
    (if (equal absolute-sitemap-filename filename)
        (funcall publishing-function plist filename pub-dir))))

(defun site--org-html-publish-sitemap-to-html (plist filename pub-dir)
  "PLIST FILENAME PUB-DIR."
  (site--publish-sitemap-filename-only #'org-html-publish-to-html plist filename pub-dir))

(defun site--format-sitemap (title list)
  "TITLE LIST."
  (concat
   (site--read-file "partials/posts/preamble.org")
   (org-list-to-org list)))

(defun site--format-sitemap-entry (entry style project)
  "ENTRY STYLE PROJECT. Style is assumed to be list."
  (let ((title (org-publish-find-title entry project))
        (date (site--format-date-string (org-publish-find-date entry project))))
    (format "%s [[file:%s][%s]]" date entry title)))

;; Posts: RSS Helpers

(defun site--org-rss-publish-sitemap-to-rss (plist filename pub-dir)
  "PLIST FILENAME PUB-DIR."
  (site--publish-sitemap-filename-only #'org-rss-publish-to-rss plist filename pub-dir))

(defun site--format-rss-feed (title list)
  "TITLE LIST."
  (concat
   (format "#+TITLE: %s\n" title)
   (org-list-to-subtree list 1 '(:icount "" :istart ""))))

;; TODO: Simplify.
;; TODO: Decide how much of the post I want to put into the RSS entry's description.
(defun site--format-rss-feed-entry (entry style project)
  "ENTRY STYLE PROJECT. Style is assumed to be list."
  (let ((file (org-publish--expand-file-name entry project))
        (title (org-publish-find-title entry project))
        (date (site--format-date-string (org-publish-find-date entry project))))
    (with-temp-buffer
      (org-mode)
      (insert (format "* [[file:%s][%s]]\n:PROPERTIES:\n:END:\n" entry title))
      (org-set-property "RSS_PERMALINK" (replace-regexp-in-string "/index.org$" "/" entry))
      (org-set-property "RSS_TITLE" title)
      (org-set-property "PUBDATE" date)
      ;; (insert-file-contents file)
      (buffer-string))))

(defun site--exclude-non-emacs-posts (project-plist)
  "PROJECT-PLIST."
  (let* ((base-dir (plist-get project-plist :base-directory))
         (exclude-regexp (plist-get project-plist :exclude))
         (additional-files-to-exclude '()))
    (dolist (file (directory-files-recursively base-dir "\\.org$"))
      (let ((file-relative-name (file-relative-name file base-dir)))
        (unless (and exclude-regexp (string-match-p exclude-regexp file-relative-name))
          (unless (site--file-has-file-tag-p file "emacs")
            (push file-relative-name additional-files-to-exclude)))))
    (when additional-files-to-exclude
      (plist-put project-plist :exclude
                 (concat (or exclude-regexp "")
                         (if exclude-regexp "\\|" "")
                         (string-join additional-files-to-exclude "\\|"))))))

(defun site--file-has-file-tag-p (file tag)
  "FILE TAG."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let ((case-fold-search t))
      (when (re-search-forward "^#\\+FILETAGS:\\s-*\\(.*\\)$" nil t)
        (member tag (split-string (match-string 1) ":" t))))))

;; Required Configuration

(add-to-list 'org-export-filter-link-functions #'site--filter-local-links)

(defvar site--project-alist
  (list
   (list "posts-org"
         :base-directory (expand-file-name "posts" site--source-directory)
         :base-extension "org"
         :publishing-directory (expand-file-name "posts" site--build-directory)
         :recursive t
         :exclude "^\\(index\\|^rss\\|^rss-emacs\\).org"
         :publishing-function #'site--org-html-publish-post-to-html
         :html-postamble (site--read-files "partials/posts/footer.html" "partials/footer.html"))

   (list "posts-sitemap"
         :base-directory (expand-file-name "posts" site--source-directory)
         :base-extension "org"
         :publishing-directory (expand-file-name "posts" site--build-directory)
         :recursive t
         :exclude "^\\(index\\|^rss\\|^rss-emacs\\).org"
         :publishing-function #'site--org-html-publish-sitemap-to-html
         :auto-sitemap t
         :sitemap-filename "index.org"
         :sitemap-title site--title
         :sitemap-style 'list
         :sitemap-sort-files 'anti-chronologically
         :sitemap-function #'site--format-sitemap
         :sitemap-format-entry #'site--format-sitemap-entry)

   (list "posts-assets"
         :base-directory (expand-file-name "posts" site--source-directory)
         :base-extension (regexp-opt '("png" "jpg" "jpeg" "gif" "pdf" "svg" "txt"))
         :publishing-directory (expand-file-name "posts" site--build-directory)
         :recursive t
         :publishing-function #'org-publish-attachment)

   (list "posts-rss"
         :base-directory (expand-file-name "posts" site--source-directory)
         :base-extension "org"
         :publishing-directory (expand-file-name "posts" site--build-directory)
         :recursive t
         :exclude "^\\(index\\|rss\\|rss-emacs\\).org"
         :publishing-function #'site--org-rss-publish-sitemap-to-rss
         :html-link-home (concat site--url "/posts/")
         :auto-sitemap t
         :sitemap-filename "rss.org"
         :sitemap-title site--title
         :sitemap-style 'list
         :sitemap-sort-files 'anti-chronologically
         :sitemap-function #'site--format-rss-feed
         :sitemap-format-entry #'site--format-rss-feed-entry
         :rss-image-url nil ;; TODO
         :rss-extension "xml")

   (list "posts-rss-emacs"
         :base-directory (expand-file-name "posts" site--source-directory)
         :base-extension "org"
         :publishing-directory (expand-file-name "posts" site--build-directory)
         :preparation-function #'site--exclude-non-emacs-posts
         :recursive t
         :exclude "^\\(index\\|rss\\|rss-emacs\\).org"
         :publishing-function #'site--org-rss-publish-sitemap-to-rss
         :html-link-home (concat site--url "/posts/")
         :auto-sitemap t
         :sitemap-filename "rss-emacs.org"
         :sitemap-title site--title
         :sitemap-style 'list
         :sitemap-sort-files 'anti-chronologically
         :sitemap-function #'site--format-rss-feed
         :sitemap-format-entry #'site--format-rss-feed-entry
         :rss-image-url nil ;; TODO
         :rss-extension "xml")

   (list "static-org"
         :base-directory (expand-file-name "static" site--source-directory)
         :base-extension "org"
         :publishing-directory site--build-directory
         :recursive t
         :publishing-function #'org-html-publish-to-html)

   (list "static-assets"
         :base-directory (expand-file-name "static" site--source-directory)
         :base-extension (regexp-opt '("css" "js" "ico" "png" "jpg" "jpeg" "gif" "pdf" "svg" "txt"))
         :publishing-directory site--build-directory
         :recursive t
         :publishing-function #'org-publish-attachment)

   (list "cname"
         :base-directory site--source-directory
         :exclude ".*"
         :include '("CNAME")
         :publishing-directory site--build-directory
         :publishing-function #'org-publish-attachment)

   (list "site"
         :components '("posts-org" "posts-sitemap" "posts-assets" "posts-rss" "posts-rss-emacs" "static-org" "static-assets" "cname"))))

(defun build ()
  "Foobar."
  (let ((org-export-time-stamp-file nil)
        (org-export-with-section-numbers nil)
        (org-export-with-toc nil)

        (org-html-checkbox-type 'html)
        (org-html-container-element "section")
        (org-html-head (site--read-file "partials/head.html"))
        (org-html-head-include-default-style nil)
        (org-html-head-include-scripts nil)
        (org-html-link-use-abs-url nil) ;; also see main.js
        (org-html-metadata-timestamp-format site--date-format-string)
        (org-html-postamble (site--read-file "partials/footer.html"))
        (org-html-preamble (site--read-file "partials/header.html"))
        (org-html-stable-ids t)
        (org-html-validation-link nil)

        (org-publish-timestamp-directory ".timestamps/")
        (org-publish-project-alist site--project-alist)

        (user-full-name site--author)
        (user-mail-address site--email))
    (org-html-stable-ids-add)
    (org-publish "site" t)
    (kill-emacs)))

(defun serve ()
  "Foobar."
  (let ((httpd-host "0.0.0.0")
        (httpd-port 8088))
    (httpd-serve-directory site--build-directory)))

(provide 'build)
;;; build.el ends here
