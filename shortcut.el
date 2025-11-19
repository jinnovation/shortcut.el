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

;;; Cache Variables

(defvar shortcut--member-cache (make-hash-table :test 'equal)
  "Cache for member information.
Keys are member IDs (as strings), values are member objects.")

;;; Faces

(defface shortcut-story-title
    '((t :inherit bold))
  "Face for story titles."
  :group 'shortcut)

(defface shortcut-story-state-unstarted
    '((t :inherit font-lock-keyword-face))
  "Face for unstarted stories."
  :group 'shortcut)

(defface shortcut-story-state-started
    '((t :inherit font-lock-function-name-face))
  "Face for started stories."
  :group 'shortcut)

(defface shortcut-story-state-done
    '((t :inherit font-lock-constant-face))
  "Face for completed stories."
  :group 'shortcut)

(defface shortcut-story-label
    '((t :inherit bold))
  "Base face for story labels."
  :group 'shortcut)

(defface shortcut-story-header
    '((t :weight bold :foreground "cyan"))
  "Face for story header fields."
  :group 'shortcut)

(defface shortcut-story-metadata
    '((t :inherit default))
  "Face for story metadata values."
  :group 'shortcut)

(defface shortcut-placeholder
    '((t :inherit font-lock-comment-face))
  "Face for placeholder values in story buffers."
  :group 'shortcut)

;;; API Utilities

(defun shortcut--api-request (endpoint &optional method data)
  "Make an API request to ENDPOINT with optional METHOD and DATA.
METHOD defaults to GET.  Returns the parsed JSON response."
  (let* ((url-request-method (or method "GET"))
         (url-request-extra-headers
          `(("Content-Type" . "application/json")
            ("Shortcut-Token" . ,shortcut-api-token)))
         (url-request-data
          (when data
            (encode-coding-string (json-encode data) 'utf-8)))
         (url (concat shortcut-api-base-url endpoint))
         (buffer (url-retrieve-synchronously url t)))
    (unwind-protect
         (with-current-buffer buffer
           (goto-char (point-min))
           (re-search-forward "^$")
           (delete-region (point-min) (point))
           (let ((json-object-type 'alist)
                 (json-array-type 'vector)
                 (json-key-type 'symbol))
             (json-read)))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

;;; Member Functions

(defun shortcut--story-get (story-id)
  "Get the JSON payload for a story with STORY-ID."
  (shortcut--api-request (format "/stories/%s" story-id)))

(defun shortcut-member-get (member-id)
  "Get the JSON payload for member with MEMBER-ID.
Returns the member as an alist parsed from JSON.
Results are cached in `shortcut--member-cache'."
  (let ((member-id-str (format "%s" member-id)))
    (or (gethash member-id-str shortcut--member-cache)
        (let ((member (shortcut--api-request (format "/members/%s" member-id-str))))
          (puthash member-id-str member shortcut--member-cache)
          member))))

(defun shortcut--member-name (member-id)
  "Get the name of the member with MEMBER-ID.
Returns the member name as a string, or the ID if lookup fails."
  (condition-case err
      (let ((member (shortcut-member-get member-id)))
        (or (alist-get 'name (alist-get 'profile member))
            (alist-get 'name member)
            (format "%s" member-id)))
    (error (format "%s" member-id))))

;;; Story Mode

(defvar shortcut-story-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") 'quit-window)
    (define-key map (kbd "g") 'shortcut-story-refresh)
    (define-key map (kbd "b") 'shortcut-story-browse-url)
    (define-key map (kbd "RET") 'shortcut-story-browse-url)
    map)
  "Keymap for `shortcut-story-mode'.")

(defvar-local shortcut-story--current-id nil
  "The ID of the story currently displayed in this buffer.")

(define-derived-mode shortcut-story-mode special-mode "Shortcut-Story"
                     "Major mode for viewing Shortcut stories.

\\{shortcut-story-mode-map}"
                     :group 'shortcut
                     (setq truncate-lines t)
                     (setq buffer-read-only t)
                     (goto-address-mode +1)
                     (font-lock-mode -1))

(defun shortcut-story-refresh ()
  "Refresh the current story buffer."
  (interactive)
  (when shortcut-story--current-id
    (let ((inhibit-read-only t)
          (story (shortcut--story-get shortcut-story--current-id))
          (pos (point)))
      (erase-buffer)
      (shortcut--story-format-buffer story)
      (goto-char (min pos (point-max))))))

(defun shortcut-story-browse-url ()
  "Open the current story in a web browser."
  (interactive)
  (when shortcut-story--current-id
    (let* ((story (shortcut--story-get shortcut-story--current-id))
           (url (alist-get 'app_url story)))
      (if url
          (browse-url url)
        (message "No URL available for this story")))))

;;; Story Buffer Formatting

(defun shortcut--story-format-state (workflow-state-name)
  "Return a face for the story state based on WORKFLOW-STATE-NAME."
  (pcase (downcase workflow-state-name)
    ((or "unstarted" "to do" "backlog") 'shortcut-story-state-unstarted)
    ((or "started" "in progress" "in review") 'shortcut-story-state-started)
    ((or "done" "completed" "deployed") 'shortcut-story-state-done)
    (_ 'shortcut-story-state-started)))

(defun shortcut--story-insert-header (label value &optional face)
  "Insert a header line with LABEL and VALUE.
Optional FACE is applied to the value."
  (when value
    (insert (propertize (format "%-15s" (concat label ":"))
                        'face 'shortcut-story-header))
    (insert (propertize (format "%s" value)
                        'face (or face 'shortcut-story-metadata)))
    (insert "\n")))

(defun shortcut--story-insert-labels (labels)
  "Insert formatted LABELS with colored backgrounds."
  (when (and labels (> (length labels) 0))
    (insert (propertize "Labels:         " 'face 'shortcut-story-header))
    (let ((first t))
      (seq-doseq (label labels)
        (let* ((name (alist-get 'name label))
               (color (alist-get 'color label))
               (description (alist-get 'description label))
               (background (or color "#cccccc"))
               (foreground (if (and color (string-prefix-p "#" color))
                               (if (> (apply #'+ (color-values background))
                                      (* 3 32768))
                                   "#000000"
                                 "#ffffff")
                             "#000000")))
          (unless first (insert " "))
          (setq first nil)
          (let ((start (point)))
            (insert name)
            (let ((o (make-overlay start (point))))
              (overlay-put o 'priority 2)
              (overlay-put o 'evaporate t)
              (overlay-put o 'face `(:background ,background
                                                 :foreground ,foreground
                                                 :weight bold))
              (when description
                (overlay-put o 'help-echo description)))))))
    (insert "\n")))

(defun shortcut--story-insert-owners (owners)
  "Insert formatted OWNERS list."
  (when (and owners (> (length owners) 0))
    (let ((names (mapcar (lambda (owner)
                           (alist-get 'profile owner))
                         owners)))
      (shortcut--story-insert-header
       "Owners"
       (mapconcat (lambda (profile)
                    (alist-get 'name profile))
                  names ", ")))))

(defun shortcut--story-format-timestamp (timestamp)
  "Format TIMESTAMP string to a readable format."
  (when timestamp
    (format-time-string "%Y-%m-%d %H:%M"
                        (encode-time (parse-time-string timestamp)))))

(defun shortcut--story-insert-description (description)
  "Insert the story DESCRIPTION with proper formatting."
  (when (and description (not (string-empty-p description)))
    (insert "\n")
    (insert (propertize "Description\n" 'face 'shortcut-story-header))
    (insert (make-string 80 ?─))
    (insert "\n\n")
    (insert description)
    (insert "\n")))

(defun shortcut--story-insert-tasks (tasks)
  "Insert TASKS as a checklist using Emacs checkbox widgets."
  (when (and tasks (> (length tasks) 0))
    (insert "\n")
    (insert (propertize "Tasks\n" 'face 'shortcut-story-header))
    (insert (make-string 80 ?─))
    (insert "\n\n")
    (seq-doseq (task tasks)
      (let* ((complete (eq :json-true (alist-get 'complete task)))
             (description (alist-get 'description task)))
        (insert "  ")
        (widget-create 'checkbox
                       :value complete
                       :inactive t)
        (insert " ")
        (if complete
            (insert (propertize description 'face 'shortcut-placeholder))
          (insert description))
        (insert "\n")))
    (insert "\n")
    (widget-setup)))

(defun shortcut--story-format-buffer (story)
  "Format STORY data into a readable buffer similar to Forge PR buffers."
  (let* ((id (alist-get 'id story))
         (name (alist-get 'name story))
         (story-type (alist-get 'story_type story))
         (workflow-state (alist-get 'workflow_state_id story))
         ;; TODO: This needs to get the state name via workflow_state_id and workflow_id
         (workflow-state-name (or (alist-get 'workflow_state_name story) "Unknown"))
         (labels (alist-get 'labels story))
         (owners (alist-get 'owner_ids story))
         (estimate (alist-get 'estimate story))
         (epic-id (alist-get 'epic_id story))
         (iteration-id (alist-get 'iteration_id story))
         (deadline (alist-get 'deadline story))
         (created-at (alist-get 'created_at story))
         (updated-at (alist-get 'updated_at story))
         (completed-at (alist-get 'completed_at story))
         (description (alist-get 'description story))
         (tasks (alist-get 'tasks story))
         (app-url (alist-get 'app_url story)))

    ;; Insert header line (title)
    (insert (propertize (format "sc-%d" id)
                        'face (shortcut--story-format-state workflow-state-name)))
    (insert " ")
    (insert (propertize name 'face 'shortcut-story-title))
    (insert "\n")
    (insert (make-string 80 ?─))
    (insert "\n\n")

    ;; Insert metadata headers
    (shortcut--story-insert-header "Type" (upcase story-type))
    (shortcut--story-insert-header "State" workflow-state-name
                                   (shortcut--story-format-state workflow-state-name))
    (when estimate
      (shortcut--story-insert-header "Estimate" (format "%d points" estimate)))
    (when epic-id
      (shortcut--story-insert-header "Epic" (format "sc-%d" epic-id)))
    (when iteration-id
      (shortcut--story-insert-header "Iteration" (format "sc-%d" iteration-id)))

    ;; Insert labels
    (shortcut--story-insert-labels labels)

    ;; Insert owners (if available from story data)
    (when owners
      (shortcut--story-insert-header "Owners"
                                     (mapconcat #'shortcut--member-name
                                                owners ", ")))

    ;; Insert deadline
    (if deadline
        (shortcut--story-insert-header "Deadline" (shortcut--story-format-timestamp deadline))
      (shortcut--story-insert-header "Deadline"
                                     "(none)"
                                     'shortcut-placeholder))

    ;; Insert timestamps
    (shortcut--story-insert-header "Created" (shortcut--story-format-timestamp created-at))
    (shortcut--story-insert-header "Updated" (shortcut--story-format-timestamp updated-at))
    (when completed-at
      (shortcut--story-insert-header "Completed" (shortcut--story-format-timestamp completed-at)))

    ;; Insert URL
    (when app-url
      (shortcut--story-insert-header "URL" app-url))

    ;; Insert tasks
    (shortcut--story-insert-tasks tasks)

    ;; Insert description
    (shortcut--story-insert-description description)))

(defun shortcut-story-get (story-id)
  "Interactively get and display a Shortcut story by STORY-ID."
  (interactive "nStory ID: ")
  (let ((story (shortcut--story-get story-id)))
    (with-current-buffer (get-buffer-create (format "*Shortcut Story: sc-%s*" story-id))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (shortcut-story-mode)
        (setq shortcut-story--current-id story-id)
        (shortcut--story-format-buffer story)
        (goto-char (point-min))
        (display-buffer (current-buffer))))))

;;; Transient Interface

(transient-define-prefix shortcut-dispatch ()
  "Work with Shortcut."
  ["Shortcut"
   ["Stories"
    ("s" "Get story" shortcut-story-get)]])

(provide 'shortcut)

;;; shortcut.el ends here
