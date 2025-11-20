;;; shortcut.el --- Emacs integration for Shortcut project management -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Jonathan Jin

;; Author: Jonathan Jin <me@jonathanj.in>
;; URL: https://github.com/jinnovation/shortcut.el
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (transient "0.3.0") (magit-section "3.3.0"))
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
(require 'magit-section)

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

(defcustom shortcut-story-search-min-chars 2
  "Minimum number of characters before triggering dynamic search.
API searches will only be triggered when the user has typed at least
this many characters.  This helps avoid excessive API calls."
  :type 'integer
  :group 'shortcut)

;;; Cache Variables

(defvar shortcut--member-cache (make-hash-table :test 'equal)
  "Cache for member information.
Keys are member IDs (as strings), values are member objects.")

(defvar shortcut--workflow-cache (make-hash-table :test 'equal)
  "Cache for workflow information.
Keys are workflow IDs (as strings), values are workflow objects.")

;; FIXME: Will need some way to expire/TTL these, e.g. to account for title changes
(defvar shortcut--story-cache (make-hash-table :test 'equal)
  "Cache for story information.
Keys are story IDs (as strings), values are alists with at least 'name field.")

(defvar shortcut--epic-cache (make-hash-table :test 'equal)
  "Cache for epic information.
Keys are epic IDs (as strings), values are epic objects.")

(defun shortcut--clear-story-cache ()
  (interactive)
  (setq shortcut--story-cache (make-hash-table :test 'equal)))

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

(defface shortcut-story-state-blocked
    '((t :inherit error))
  "Face for blocked stories."
  :group 'shortcut)

(defface shortcut-story-label
    '((t :inherit bold))
  "Base face for story labels."
  :group 'shortcut)

(defface shortcut-story-header
    '((t :inherit default))
  "Face for story header fields."
  :group 'shortcut)

(defface shortcut-id
    '((t :foreground "#dbac66"))
  "Face for story or epic IDs."
  :group 'shortcut)

(defface shortcut-placeholder
    '((t :inherit font-lock-comment-face))
  "Face for placeholder values in story buffers."
  :group 'shortcut)

(defface shortcut-comment-author
    '((t :inherit bold))
  "Face for comment author names."
  :group 'shortcut)

(defface shortcut-comment-date
    '((t :inherit font-lock-comment-face))
  "Face for comment timestamps."
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

(defun shortcut--story-cache-add (story)
  "Add STORY to the cache, storing its ID, name, epic, and author.
STORY should be an alist with at least 'id and 'name fields."
  (when-let ((id (alist-get 'id story))
             (name (alist-get 'name story)))
    (let ((epic-id (alist-get 'epic_id story))
          (owner-ids (alist-get 'owner_ids story)))
      (puthash (format "%s" id)
               `((id . ,id)
                 (name . ,name)
                 (epic_id . ,epic-id)
                 (owner_ids . ,owner-ids))
               shortcut--story-cache))))

(defun shortcut--story-cache-candidates ()
  "Get a list of story candidates from cache for completing-read.
Returns an alist where keys are 'ID TITLE' strings for matching,
and values are the story IDs (as strings without 'sc-' prefix)."
  (let ((candidates '()))
    (maphash (lambda (key value)
               (let* ((id key)
                      (name (alist-get 'name value))
                      ;; Create a key with ID and title for filtering
                      (display-key (if name
                                       (format "%s %s"
                                               (propertize id 'face 'shortcut-id)
                                               name)
                                     id)))
                 (push (cons display-key id) candidates)))
             shortcut--story-cache)
    (sort candidates
          (lambda (a b)
            (> (string-to-number (cdr a))
               (string-to-number (cdr b)))))))

(defun shortcut--stories-search (input)
  "Search for stories using the Shortcut Search API with INPUT string.
Returns an alist where keys are 'ID TITLE' display strings (with propertized ID)
and values are story IDs (as strings without 'sc-' prefix).
Caches retrieved stories in `shortcut--story-cache'."
  (condition-case err
      (let* ((query (if (string-empty-p input)
                        "is:story"
                      (format "is:story %s" input)))
             (body `((query . ,query)
                     (entity_types . ["story"])
                     (page_size . 50)))
             (response (shortcut--api-request "/search" "GET" body))
             (stories (alist-get 'data (alist-get 'stories response)))
             (candidates '()))
        ;; Cache each story and collect candidates in cache format
        (when stories
          (seq-doseq (story stories)
            (shortcut--story-cache-add story)
            (when-let* ((id (alist-get 'id story))
                        (name (alist-get 'name story))
                        (id-str (format "%s" id)))
              (let ((display-key (format "%s %s"
                                         (propertize id-str 'face 'shortcut-id)
                                         name)))
                (push (cons display-key id-str) candidates)))))
        ;; Return in descending order (most recent first)
        (sort candidates
              (lambda (a b)
                (> (string-to-number (cdr a))
                   (string-to-number (cdr b))))))
    (error
     ;; On error, return empty list and optionally log
     (message "Shortcut search API error: %s" (error-message-string err))
     '())))

(defun shortcut--story-should-search-p (input)
  "Return non-nil if we should trigger an API search for INPUT.
Checks minimum character length."
  (>= (length input) shortcut-story-search-min-chars))

(defun shortcut--story-merge-candidates (cache-candidates search-ids)
  "Merge CACHE-CANDIDATES with SEARCH-IDS, removing duplicates.
CACHE-CANDIDATES is an alist of (display-string . id).
SEARCH-IDS is a list of story ID strings from API search.
Returns a merged alist sorted by ID (most recent first)."
  (let* ((cache-ids (mapcar #'cdr cache-candidates))
         (all-ids (delete-dups (append search-ids cache-ids)))
         (merged '()))
    ;; Build merged list with display strings
    (dolist (id all-ids)
      (let* ((cached-entry (gethash id shortcut--story-cache))
             (name (alist-get 'name cached-entry))
             (display-key (if name
                              (format "%s %s"
                                      (propertize id 'face 'shortcut-id)
                                      name)
                            id)))
        (push (cons display-key id) merged)))
    merged))

;; NB(@jinnovation): How can we get the substring to properly be sent in unconditionally when using
;; something like vertico-prescient-mode, which seems to send empty string on some cases?
(defun shortcut--story-completion-table (string predicate action)
  "Completion table function for story selection with dynamic search.
STRING is the current input, PREDICATE is the completion predicate,
and ACTION is the completion action (t, lambda, metadata, etc.)."
  ;; TODO: How to set substring search style for this specifically?
  (pcase action
    ('metadata
     ;; Return completion metadata with affixation function for prefix and annotation function for suffix
     '(metadata (category . shortcut-story)
       ;; NB(@jinnovation): Affixation function only adds `sc-` prefix. Not very useful. Consider removing.'
       ;; (affixation-function . shortcut--story-affixation-function)

       ;; FIXME: affixation takes precedent over annotation-function. How can we include the
       ;; annotation info but not allow completing on it?
       (annotation-function . shortcut--story-annotation-function)
       (group-function . shortcut--story-group-function)))
    ('lambda
        ;; Test if STRING is a valid completion
        (let ((candidates (shortcut--story-cache-candidates)))
          (test-completion string candidates predicate)))
    ('t
     ;; Return all completions matching STRING
     (let* ((cache-candidates (shortcut--story-cache-candidates))
            (candidates
             (if (shortcut--story-should-search-p string)
                 (progn
                   ;; Perform search and merge with cache
                   (let ((search-ids (shortcut--stories-search string)))
                     (shortcut--story-merge-candidates cache-candidates search-ids)))
               ;; Just use cache if search not triggered
               cache-candidates)))
       (all-completions string candidates predicate)))
    (_
     ;; Default: try-completion
     (let ((cache-candidates (shortcut--story-cache-candidates)))
       (try-completion string cache-candidates predicate)))))

(defun shortcut--story-get (story-id)
  "Get the JSON payload for a story with STORY-ID.
Caches the story's ID and name in `shortcut--story-cache'."
  (let ((story (shortcut--api-request (format "/stories/%s" story-id))))
    (shortcut--story-cache-add story)
    story))

(defun shortcut--story-comments-get (story-id)
  "Get all comments for story with STORY-ID.
Returns a vector of comment objects."
  (let ((story (shortcut--story-get story-id)))
    (or (alist-get 'comments story) [])))

(defun shortcut--story-task-update (story-id task-id complete)
  "Update task TASK-ID in story STORY-ID with COMPLETE status.
COMPLETE should be t or nil.  Returns the updated task."
  (shortcut--api-request
   (format "/stories/%s/tasks/%s" story-id task-id)
   "PUT"
   `((complete . ,(if complete t :json-false)))))

(defun shortcut--story-update (story-id fields)
  "Update story STORY-ID with FIELDS.
FIELDS should be an alist of field names to values.
Returns the updated story."
  (shortcut--api-request
   (format "/stories/%s" story-id)
   "PUT"
   fields))

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

(defun shortcut--workflow-get (workflow-id)
  "Get the JSON payload for workflow with WORKFLOW-ID.
Returns the workflow as an alist parsed from JSON.
Results are cached in `shortcut--workflow-cache'."
  (let ((workflow-id-str (format "%s" workflow-id)))
    (or (gethash workflow-id-str shortcut--workflow-cache)
        (let ((workflow (shortcut--api-request (format "/workflows/%s" workflow-id-str))))
          (puthash workflow-id-str workflow shortcut--workflow-cache)
          workflow))))

(defun shortcut--workflow-state-name (workflow-id workflow-state-id)
  "Get the name of the workflow state with WORKFLOW-STATE-ID in WORKFLOW-ID.
Returns the state name as a string, or \"Unknown\" if lookup fails."
  (condition-case err
      (let* ((workflow (shortcut--workflow-get workflow-id))
             (states (alist-get 'states workflow))
             (state (seq-find (lambda (s)
                                (= (alist-get 'id s) workflow-state-id))
                              states)))
        (or (alist-get 'name state) "Unknown"))
    (error "Unknown")))

(defun shortcut--workflow-states-get (workflow-id)
  "Get all workflow states for WORKFLOW-ID.
Returns a vector of state objects, each with 'id and 'name fields."
  (let* ((workflow (shortcut--workflow-get workflow-id))
         (states (alist-get 'states workflow)))
    (or states [])))

(defun shortcut--epic-get (epic-id)
  "Get the JSON payload for epic with EPIC-ID.
Returns the epic as an alist parsed from JSON.
Results are cached in `shortcut--epic-cache'."
  (let ((epic-id-str (format "%s" epic-id)))
    (or (gethash epic-id-str shortcut--epic-cache)
        (let ((epic (shortcut--api-request (format "/epics/%s" epic-id-str))))
          (puthash epic-id-str epic shortcut--epic-cache)
          epic))))

(defun shortcut--epic-name (epic-id)
  "Get the name of the epic with EPIC-ID.
Returns the epic name as a string, or nil if lookup fails or epic-id is nil."
  (when epic-id
    (condition-case err
        (let ((epic (shortcut--epic-get epic-id)))
          (alist-get 'name epic))
      (error nil))))

;;; Story Mode

(defun shortcut-story-ret ()
  "Handle RET in story buffer.
If on a widget, activate it.  Otherwise, browse the story URL."
  (interactive)
  (if (get-char-property (point) 'button)
      (widget-button-press (point))
    (shortcut-story-browse-url)))

(defvar shortcut-story-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") 'quit-window)
    (define-key map (kbd "g") 'shortcut-story-refresh)
    (define-key map (kbd "b") 'shortcut-story-browse-url)
    (define-key map (kbd "RET") 'shortcut-story-ret)
    (define-key map (kbd "M-w") 'shortcut-story-copy-id)
    (define-key map (kbd "s") 'shortcut-story-set-state)
    map)
  "Keymap for `shortcut-story-mode'.")

(defvar-local shortcut-story--current-id nil
  "The ID of the story currently displayed in this buffer.")

(defvar-local shortcut-story--current-workflow-id nil
  "The workflow ID of the story currently displayed in this buffer.")

(defvar-local shortcut-story--current-workflow-state-id nil
  "The current workflow state ID of the story displayed in this buffer.")

(defun shortcut-story-set-state ()
  "Change the workflow state of the current story.
Prompts for a new state using completing-read from available workflow states."
  (interactive)
  (unless shortcut-story--current-id
    (user-error "No story loaded in current buffer"))
  (unless shortcut-story--current-workflow-id
    (user-error "No workflow information available"))

  (let* ((states (shortcut--workflow-states-get shortcut-story--current-workflow-id))
         (current-state-name (when shortcut-story--current-workflow-state-id
                               (shortcut--workflow-state-name
                                shortcut-story--current-workflow-id
                                shortcut-story--current-workflow-state-id)))
         ;; Create alist with propertized state names for display
         (state-alist (mapcar (lambda (state)
                                (let ((name (alist-get 'name state)))
                                  (cons (propertize name 'face (shortcut--story-format-state name))
                                        (alist-get 'id state))))
                              states))
         (prompt (if current-state-name
                     (format "Set state (current: %s): " current-state-name)
                   "Set state: "))
         (selected-name (completing-read prompt state-alist nil t))
         ;; Strip text properties from selected name to match original string
         (selected-id (alist-get selected-name state-alist nil nil
                                 (lambda (a b) (string= (substring-no-properties a)
                                                        (substring-no-properties b))))))

    (when selected-id
      (condition-case err
          (progn
            (message "Updating story state...")
            (shortcut--story-update shortcut-story--current-id
                                    `((workflow_state_id . ,selected-id)))
            (shortcut-story-refresh)
            (message "Story state updated to: %s" selected-name))
        (error
         (message "Failed to update story state: %s" (error-message-string err))
         (shortcut-story-refresh))))))

(define-derived-mode shortcut-story-mode magit-section-mode "Shortcut-Story"
                     "Major mode for viewing Shortcut stories.

\\{shortcut-story-mode-map}"
                     :group 'shortcut
                     (setq truncate-lines t)
                     (goto-address-mode +1)
                     ;; Enable widget minor mode for checkbox interaction
                     (setq-local widget-push-button-prefix "")
                     (setq-local widget-push-button-suffix "")
                     (setq-local widget-link-prefix "")
                     (setq-local widget-link-suffix ""))

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

(defun shortcut-story-copy-id ()
  "Copy the current story ID to the kill ring."
  (interactive)
  (if shortcut-story--current-id
      (let ((id-string (format "sc-%d" shortcut-story--current-id)))
        (kill-new id-string)
        (message "Copied %s to kill ring" id-string))
    (message "No story ID available")))

;;; Story Buffer Formatting

(defun shortcut--story-format-state (workflow-state-name)
  "Return a face for the story state based on WORKFLOW-STATE-NAME."
  (pcase (downcase workflow-state-name)
    ((or "unstarted" "to do" "backlog") 'shortcut-story-state-unstarted)
    ((or "started" "in progress" "in review") 'shortcut-story-state-started)
    ((or "done" "completed" "deployed") 'shortcut-story-state-done)
    ((or "blocked" "on hold") 'shortcut-story-state-blocked)
    (_ 'shortcut-story-state-started)))

(defun shortcut--story-insert-header (label value &optional face)
  "Insert a header line with LABEL and VALUE.
Optional FACE is applied to the value."
  (when value
    (insert (propertize (format "%-15s" (concat label ":"))
                        'font-lock-face 'shortcut-story-header))
    (insert (if face
                (propertize (format "%s" value) 'font-lock-face face)
              (format "%s" value)))
    (insert "\n")))

(defun shortcut--story-insert-labels (labels)
  "Insert formatted LABELS with colored backgrounds."
  (when (and labels (> (length labels) 0))
    (insert (propertize "Labels:         " 'font-lock-face 'shortcut-story-header))
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
              (overlay-put o 'font-lock-face `(:background ,background
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
    (magit-insert-section (description)
      (magit-insert-heading "Description")
      (insert (shortcut--fontify-markdown description))
      (insert "\n\n"))))

(defun shortcut--story-insert-tasks (tasks)
  "Insert TASKS as a checklist using Emacs checkbox widgets."
  (when (and tasks (> (length tasks) 0))
    (magit-insert-section (tasks)
      (magit-insert-heading "Tasks")
      (seq-doseq (task tasks)
        (let* ((complete (not (eq :json-false (alist-get 'complete task))))
               (description (alist-get 'description task))
               (task-id (alist-get 'id task)))
          (insert "  ")
          (let ((widget-start (point)))
            (widget-create 'checkbox
                           :value complete
                           :notify (lambda (widget &rest _)
                                     (let ((new-value (widget-value widget)))
                                       (condition-case err
                                           (progn
                                             (message "Updating task...")
                                             (shortcut--story-task-update
                                              shortcut-story--current-id
                                              task-id
                                              new-value)
                                             (shortcut-story-refresh)
                                             (message "Task updated successfully"))
                                         (error
                                          (message "Failed to update task: %s" (error-message-string err))
                                          (shortcut-story-refresh)))))))
          (insert " ")
          (let ((formatted-desc (shortcut--fontify-markdown description)))
            (if complete
                (insert (propertize formatted-desc 'font-lock-face 'shortcut-placeholder))
              (insert formatted-desc)))
          (insert "\n")))
      (insert "\n")
      (widget-setup))))

(defun shortcut--fontify-markdown (text)
  "Fontify TEXT as markdown and return it as a string with text properties.
Similar to Forge's markdown fontification."
  (if (and text (not (string-empty-p text)))
      (with-temp-buffer
        (insert text)
        (when (fboundp 'gfm-mode)
          (delay-mode-hooks (gfm-mode)))
        (font-lock-ensure)
        ;; Convert face properties to font-lock-face for persistence
        (let ((result (buffer-string))
              (beg 0)
              (end (length (buffer-string))))
          (while (< beg end)
            (let ((pos (next-single-property-change beg 'face result end))
                  (val (get-text-property beg 'face result)))
              (when val
                (put-text-property beg pos 'font-lock-face val result)
                (remove-text-properties beg pos '(face) result))
              (setq beg pos)))
          result))
    ""))

(defun shortcut--format-timestamp (timestamp)
  "Format TIMESTAMP as a relative time string (e.g., '2 hours ago').
TIMESTAMP should be an ISO 8601 string."
  (if (not timestamp)
      ""
    (let* ((time (date-to-time timestamp))
           (diff (time-subtract (current-time) time))
           (seconds (time-to-seconds diff)))
      (cond
        ((< seconds 60) "just now")
        ((< seconds 3600) (format "%d minutes ago" (/ seconds 60)))
        ((< seconds 86400) (format "%d hours ago" (/ seconds 3600)))
        ((< seconds 604800) (format "%d days ago" (/ seconds 86400)))
        ((< seconds 2592000) (format "%d weeks ago" (/ seconds 604800)))
        ((< seconds 31536000) (format "%d months ago" (/ seconds 2592000)))
        (t (format "%d years ago" (/ seconds 31536000)))))))

(defun shortcut--comment-insert-heading (comment &optional indent)
  "Insert the heading for COMMENT with author and timestamp.
Optional INDENT specifies the indentation level in spaces."
  (let* ((author-id (alist-get 'author_id comment))
         (author-name (shortcut--member-name author-id))
         (created-at (alist-get 'created_at comment))
         (timestamp (shortcut--format-timestamp created-at))
         (indent-str (if indent (make-string indent ?\s) "")))
    (insert indent-str)
    (insert (propertize author-name 'font-lock-face 'shortcut-comment-author))
    (insert " ")
    (insert (propertize timestamp 'font-lock-face 'shortcut-comment-date))
    (insert "\n")))

(defun shortcut--comment-insert-content (comment &optional indent)
  "Insert the content/body of COMMENT with markdown formatting.
Optional INDENT specifies the indentation level in spaces."
  (let ((text (alist-get 'text comment)))
    (when (and text (not (string-empty-p text)))
      (let ((content (shortcut--fontify-markdown text)))
        (if indent
            ;; Apply indentation to each line of the content
            (let ((indent-str (make-string indent ?\s)))
              (insert (string-join
                       (mapcar (lambda (line) (concat indent-str line))
                               (split-string content "\n"))
                       "\n")))
          (insert content)))
      (insert "\n\n"))))

(defun shortcut--story-insert-comment (comment all-comments &optional indent)
  "Insert a single COMMENT into the buffer with optional INDENT level.
ALL-COMMENTS is the full list of comments to find replies.
INDENT specifies the number of spaces to indent nested replies.
Recursively inserts any nested reply comments based on parent_id."
  (let ((comment-id (alist-get 'id comment)))
    (magit-insert-section (comment comment)
      (shortcut--comment-insert-heading comment indent)
      (shortcut--comment-insert-content comment indent)
      ;; Find and recursively insert replies (comments with this comment's id as parent_id)
      (let ((replies (seq-filter (lambda (c)
                                   (equal (alist-get 'parent_id c) comment-id))
                                 all-comments)))
        (when replies
          (seq-doseq (reply replies)
            (shortcut--story-insert-comment reply all-comments (+ (or indent 0) 4))))))))

(defun shortcut--story-insert-comments (comments)
  "Insert all COMMENTS for the story.
Builds a threaded view based on parent_id relationships."
  (when (and comments (> (length comments) 0))
    (magit-insert-section (comments nil t)
      (magit-insert-heading "Comments")
      (magit-insert-section-body
        ;; Insert only top-level comments (those without a parent_id or with null parent_id)
        (let ((top-level-comments (seq-filter (lambda (c)
                                                (let ((parent-id (alist-get 'parent_id c)))
                                                  (or (null parent-id)
                                                      (eq parent-id :null))))
                                              comments)))
          (seq-doseq (comment top-level-comments)
            (shortcut--story-insert-comment comment comments)))))))

(defun shortcut--story-format-buffer (story)
  "Format STORY data into a readable buffer similar to Forge PR buffers."

  (magit-insert-section (story story)
    (let* ((id (alist-get 'id story))
           (name (alist-get 'name story))
           (story-type (alist-get 'story_type story))
           (workflow-id (alist-get 'workflow_id story))
           (workflow-state-id (alist-get 'workflow_state_id story))
           (workflow-state-name (shortcut--workflow-state-name workflow-id workflow-state-id))
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
           (comments (alist-get 'comments story))
           (app-url (alist-get 'app_url story)))

      ;; Set buffer-local variables for workflow state changes
      (setq shortcut-story--current-workflow-id workflow-id)
      (setq shortcut-story--current-workflow-state-id workflow-state-id)

      ;; Set header line with story ID and title
      (setq header-line-format
            (concat (propertize (format "sc-%d" id) 'face 'shortcut-id)
                    " "
                    (propertize name 'face 'shortcut-story-title)))

      (magit-insert-section (overview)
        (magit-insert-heading "Overview")

        (shortcut--story-insert-header "Type" (upcase story-type))
        (shortcut--story-insert-header "State" workflow-state-name
                                       (shortcut--story-format-state workflow-state-name))
        (when estimate
          (shortcut--story-insert-header "Estimate" (format "%d points" estimate)))
        (when epic-id
          (shortcut--story-insert-header "Epic" (format "sc-%d" epic-id) 'shortcut-id))
        (when iteration-id
          (shortcut--story-insert-header "Iteration" (format "sc-%d" iteration-id) 'shortcut-id))

        (shortcut--story-insert-labels labels)

        (when owners
          (shortcut--story-insert-header "Owners"
                                         (mapconcat #'shortcut--member-name
                                                    owners ", ")))

        (if deadline
            (shortcut--story-insert-header "Deadline" (shortcut--story-format-timestamp deadline))
          (shortcut--story-insert-header "Deadline"
                                         "(none)"
                                         'shortcut-placeholder))

        (shortcut--story-insert-header "Created" (shortcut--story-format-timestamp created-at))
        (shortcut--story-insert-header "Updated" (shortcut--story-format-timestamp updated-at))
        (when completed-at
          (shortcut--story-insert-header "Completed" (shortcut--story-format-timestamp completed-at)))

        (when app-url
          (shortcut--story-insert-header "URL" app-url))

        (insert "\n"))

      (shortcut--story-insert-tasks tasks)
      (shortcut--story-insert-description description)
      (shortcut--story-insert-comments comments))))

(defun shortcut--story-affixation-function (candidates)
  "Affixation function for story completion.
CANDIDATES is a list of display keys from the alist (strings in format 'ID TITLE').
Returns a list of (candidate prefix suffix) for each candidate, adding 'sc-' prefix."
  (mapcar (lambda (candidate)
            (list candidate
                  (propertize "sc-" 'face 'shortcut-id)
                  ""))
          candidates))

(defun shortcut--story-annotation-function (candidate)
  "Annotation function for story completion.
CANDIDATE is a display key string in format 'ID TITLE'.
Returns an annotation string with epic name and author."
  (let* (;; Extract the story ID from the candidate string using regex
         ;; Candidate format is "ID TITLE" where ID is a sequence of digits
         (id (when (string-match "^\\([0-9]+\\)" candidate)
               (match-string 1 candidate)))
         ;; Get story from cache
         (story (when id (gethash id shortcut--story-cache)))
         (epic-id (alist-get 'epic_id story))
         (owner-ids (alist-get 'owner_ids story))
         ;; Build annotation parts
         (epic-str (when epic-id
                     (let ((epic-name (shortcut--epic-name epic-id)))
                       (when epic-name
                         (format " [%s]" epic-name)))))
         (owner-str (when (and owner-ids (> (length owner-ids) 0))
                      (let ((first-owner (aref owner-ids 0)))
                        (format " @%s" (shortcut--member-name first-owner)))))
         ;; Combine annotations
         (annotation (concat
                      (propertize " " 'display '(space :align-to center))
                      (when epic-str
                        (propertize epic-str 'face 'font-lock-comment-face))
                      (when owner-str
                        (propertize owner-str 'face 'font-lock-keyword-face)))))
    annotation))

(defun shortcut--story-group-function (candidate transform)
  "Group function for story completion.
CANDIDATE is a display key string in format 'ID TITLE'.
TRANSFORM is either nil (return group title) or non-nil (return transformed candidate).
Groups stories by their epic name, with stories without epics in 'No Epic' group."
  (if transform
      ;; When TRANSFORM is non-nil, return the candidate as-is
      candidate
    ;; When TRANSFORM is nil, return the group title for this candidate
    (let* (;; Extract the story ID from the candidate string using regex
           (id (when (string-match "^\\([0-9]+\\)" candidate)
                 (match-string 1 candidate)))
           ;; Get story from cache
           (story (when id (gethash id shortcut--story-cache)))
           (epic-id (alist-get 'epic_id story))
           ;; Get epic name, or use "No Epic" as default
           (group-name (if epic-id
                           (or (shortcut--epic-name epic-id)
                               (format "Epic sc-%s" epic-id))
                         "No Epic")))
      group-name)))

(defun shortcut-story-get (story-id)
  "Interactively get and display a Shortcut story by STORY-ID.
When called interactively, prompts for the story ID using completing-read.
Supports dynamic searching - type to search for stories via the API,
or select from cached stories."
  (interactive
   (let* (;; Use completion table function for dynamic search
          (id-str (completing-read "Story ID: "
                                   #'shortcut--story-completion-table
                                   nil nil))
          (id (if (string-match "^sc-\\([0-9]+\\)$" id-str)
                  (string-to-number (match-string 1 id-str))
                (string-to-number id-str))))
     (list id)))
  (let ((story (shortcut--story-get story-id)))
    (with-current-buffer (get-buffer-create (format "*Shortcut Story: sc-%s*" story-id))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (shortcut-story-mode)
        (setq shortcut-story--current-id story-id)
        (shortcut--story-format-buffer story)
        (goto-char (point-min))
        (display-buffer (current-buffer))))))

;;; Epic Mode

(defun shortcut-epic-ret ()
  "Handle RET in epic buffer.
If on a widget, activate it.  Otherwise, browse the epic URL."
  (interactive)
  (if (get-char-property (point) 'button)
      (widget-button-press (point))
    (shortcut-epic-browse-url)))

(defvar shortcut-epic-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") 'quit-window)
    (define-key map (kbd "g") 'shortcut-epic-refresh)
    (define-key map (kbd "b") 'shortcut-epic-browse-url)
    (define-key map (kbd "RET") 'shortcut-epic-ret)
    (define-key map (kbd "M-w") 'shortcut-epic-copy-id)
    map)
  "Keymap for `shortcut-epic-mode'.")

(defvar-local shortcut-epic--current-id nil
  "The ID of the epic currently displayed in this buffer.")

(defvar-local shortcut-epic--current-state-id nil
  "The current state ID of the epic displayed in this buffer.")

(define-derived-mode shortcut-epic-mode magit-section-mode "Shortcut-Epic"
                     "Major mode for viewing Shortcut epics.

\\{shortcut-epic-mode-map}"
                     :group 'shortcut
                     (setq truncate-lines t)
                     (goto-address-mode +1))

(defun shortcut-epic-refresh ()
  "Refresh the current epic buffer."
  (interactive)
  (when shortcut-epic--current-id
    (let ((inhibit-read-only t)
          (epic (shortcut--epic-get shortcut-epic--current-id))
          (pos (point)))
      (erase-buffer)
      (shortcut--epic-format-buffer epic)
      (goto-char (min pos (point-max))))))

(defun shortcut-epic-browse-url ()
  "Open the current epic in a web browser."
  (interactive)
  (when shortcut-epic--current-id
    (let* ((epic (shortcut--epic-get shortcut-epic--current-id))
           (url (alist-get 'app_url epic)))
      (if url
          (browse-url url)
        (message "No URL available for this epic")))))

(defun shortcut-epic-copy-id ()
  "Copy the current epic ID to the kill ring."
  (interactive)
  (if shortcut-epic--current-id
      (let ((id-string (format "sc-%d" shortcut-epic--current-id)))
        (kill-new id-string)
        (message "Copied %s to kill ring" id-string))
    (message "No epic ID available")))

;;; Epic Buffer Formatting

(defun shortcut--epic-state-name (epic)
  "Get the state name from EPIC.
Returns the state as a string, or \"Unknown\" if not found."
  (or (alist-get 'state epic) "Unknown"))

(defun shortcut--epic-insert-stats (stats)
  "Insert STATS section showing story and point counts."
  (when stats
    (magit-insert-section (stats)
      (magit-insert-heading "Stats")

      (let ((num-stories-total (alist-get 'num_stories_total stats))
            (num-stories-unstarted (alist-get 'num_stories_unstarted stats))
            (num-stories-started (alist-get 'num_stories_started stats))
            (num-stories-done (alist-get 'num_stories_done stats))
            (num-points-total (alist-get 'num_points_total stats))
            (num-points-unstarted (alist-get 'num_points_unstarted stats))
            (num-points-started (alist-get 'num_points_started stats))
            (num-points-done (alist-get 'num_points_done stats)))

        (when num-stories-total
          (shortcut--story-insert-header "Stories"
                                         (format "%d total" num-stories-total))
          (when num-stories-unstarted
            (insert (propertize "                " 'font-lock-face 'shortcut-story-header))
            (insert (propertize (format "%d unstarted" num-stories-unstarted)
                                'font-lock-face 'shortcut-story-state-unstarted))
            (insert "\n"))
          (when num-stories-started
            (insert (propertize "                " 'font-lock-face 'shortcut-story-header))
            (insert (propertize (format "%d started" num-stories-started)
                                'font-lock-face 'shortcut-story-state-started))
            (insert "\n"))
          (when num-stories-done
            (insert (propertize "                " 'font-lock-face 'shortcut-story-header))
            (insert (propertize (format "%d done" num-stories-done)
                                'font-lock-face 'shortcut-story-state-done))
            (insert "\n")))

        (when num-points-total
          (shortcut--story-insert-header "Points"
                                         (format "%d total" num-points-total))
          (when num-points-unstarted
            (insert (propertize "                " 'font-lock-face 'shortcut-story-header))
            (insert (propertize (format "%d unstarted" num-points-unstarted)
                                'font-lock-face 'shortcut-story-state-unstarted))
            (insert "\n"))
          (when num-points-started
            (insert (propertize "                " 'font-lock-face 'shortcut-story-header))
            (insert (propertize (format "%d started" num-points-started)
                                'font-lock-face 'shortcut-story-state-started))
            (insert "\n"))
          (when num-points-done
            (insert (propertize "                " 'font-lock-face 'shortcut-story-header))
            (insert (propertize (format "%d done" num-points-done)
                                'font-lock-face 'shortcut-story-state-done))
            (insert "\n"))))

      (insert "\n"))))

(defun shortcut--epic-format-buffer (epic)
  "Format EPIC data into a readable buffer similar to story buffers."

  (magit-insert-section (epic epic)
    (let* ((id (alist-get 'id epic))
           (name (alist-get 'name epic))
           (state (shortcut--epic-state-name epic))
           (labels (alist-get 'labels epic))
           (owner-ids (alist-get 'owner_ids epic))
           (milestone-id (alist-get 'milestone_id epic))
           (objective-ids (alist-get 'objective_ids epic))
           (project-ids (alist-get 'project_ids epic))
           (deadline (alist-get 'deadline epic))
           (planned-start-date (alist-get 'planned_start_date epic))
           (created-at (alist-get 'created_at epic))
           (updated-at (alist-get 'updated_at epic))
           (completed-at (alist-get 'completed_at epic))
           (description (alist-get 'description epic))
           (stats (alist-get 'stats epic))
           (comments (alist-get 'comments epic))
           (app-url (alist-get 'app_url epic)))

      ;; Set buffer-local variables
      (setq shortcut-epic--current-state-id (alist-get 'epic_state_id epic))

      ;; Set header line with epic ID and title
      (setq header-line-format
            (concat (propertize (format "sc-%d" id) 'face 'shortcut-id)
                    " "
                    (propertize name 'face 'shortcut-story-title)))

      (magit-insert-section (overview)
        (magit-insert-heading "Overview")

        (shortcut--story-insert-header "State" state
                                       (shortcut--story-format-state state))

        (when owner-ids
          (shortcut--story-insert-header "Owners"
                                         (mapconcat #'shortcut--member-name
                                                    owner-ids ", ")))

        (when milestone-id
          (shortcut--story-insert-header "Milestone" (format "sc-%d" milestone-id) 'shortcut-id))

        (when (and objective-ids (> (length objective-ids) 0))
          (shortcut--story-insert-header "Objectives"
                                         (mapconcat (lambda (id) (format "sc-%d" id))
                                                    objective-ids ", ")
                                         'shortcut-id))

        (shortcut--story-insert-labels labels)

        (if deadline
            (shortcut--story-insert-header "Deadline" (shortcut--story-format-timestamp deadline))
          (shortcut--story-insert-header "Deadline"
                                         "(none)"
                                         'shortcut-placeholder))

        (when planned-start-date
          (shortcut--story-insert-header "Planned Start" (shortcut--story-format-timestamp planned-start-date)))

        (when (and project-ids (> (length project-ids) 0))
          (shortcut--story-insert-header "Projects"
                                         (mapconcat (lambda (id) (format "sc-%d" id))
                                                    project-ids ", ")
                                         'shortcut-id))

        (shortcut--story-insert-header "Created" (shortcut--story-format-timestamp created-at))
        (shortcut--story-insert-header "Updated" (shortcut--story-format-timestamp updated-at))
        (when completed-at
          (shortcut--story-insert-header "Completed" (shortcut--story-format-timestamp completed-at)))

        (when app-url
          (shortcut--story-insert-header "URL" app-url))

        (insert "\n"))

      (shortcut--epic-insert-stats stats)
      (shortcut--story-insert-description description)
      (shortcut--story-insert-comments comments))))

(defun shortcut-epic-get (epic-id)
  "Interactively get and display a Shortcut epic by EPIC-ID.
When called interactively, prompts for the epic ID."
  (interactive
   (let* ((id-str (read-string "Epic ID: "))
          (id (if (string-match "^sc-\\([0-9]+\\)$" id-str)
                  (string-to-number (match-string 1 id-str))
                (string-to-number id-str))))
     (list id)))
  (let ((epic (shortcut--epic-get epic-id)))
    (with-current-buffer (get-buffer-create (format "*Shortcut Epic: sc-%s*" epic-id))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (shortcut-epic-mode)
        (setq shortcut-epic--current-id epic-id)
        (shortcut--epic-format-buffer epic)
        (goto-char (point-min))
        (display-buffer (current-buffer))))))

;;; Member and Workspace Functions

(defvar shortcut--current-member-cache nil
  "Cached current member information including workspace details.")

(defun shortcut--member-current ()
  "Get the current member information.
Returns the member as an alist parsed from JSON.
Results are cached in `shortcut--current-member-cache'."
  (or shortcut--current-member-cache
      (let ((member (shortcut--api-request "/member")))
        (setq shortcut--current-member-cache member)
        member)))

(defun shortcut--workspace-name ()
  "Get the name of the current workspace.
Returns the workspace name as a string, or \"Unknown\" if lookup fails."
  (condition-case err
      (let* ((member (shortcut--member-current))
             (workspace (alist-get 'workspace2 member)))
        (or (alist-get 'name workspace) "Unknown"))
    (error "Unknown")))

(defun shortcut--current-user-name ()
  "Get the name of the current authenticated user.
Returns the user name as a string, or \"Unknown\" if lookup fails."
  (condition-case err
      (or (alist-get 'name (shortcut--member-current)) "Unknown")
    (error "Unknown")))

;;; Transient Interface

(transient-define-prefix shortcut-dispatch ()
  "Work with Shortcut."
  [:description (lambda () (format "Shortcut: %s (%s)"
                                   (shortcut--workspace-name)
                                   (shortcut--current-user-name)))
                ["Stories"
                 ("s" "Get story" shortcut-story-get)]
                ["Epics"
                 ("e" "Get epic" shortcut-epic-get)]])

(provide 'shortcut)

;;; shortcut.el ends here
