;;; build.el --- Site Build Script -*- lexical-binding: t; -*-

;;; Commentary:

;;; Code:

(push (expand-file-name "./contrib") load-path)

(require 'cl-lib)
(require 'filenotify)

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

(defun site--post-date-string (file)
  "Return the #+last_modified or #+date keyword value from FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((case-fold-search t))
      (or (and (re-search-forward "^#\\+last_modified:\\s-*\\(\\[.*?\\]\\)" nil t)
               (match-string 1))
          (and (goto-char (point-min))
               (re-search-forward "^#\\+date:\\s-*\\(\\[.*?\\]\\)" nil t)
               (match-string 1))))))

(defun site--restore-post-mtimes ()
  "Set each post's mtime from its #+last_modified: or #+date: keyword."
  (let ((posts-dir (expand-file-name "posts" site--source-directory)))
    (dolist (file (directory-files-recursively posts-dir "^index\\.org$"))
      (unless (string= (file-name-directory file) (file-name-as-directory posts-dir))
        (when-let* ((date-string (site--post-date-string file)))
          (set-file-times file (org-time-string-to-time date-string)))))))

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
   (site--read-file "partials/posts/sitemap-header-inner.org")
   (org-list-to-org list)))

(defun site--format-sitemap-entry (entry style project)
  "ENTRY STYLE PROJECT. Style is assumed to be list."
  (let ((title (org-publish-find-title entry project))
        (date (site--format-date-string (org-publish-find-date entry project))))
    (format "%s [[file:%s][%s]]" date entry title)))

;; Posts: RSS Helpers

(defun site--normalize-rss-channel-dates ()
  "Normalize channel dates in all RSS feeds in `site--project-alist'."
  (dolist (project site--project-alist)
    (let ((plist (cdr project)))
      (when (eq (plist-get plist :publishing-function) #'site--org-rss-publish-sitemap-to-rss)
        (site--normalize-rss-file-channel-dates
         (expand-file-name
          (concat (file-name-sans-extension (plist-get plist :sitemap-filename))
                  "." (plist-get plist :rss-extension))
          (plist-get plist :publishing-directory)))))))

(defun site--normalize-rss-file-channel-dates (rss-file)
  "Set channel pubDate/lastBuildDate in RSS-FILE to the most recent item date."
  (with-temp-buffer
    (insert-file-contents rss-file)
    (let ((items-start (save-excursion
                         (goto-char (point-min))
                         (and (re-search-forward "<item>" nil t)
                              (match-beginning 0)))))
      (when items-start
        (let ((most-recent nil))
          (goto-char items-start)
          (while (re-search-forward "<pubDate>\\([^<]+\\)</pubDate>" nil t)
            (let ((time (date-to-time (match-string 1))))
              (when (or (null most-recent) (time-less-p most-recent time))
                (setq most-recent time))))
          (when most-recent
            (let ((date-string (let ((system-time-locale "C"))
                                 (format-time-string "%a, %d %b %Y %T %z" most-recent))))
              (dolist (tag '("pubDate" "lastBuildDate"))
                (goto-char (point-min))
                (when (re-search-forward (format "<%s>[^<]*</%s>" tag tag) items-start t)
                  (replace-match (format "<%s>%s</%s>" tag date-string tag))))
              (write-region (point-min) (point-max) rss-file))))))))

(defun site--org-rss-publish-sitemap-to-rss (plist filename pub-dir)
  "PLIST FILENAME PUB-DIR."
  (site--publish-sitemap-filename-only #'org-rss-publish-to-rss plist filename pub-dir))

(defun site--format-rss-feed (title list)
  "TITLE LIST."
  (concat
   (format "#+TITLE: %s\n" title)
   (org-list-to-subtree list 1 '(:icount "" :istart ""))))

;; TODO: Simplify.
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

      ;; TODO: Decide how much of the post I want to put into the RSS entry's description.
      ;; TODO: Alternatively, (insert-file-contents file)
      (when-let* ((description (with-temp-buffer
                                 (org-mode)
                                 (insert-file-contents file)
                                 (cadr (assoc "DESCRIPTION" (org-collect-keywords '("description")))))))
        (insert description))

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
         :html-preamble (site--read-files "partials/header.html" "partials/posts/header-inner.html")
         :html-postamble (site--read-files "partials/posts/footer-inner.html" "partials/footer.html"))

   (list "posts-sitemap"
         :base-directory (expand-file-name "posts" site--source-directory)
         :base-extension "org"
         :publishing-directory (expand-file-name "posts" site--build-directory)
         :recursive t
         :publishing-function #'site--org-html-publish-sitemap-to-html
         :auto-sitemap t
         :sitemap-filename (expand-file-name "index.org" (expand-file-name "posts" site--build-directory))
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
         :publishing-function #'site--org-rss-publish-sitemap-to-rss
         :html-link-home (concat site--url "/posts/")
         :auto-sitemap t
         :sitemap-filename (expand-file-name "rss.org" (expand-file-name "posts" site--build-directory))
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
         :publishing-function #'site--org-rss-publish-sitemap-to-rss
         :html-link-home (concat site--url "/posts/")
         :auto-sitemap t
         :sitemap-filename (expand-file-name "rss-emacs.org" (expand-file-name "posts" site--build-directory))
         :sitemap-title site--title
         :sitemap-style 'list
         :sitemap-sort-files 'anti-chronologically
         :sitemap-function #'site--format-rss-feed
         :sitemap-format-entry #'site--format-rss-feed-entry
         :rss-image-url nil ;; TODO
         :rss-extension "xml")

   (list "static-org-homepage"
         :base-directory (expand-file-name "static" site--source-directory)
         :base-extension "org"
         :publishing-directory site--build-directory
         :exclude ".*"
         :include '("index.org")
         :publishing-function #'org-html-publish-to-html
         :html-preamble (site--read-files "partials/header.html" "partials/header-homepage-inner.html"))

   (list "static-org-rest"
         :base-directory (expand-file-name "static" site--source-directory)
         :base-extension "org"
         :publishing-directory site--build-directory
         :recursive t
         :exclude "^index.org"
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
         :components '("posts-org" "posts-sitemap" "posts-assets" "posts-rss" "posts-rss-emacs" "static-org-homepage" "static-org-rest" "static-assets" "cname"))))

(defvar site--watch-timer nil)
(defvar site--watch-descriptors nil)

(defun site--watch-callback (event)
  "Rebuild on file change EVENT, debounced."
  (when (memq (nth 1 event) '(changed created deleted renamed))
    (unless site--watch-timer
      (setq site--watch-timer
            (run-with-timer 1.0 nil
                            (lambda ()
                              (setq site--watch-timer nil)
                              (condition-case err
                                  (site--rebuild)
                                (error (message "Rebuild failed: %s" err)))))))))

(defun site--rebuild ()
  "Rebuild the site without killing Emacs."
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

        (org-publish-use-timestamps-flag nil)
        (org-publish-project-alist site--project-alist)

        (user-full-name site--author)
        (user-mail-address site--email))
    (site--restore-post-mtimes)
    (org-html-stable-ids-add)
    (org-publish "site" t)
    (site--normalize-rss-channel-dates)
    (message "Site rebuilt at %s" (current-time-string))))

(defun build ()
  "Build the site and exit."
  (site--rebuild)
  (kill-emacs))

(defun serve ()
  "Serve the site with auto-rebuild on source change."
  (let ((httpd-host "0.0.0.0")
        (httpd-port 8088))
    (setq site--watch-descriptors
          (mapcar (lambda (dir)
                    (file-notify-add-watch dir '(change) #'site--watch-callback))
                  (directory-files-recursively site--source-directory "" t)))
    (message "Watching %s for changes..." site--source-directory)
    (httpd-serve-directory site--build-directory)))

(provide 'build)
;;; build.el ends here
