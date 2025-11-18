;;; shortcut.el --- Emacs integration for Shortcut project management -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Jonathan Jin

;; Author: Jonathan Jin <me@jonathanj.in>
;; URL: https://github.com/jinnovation/shortcut.el
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (transient "0.3.0"))
;; Keywords: tools, convenience, project, project-management

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package provides Emacs integration with Shortcut (https://www.shortcut.com),
;; a project management platform.  It allows you to interact with Shortcut stories,
;; epics, iterations, and other entities directly from Emacs.

;;; Code:

(require 'url)
(require 'json)
(require 'transient)

(defgroup shortcut nil
  "Emacs integration for Shortcut project management."
  :group 'tools
  :prefix "shortcut-")

(defcustom shortcut-api-token (getenv "SHORTCUT_API_TOKEN")
  "API token for authenticating with Shortcut.
If nil, the token will be read from the SHORTCUT_API_TOKEN environment variable.
You can generate a token at https://app.shortcut.com/settings/account/api-tokens"
  :type 'string
  :group 'shortcut)

(defcustom shortcut-api-base-url "https://api.app.shortcut.com/api/v3"
  "Base URL for the Shortcut API."
  :type 'string
  :group 'shortcut)

;;; API Utilities

(defun shortcut--make-api-request (endpoint &optional method data)
  "Make an API request to ENDPOINT with optional METHOD and DATA.
METHOD defaults to GET.  Returns the parsed JSON response."
  (let* ((url-request-method (or method "GET"))
         (url-request-extra-headers
          `(("Content-Type" . "application/json")
            ("Shortcut-Token" . ,shortcut-api-token)))
         (url-request-data
          (when data
            (encode-coding-string (json-encode data) 'utf-8)))
         (url (concat shortcut-api-base-url endpoint)))
    (with-current-buffer (url-retrieve-synchronously url t)
      (goto-char (point-min))
      (re-search-forward "^$")
      (delete-region (point-min) (point))
      (let ((json-object-type 'alist)
            (json-array-type 'vector)
            (json-key-type 'symbol))
        (json-read)))))

;;; Story Functions

(defun shortcut-get-story (story-id)
  "Get the JSON payload for story with STORY-ID.
Returns the story as an alist parsed from JSON."
  (shortcut--make-api-request (format "/stories/%s" story-id)))

(defun shortcut-get-story-interactive (story-id)
  "Interactively get and display a Shortcut story by STORY-ID."
  (interactive "nStory ID: ")
  (let ((story (shortcut-get-story story-id)))
    (with-current-buffer (get-buffer-create (format "*Shortcut Story: %s*" story-id))
      (erase-buffer)
      (insert (json-encode story))
      (json-pretty-print-buffer)
      (goto-char (point-min))
      (display-buffer (current-buffer)))))

;;; Transient Interface

(transient-define-prefix shortcut-dispatch ()
  "Dispatch transient for Shortcut commands."
  ["Shortcut"
   ["Stories"
    ("s" "Get story by ID" shortcut-get-story-interactive)]])

(provide 'shortcut)

;;; shortcut.el ends here
