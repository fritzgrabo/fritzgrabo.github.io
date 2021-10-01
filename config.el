;;; config.el --- Site Configuration -*- lexical-binding: t; -*-

;;; Commentary:

;;; Code:

(defvar site--url "https://fritzgrabo.com")
(defvar site--title "Fritz Grabo")
(defvar site--author "Fritz Grabo")
(defvar site--email "hello@fritzgrabo.com")

(defvar site--root-directory (file-name-directory load-file-name))
(defvar site--source-directory (expand-file-name "source" site--root-directory))
(defvar site--build-directory (expand-file-name "docs" site--root-directory))

(defvar site--date-format-string "%Y-%m-%d")

(provide 'config)
;;; config.el ends here
