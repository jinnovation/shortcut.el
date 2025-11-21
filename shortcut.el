;;; shortcut.el --- Emacs integration for Shortcut project management -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Jonathan Jin

;; Author: Jonathan Jin <me@jonathanj.in>
;; URL: https://github.com/jinnovation/shortcut.el
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (transient "0.3.0") (magit-section "4.0.0"))
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
(require 'wid-edit)
(require 'vtable)

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
Keys are story IDs (as strings), values are alists with at least `name' field.")

(defvar shortcut--epic-cache (make-hash-table :test 'equal)
  "Cache for epic information.
Keys are epic IDs (as strings), values are epic objects.")

(defvar shortcut--group-cache (make-hash-table :test 'equal)
  "Cache for group/team information.
Keys are group IDs (as strings), values are group objects.")

(defvar shortcut--workflow-state-cache (make-hash-table :test 'equal)
  "Cache for workflow state information including type.
Keys are \"workflow-id:state-id\" strings, values are state objects with
name, id, and type.")

(defun shortcut--clear-story-cache ()
  "Clear the story cache.
This is useful when cached story information becomes stale or outdated."
  (interactive)
  (setq shortcut--story-cache (make-hash-table :test 'equal)))

(defun shortcut--clear-all-caches ()
  "Clear all Shortcut caches.
This clears story, epic, member, workflow, workflow state, and group caches,
as well as the current member cache.  Useful when cached information becomes
stale or outdated."
  (interactive)
  (setq shortcut--story-cache (make-hash-table :test 'equal))
  (setq shortcut--epic-cache (make-hash-table :test 'equal))
  (setq shortcut--member-cache (make-hash-table :test 'equal))
  (setq shortcut--workflow-cache (make-hash-table :test 'equal))
  (setq shortcut--workflow-state-cache (make-hash-table :test 'equal))
  (setq shortcut--group-cache (make-hash-table :test 'equal))
  (setq shortcut--current-member-cache nil)
  (message "Cleared all Shortcut caches"))

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
  "Add STORY to the cache, storing its ID, name, epic, author, and completion.
STORY should be an alist with at least `id' and `name' fields."
  (when-let ((id (alist-get 'id story))
             (name (alist-get 'name story)))
    (let ((epic-id (alist-get 'epic_id story))
          (owner-ids (alist-get 'owner_ids story))
          (workflow-state-id (alist-get 'workflow_state_id story))
          (completed (alist-get 'completed story)))
      (puthash (format "%s" id)
               `((id . ,id)
                 (name . ,name)
                 (epic_id . ,epic-id)
                 (owner_ids . ,owner-ids)
                 (workflow_state_id . ,workflow-state-id)
                 (completed . ,completed))
               shortcut--story-cache))))

(defun shortcut--story-cache-candidates ()
  "Get a list of story candidates from cache for `completing-read'.
Returns an alist where keys are \"ID TITLE\" strings for matching,
and values are the story IDs (as strings without \"sc-\" prefix).
Completed stories are displayed with strikethrough and grey color."
  (let ((candidates '()))
    (maphash (lambda (key value)
               (let* ((id key)
                      (name (alist-get 'name value))
                      (completed (alist-get 'completed value))
                      ;; Apply strikethrough and grey to completed stories
                      (display-name (if (and name (not (eq completed :json-false)))
                                        (propertize name
                                                    'face '(:strike-through t :foreground "grey"))
                                      name))
                      ;; Create a key with ID and title for filtering
                      (display-key (if name
                                       (format "%s %s"
                                               (propertize id 'face 'shortcut-id)
                                               display-name)
                                     id)))
                 (push (cons display-key id) candidates)))
             shortcut--story-cache)
    (sort candidates
          (lambda (a b)
            (> (string-to-number (cdr a))
               (string-to-number (cdr b)))))))

(defun shortcut--stories-search (input)
  "Search for stories using the Shortcut Search API with INPUT string.
Returns an alist where keys are \"ID TITLE\" display strings
\(with propertized ID) and values are story IDs (as strings
without \"sc-\" prefix).
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
              (let* ((completed (alist-get 'completed story))
                     ;; Apply strikethrough and grey to completed stories
                     (display-name (if (not (eq completed :json-false))
                                       (propertize name
                                                   'face '(:strike-through t :foreground "grey"))
                                     name))
                     (display-key (format "%s %s"
                                          (propertize id-str 'face 'shortcut-id)
                                          display-name)))
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
Returns a merged alist sorted by ID (most recent first).
Completed stories are displayed with strikethrough and grey color."
  (let* ((cache-ids (mapcar #'cdr cache-candidates))
         (all-ids (delete-dups (append search-ids cache-ids)))
         (merged '()))
    ;; Build merged list with display strings
    (dolist (id all-ids)
      (let* ((cached-entry (gethash id shortcut--story-cache))
             (name (alist-get 'name cached-entry))
             (completed (alist-get 'completed cached-entry))
             ;; Apply strikethrough and grey to completed stories
             (display-name (if (and name (not (eq completed :json-false)))
                               (propertize name
                                           'face '(:strike-through t :foreground "grey"))
                             name))
             (display-key (if name
                              (format "%s %s"
                                      (propertize id 'face 'shortcut-id)
                                      display-name)
                            id)))
        (push (cons display-key id) merged)))
    merged))

(defun shortcut--story-display-sort-function (candidates)
  "Sort story CANDIDATES within groups by completion status.
Candidates are in \"ID NAME\" format.  Sorts with incomplete stories first,
then completed stories.  Within each completion status, sorts by ID descending."
  (sort candidates
        (lambda (a b)
          ;; Extract ID from "ID NAME" format
          (let* ((id-a (when (string-match "^\\([0-9]+\\)" a)
                         (match-string 1 a)))
                 (id-b (when (string-match "^\\([0-9]+\\)" b)
                         (match-string 1 b)))
                 ;; Get completion status from cache
                 (story-a (when id-a (gethash id-a shortcut--story-cache)))
                 (story-b (when id-b (gethash id-b shortcut--story-cache)))
                 (completed-a (and story-a (not (eq (alist-get 'completed story-a) :json-false))))
                 (completed-b (and story-b (not (eq (alist-get 'completed story-b) :json-false)))))
            (cond
              ;; If completion status differs, incomplete stories come first
              ((and (not completed-a) completed-b) t)
              ((and completed-a (not completed-b)) nil)
              ;; If both have same completion status, sort by ID descending (most recent first)
              (t (and id-a id-b (> (string-to-number id-a) (string-to-number id-b)))))))))

(cl-defun shortcut--make-completion-table (&key category
                                             cache-fn
                                             search-fn
                                             merge-fn
                                             should-search-fn
                                             annotation-fn
                                             group-fn
                                             sort-fn)
  "Create a completion table function for entity type.
CATEGORY is the completion category symbol.
CACHE-FN is a function to get cache candidates.
SEARCH-FN is a function to search API.
MERGE-FN is a function to merge candidates.
SHOULD-SEARCH-FN is a function to check if search is needed.
ANNOTATION-FN is the annotation function.
GROUP-FN is the group function.
SORT-FN is the display sort function."
  (lambda (string predicate action)
    (pcase action
      ('metadata
       `(metadata (category . ,category)
                  (annotation-function . ,annotation-fn)
                  (group-function . ,group-fn)
                  (display-sort-function . ,sort-fn)))
      ('lambda
          (let ((candidates (funcall cache-fn)))
            (test-completion string candidates predicate)))
      ('t
       (let* ((cache-candidates (funcall cache-fn))
              (candidates
               (if (funcall should-search-fn string)
                   (let ((search-results (funcall search-fn string)))
                     (funcall merge-fn cache-candidates search-results))
                 cache-candidates)))
         (all-completions string candidates predicate)))
      (_
       (let ((cache-candidates (funcall cache-fn)))
         (try-completion string cache-candidates predicate))))))

(defun shortcut--story-completion-table (string predicate action)
  "Completion table function for story selection with dynamic search.
STRING is the current input, PREDICATE is the completion predicate,
and ACTION is the completion action (t, lambda, metadata, etc.)."
  (funcall (shortcut--make-completion-table
            :category 'shortcut-story
            :cache-fn #'shortcut--story-cache-candidates
            :search-fn #'shortcut--stories-search
            :merge-fn #'shortcut--story-merge-candidates
            :should-search-fn #'shortcut--story-should-search-p
            :annotation-fn #'shortcut--story-annotation-function
            :group-fn #'shortcut--story-group-function
            :sort-fn #'shortcut--story-display-sort-function)
           string predicate action))

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

(defun shortcut--stories-by-current-user-field (field)
  "Get all story IDs where current user matches FIELD.
FIELD should be \"requester\" or \"owner\".
Returns a list of story IDs (as integers).
Uses the Shortcut Search API with the authenticated user's mention name."
  (let ((mention-name (shortcut--current-user-mention-name)))
    (unless mention-name
      (user-error "Could not determine current user's mention name"))
    (let* ((query (format "%s:%s" field mention-name))
           (results (shortcut--stories-search query))
           (story-ids '()))
      ;; Extract story IDs from the search results
      ;; shortcut--stories-search returns an alist where values are ID strings
      (dolist (result results)
        (let ((id-str (cdr result)))
          (when id-str
            (push (string-to-number id-str) story-ids))))
      ;; Return in ascending order (oldest first)
      (sort story-ids #'<))))

;;; Stories List Mode

(defvar-local shortcut-stories-list--vtable nil
  "The vtable object for the stories list buffer.")

(defvar-local shortcut-stories-list--query-field nil
  "The query field for this stories list buffer.
Can be \"requester\" or \"owner\".")

(defvar-local shortcut-stories-list--display-name nil
  "The display name for this stories list buffer.
E.g., \"Requested by Me\" or \"Owned by Me\".")

(defun shortcut--vtable-get-id (story _index)
  "Get formatted ID for STORY."
  (propertize (format "sc-%d" (alist-get 'id story))
              'face 'shortcut-id))

(defun shortcut--vtable-get-title (story _index)
  "Get formatted title for STORY."
  (let* ((name (alist-get 'name story))
         (completed (alist-get 'completed story)))
    (if (and completed (not (eq completed :json-false)))
        (propertize name 'face '(:strike-through t :foreground "grey"))
      name)))

(defun shortcut--vtable-get-state (story _index)
  "Get formatted state for STORY."
  (let* ((workflow-id (alist-get 'workflow_id story))
         (state-id (alist-get 'workflow_state_id story))
         (state-name (if (and workflow-id state-id)
                         (shortcut--workflow-state-name workflow-id state-id)
                       "Unknown")))
    (propertize state-name 'face (shortcut--story-format-state state-name))))

(defun shortcut--vtable-get-epic (story _index)
  "Get formatted epic for STORY."
  (let ((epic-id (alist-get 'epic_id story)))
    (if epic-id
        (or (shortcut--epic-name epic-id)
            (format "sc-%d" epic-id))
      "")))

(defun shortcut--vtable-get-owner (story _index)
  "Get formatted owner for STORY."
  (let ((owner-ids (alist-get 'owner_ids story)))
    (if (and owner-ids (> (length owner-ids) 0))
        (shortcut--member-name (aref owner-ids 0))
      "")))

(defun shortcut--vtable-get-created-at (story _index)
  "Get formatted creation timestamp for STORY."
  (let ((created-at (alist-get 'created_at story)))
    (or (shortcut--story-format-timestamp created-at) "")))

(defun shortcut--vtable-get-deadline (story _index)
  "Get formatted deadline for STORY."
  (let ((deadline (alist-get 'deadline story)))
    (or (shortcut--story-format-timestamp deadline) "")))

(defun shortcut-stories-list-open-story ()
  "Open the story at point in a detail view."
  (interactive)
  (when-let* ((row-data (vtable-current-object))
              (story-id (alist-get 'id row-data)))
    (shortcut-story-get story-id)))

(defun shortcut-stories-list-open-story-at-mouse (event)
  "Open the story at mouse EVENT in a detail view."
  (interactive "e")
  (mouse-set-point event)
  (shortcut-stories-list-open-story))

(defun shortcut-stories-list-refresh ()
  "Refresh the stories list."
  (interactive)
  (when (derived-mode-p 'shortcut-stories-list-mode)
    (if (and shortcut-stories-list--query-field
             shortcut-stories-list--display-name)
        (shortcut--stories-list-display
         shortcut-stories-list--query-field
         shortcut-stories-list--display-name)
      (user-error "Cannot refresh: unknown query type"))))

(defvar-keymap shortcut-stories-list-mode-map
  :parent special-mode-map
  :doc "Keymap for `shortcut-stories-list-mode'."
  "RET" #'shortcut-stories-list-open-story
  "<mouse-1>" #'shortcut-stories-list-open-story-at-mouse
  "g" #'shortcut-stories-list-refresh)

(define-derived-mode shortcut-stories-list-mode special-mode "Shortcut-Stories-List"
                     "Major mode for listing Shortcut stories.

\\{shortcut-stories-list-mode-map}"
                     :group 'shortcut
                     (setq truncate-lines t))

(defun shortcut--stories-list-display (field display-name)
  "Display stories where current user matches FIELD.
FIELD should be \"requester\" or \"owner\".
DISPLAY-NAME is used for buffer name and messages (e.g., \"Requested by Me\")."
  (message "Fetching stories %s..." (downcase display-name))
  (let* ((story-ids (shortcut--stories-by-current-user-field field))
         (stories '()))
    ;; Fetch story data for each ID (uses cache when available)
    (dolist (story-id story-ids)
      (condition-case err
          (let ((story (shortcut--story-get story-id)))
            (push story stories))
        (error
         (message "Failed to fetch story %s: %s" story-id (error-message-string err)))))
    ;; Reverse to get chronological order (oldest first)
    (setq stories (nreverse stories))
    ;; Create or switch to buffer
    (let ((buffer (get-buffer-create (format "*Shortcut Stories: %s*" display-name))))
      (with-current-buffer buffer
        (let ((inhibit-read-only t))
          (erase-buffer)
          (shortcut-stories-list-mode)
          ;; Store query type for refresh functionality
          (setq-local shortcut-stories-list--query-field field)
          (setq-local shortcut-stories-list--display-name display-name)
          ;; Create vtable
          (setq shortcut-stories-list--vtable
                (make-vtable
                 :columns
                 '((:name "ID" :width 10 :getter shortcut--vtable-get-id)
                   (:name "Title" :width 50 :getter shortcut--vtable-get-title)
                   (:name "State" :width 15 :getter shortcut--vtable-get-state)
                   (:name "Epic" :width 30 :getter shortcut--vtable-get-epic)
                   (:name "Owner" :width 20 :getter shortcut--vtable-get-owner)
                   (:name "Created At" :width 16 :getter shortcut--vtable-get-created-at)
                   (:name "Deadline" :width 16 :getter shortcut--vtable-get-deadline))
                 :objects stories
                 :actions '("RET" shortcut-stories-list-open-story
                            "<mouse-1>" shortcut-stories-list-open-story-at-mouse)))
          (goto-char (point-min)))
        (display-buffer buffer)
        (message "Found %d %s %s"
                 (length stories)
                 (if (= (length stories) 1) "story" "stories")
                 (downcase display-name))))))

(defun shortcut-stories-list-requested-by-me ()
  "Display a list of stories requested by the current user.
Uses vtable to show story ID, title, state, epic, owner, and timestamps."
  (interactive)
  (shortcut--stories-list-display "requester" "Requested by Me"))

(defun shortcut-stories-list-owned-by-me ()
  "Display a list of stories owned by the current user.
Uses vtable to show story ID, title, state, epic, owner, and timestamps."
  (interactive)
  (shortcut--stories-list-display "owner" "Owned by Me"))

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
  (condition-case nil
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
  (condition-case nil
      (let* ((workflow (shortcut--workflow-get workflow-id))
             (states (alist-get 'states workflow))
             (state (seq-find (lambda (s)
                                (= (alist-get 'id s) workflow-state-id))
                              states)))
        (or (alist-get 'name state) "Unknown"))
    (error "Unknown")))

(defun shortcut--workflow-states-get (workflow-id)
  "Get all workflow states for WORKFLOW-ID.
Returns a vector of state objects, each with `id', `name', and `type' fields.
Also caches each state in `shortcut--workflow-state-cache'."
  (let* ((workflow (shortcut--workflow-get workflow-id))
         (states (alist-get 'states workflow)))
    ;; Cache each state with its type information
    (when states
      (seq-doseq (state states)
        (let* ((state-id (alist-get 'id state))
               (cache-key (format "%s:%s" workflow-id state-id)))
          (puthash cache-key state shortcut--workflow-state-cache))))
    (or states [])))

(defun shortcut--workflow-state-type-display (state-type)
  "Get a display name for STATE-TYPE.
Capitalizes the type name for display in completion groups."
  (capitalize (or state-type "Unknown")))

(defun shortcut--workflow-state-group-function (workflow-id)
  "Create a group function for workflow states in WORKFLOW-ID.
Returns a function suitable for use as completion metadata group-function."
  (lambda (candidate transform)
    "Group function for workflow state completion.
CANDIDATE is a state name string.
TRANSFORM is either nil (return group title) or non-nil (return transformed
candidate)."
    (if transform
        ;; When TRANSFORM is non-nil, return the candidate as-is
        candidate
      ;; When TRANSFORM is nil, return the group title for this candidate
      (let* ((states (shortcut--workflow-states-get workflow-id))
             (state (seq-find (lambda (s)
                                (string= (substring-no-properties candidate)
                                         (alist-get 'name s)))
                              states))
             (state-type (when state (alist-get 'type state)))
             (group-name (shortcut--workflow-state-type-display state-type)))
        group-name))))

(defun shortcut--workflow-state-annotation-function (workflow-id)
  "Create an annotation function for workflow states in WORKFLOW-ID.
Returns a function suitable for use as completion metadata annotation-function."
  (lambda (candidate)
    "Annotation function for workflow state completion.
CANDIDATE is a state name string."
    (let* ((states (shortcut--workflow-states-get workflow-id))
           (state (seq-find (lambda (s)
                              (string= (substring-no-properties candidate)
                                       (alist-get 'name s)))
                            states))
           (state-type (when state (alist-get 'type state))))
      (when state-type
        (concat (propertize " " 'display '(space :align-to center))
                (propertize (format "[%s]" state-type)
                            'face 'font-lock-comment-face))))))

(defun shortcut--workflow-state-completion-table (workflow-id)
  "Create a completion table for workflow states in WORKFLOW-ID.
Returns a function suitable for use with `completing-read'."
  (lambda (string predicate action)
    (let ((states (shortcut--workflow-states-get workflow-id)))
      (pcase action
        ('metadata
         `(metadata
           (category . shortcut-workflow-state)
           (group-function . ,(shortcut--workflow-state-group-function workflow-id))
           (annotation-function . ,(shortcut--workflow-state-annotation-function workflow-id))))
        ('lambda
            ;; Test if STRING is a valid completion
            (let ((candidates (mapcar (lambda (state) (alist-get 'name state)) states)))
              (test-completion string candidates predicate)))
        ('t
         ;; Return all completions matching STRING
         (let ((candidates (mapcar (lambda (state) (alist-get 'name state)) states)))
           (all-completions string candidates predicate)))
        (_
         ;; Default: try-completion
         (let ((candidates (mapcar (lambda (state) (alist-get 'name state)) states)))
           (try-completion string candidates predicate)))))))

(defun shortcut--group-get (group-id)
  "Get the JSON payload for group/team with GROUP-ID.
Returns the group as an alist parsed from JSON.
Results are cached in `shortcut--group-cache'."
  (let ((group-id-str (format "%s" group-id)))
    (or (gethash group-id-str shortcut--group-cache)
        (let ((group (shortcut--api-request (format "/groups/%s" group-id-str))))
          (puthash group-id-str group shortcut--group-cache)
          group))))

(defun shortcut--group-name (group-id)
  "Get the name of the group/team with GROUP-ID.
Returns the group name as a string, or nil if lookup fails or group-id is nil."
  (when group-id
    (condition-case nil
        (let ((group (shortcut--group-get group-id)))
          (alist-get 'name group))
      (error nil))))

(defun shortcut--epic-get (epic-id)
  "Get the JSON payload for epic with EPIC-ID.
Returns the epic as an alist parsed from JSON.
Results are cached in `shortcut--epic-cache'."
  (let ((epic-id-str (format "%s" epic-id)))
    (or (gethash epic-id-str shortcut--epic-cache)
        (let ((epic (shortcut--api-request (format "/epics/%s" epic-id-str))))
          (shortcut--epic-cache-add epic)
          epic))))

(defun shortcut--epic-cache-add (epic)
  "Add EPIC to the cache, storing its ID, name, state, and URL.
EPIC should be an alist with at least `id' and `name' fields."
  (when-let ((id (alist-get 'id epic))
             (name (alist-get 'name epic)))
    (let ((state (alist-get 'state epic))
          (owner-ids (alist-get 'owner_ids epic))
          (app-url (alist-get 'app_url epic)))
      (puthash (format "%s" id)
               `((id . ,id)
                 (name . ,name)
                 (state . ,state)
                 (owner_ids . ,owner-ids)
                 (app_url . ,app-url))
               shortcut--epic-cache))))

(defun shortcut--epic-cache-candidates ()
  "Get a list of epic candidates from cache for `completing-read'.
Returns an alist where keys are \"ID NAME\" strings for matching,
and values are the epic IDs (as strings without \"sc-\" prefix)."
  (let ((candidates '()))
    (maphash (lambda (key value)
               (let* ((id key)
                      (name (alist-get 'name value))
                      (display-key (if name
                                       (format "%s %s"
                                               (propertize id 'face 'shortcut-id)
                                               name)
                                     id)))
                 (push (cons display-key id) candidates)))
             shortcut--epic-cache)
    (sort candidates
          (lambda (a b)
            (> (string-to-number (cdr a))
               (string-to-number (cdr b)))))))

(defun shortcut--epic-name (epic-id)
  "Get the name of the epic with EPIC-ID.
Returns the epic name as a string, or nil if lookup fails or epic-id is nil."
  (when epic-id
    (condition-case nil
        (let ((epic (shortcut--epic-get epic-id)))
          (alist-get 'name epic))
      (error nil))))

(defun shortcut--epics-search (input)
  "Search for epics using the Shortcut Search API with INPUT string.
Returns an alist where keys are \"ID NAME\" display strings
\(with propertized ID) and values are epic IDs (as strings
without \"sc-\" prefix).
Caches retrieved epics in `shortcut--epic-cache'."
  (condition-case err
      (let* ((query (if (string-empty-p input)
                        "is:epic"
                      (format "is:epic %s" input)))
             (body `((query . ,query)
                     (entity_types . ["epic"])
                     (page_size . 50)))
             (response (shortcut--api-request "/search" "GET" body))
             (epics (alist-get 'data (alist-get 'epics response)))
             (candidates '()))
        ;; Cache each epic and collect candidates
        (when epics
          (seq-doseq (epic epics)
            (shortcut--epic-cache-add epic)
            (when-let* ((id (alist-get 'id epic))
                        (name (alist-get 'name epic))
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
     ;; On error, return empty list and log
     (message "Shortcut search API error: %s" (error-message-string err))
     '())))

(defun shortcut--epic-should-search-p (input)
  "Return non-nil if we should trigger an API search for INPUT.
Checks minimum character length."
  (>= (length input) shortcut-story-search-min-chars))

(defun shortcut--epic-merge-candidates (cache-candidates search-ids)
  "Merge CACHE-CANDIDATES with SEARCH-IDS, removing duplicates.
CACHE-CANDIDATES is an alist of (display-string . id).
SEARCH-IDS is a list of epic ID strings from API search.
Returns a merged alist sorted by ID (most recent first)."
  (let* ((cache-ids (mapcar #'cdr cache-candidates))
         (all-ids (delete-dups (append search-ids cache-ids)))
         (merged '()))
    ;; Build merged list with display strings
    (dolist (id all-ids)
      (let* ((cached-entry (gethash id shortcut--epic-cache))
             (name (alist-get 'name cached-entry))
             (display-key (if name
                              (format "%s %s"
                                      (propertize id 'face 'shortcut-id)
                                      name)
                            id)))
        (push (cons display-key id) merged)))
    merged))

(defun shortcut--epic-display-sort-function (candidates)
  "Sort epic CANDIDATES within groups by ID in descending order.
Candidates are in \"ID NAME\" format.  Sorts by epic ID (most recent first)."
  (sort candidates
        (lambda (a b)
          ;; Extract ID from "ID NAME" format
          (let ((id-a (when (string-match "^\\([0-9]+\\)" a)
                        (string-to-number (match-string 1 a))))
                (id-b (when (string-match "^\\([0-9]+\\)" b)
                        (string-to-number (match-string 1 b)))))
            (and id-a id-b (> id-a id-b))))))

(defun shortcut--epic-completion-table (string predicate action)
  "Completion table function for epic selection with dynamic search.
STRING is the current input, PREDICATE is the completion predicate,
and ACTION is the completion action (t, lambda, metadata, etc.)."
  (funcall (shortcut--make-completion-table
            :category 'shortcut-epic
            :cache-fn #'shortcut--epic-cache-candidates
            :search-fn #'shortcut--epics-search
            :merge-fn #'shortcut--epic-merge-candidates
            :should-search-fn #'shortcut--epic-should-search-p
            :annotation-fn #'shortcut--epic-annotation-function
            :group-fn #'shortcut--epic-group-function
            :sort-fn #'shortcut--epic-display-sort-function)
           string predicate action))

(defun shortcut--epic-annotation-function (candidate)
  "Annotation function for epic completion.
CANDIDATE is a display key string in format \"ID NAME\".
Returns an annotation string with state and owner."
  (let* (;; Extract the epic ID from the candidate string
         (id (when (string-match "^\\([0-9]+\\)" candidate)
               (match-string 1 candidate)))
         ;; Get epic from cache
         (epic (when id (gethash id shortcut--epic-cache)))
         (state (alist-get 'state epic))
         (owner-ids (alist-get 'owner_ids epic))
         ;; Build annotation parts
         (state-str (when state
                      (format " [%s]" state)))
         (owner-str (when (and owner-ids (> (length owner-ids) 0))
                      (let ((first-owner (aref owner-ids 0)))
                        (format " @%s" (shortcut--member-name first-owner)))))
         ;; Combine annotations
         (annotation (concat
                      (propertize " " 'display '(space :align-to center))
                      (when state-str
                        (propertize state-str 'face 'font-lock-comment-face))
                      (when owner-str
                        (propertize owner-str 'face 'font-lock-keyword-face)))))
    annotation))

(defun shortcut--epic-group-function (candidate transform)
  "Group function for epic completion.
CANDIDATE is a display key string in format \"ID NAME\".
TRANSFORM is either nil (return group title) or non-nil (return transformed
candidate).  Groups epics by their state."
  (if transform
      ;; When TRANSFORM is non-nil, return the candidate as-is
      candidate
    ;; When TRANSFORM is nil, return the group title for this candidate
    (let* (;; Extract the epic ID from the candidate string
           (id (when (string-match "^\\([0-9]+\\)" candidate)
                 (match-string 1 candidate)))
           ;; Get epic from cache
           (epic (when id (gethash id shortcut--epic-cache)))
           (state (alist-get 'state epic))
           ;; Get state name, or use "Unknown" as default
           (group-name (or state "Unknown")))
      group-name)))

;;; Story Mode

(defun shortcut-story-ret ()
  "Handle RET in story buffer.
If on a widget, activate it.  Otherwise, browse the story URL."
  (interactive)
  (if (get-char-property (point) 'button)
      (widget-button-press (point))
    (shortcut-story-browse-url)))

(define-derived-mode shortcut-base-mode magit-section-mode "Shortcut"
                     "Base major mode for viewing Shortcut entities.

\\{shortcut-base-mode-map}"
                     :group 'shortcut
                     (setq truncate-lines t)
                     (goto-address-mode +1))

(defvar-keymap shortcut-base-mode-map
  :parent magit-section-mode-map
  "q" #'quit-window)

(defvar-keymap shortcut-story-mode-map
  :parent shortcut-base-mode-map
  :doc "Keymap for `shortcut-story-mode'."
  "g" #'shortcut-story-refresh
  "C-c C-o" #'shortcut-story-browse-url
  "RET" #'shortcut-story-ret
  "M-w" #'shortcut-story-copy-id
  "s" #'shortcut-story-set-state)

(defvar-local shortcut-story--current-id nil
  "The ID of the story currently displayed in this buffer.")

(defvar-local shortcut-story--current-workflow-id nil
  "The workflow ID of the story currently displayed in this buffer.")

(defvar-local shortcut-story--current-workflow-state-id nil
  "The current workflow state ID of the story displayed in this buffer.")

(defun shortcut-story-set-state ()
  "Change the workflow state of the current story.
Prompts for a new state using `completing-read' from available workflow states.
States are grouped by type (Backlog, Unstarted, Started, Done)."
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
         (prompt (if current-state-name
                     (format "Set state (current: %s): " current-state-name)
                   "Set state: "))
         ;; Use completion table with grouping support
         (completion-table (shortcut--workflow-state-completion-table shortcut-story--current-workflow-id))
         (selected-name (completing-read prompt completion-table nil t))
         ;; Find the state ID by matching the name
         (selected-state (seq-find (lambda (state)
                                     (string= (substring-no-properties selected-name)
                                              (alist-get 'name state)))
                                   states))
         (selected-id (when selected-state (alist-get 'id selected-state))))

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

(define-derived-mode shortcut-story-mode shortcut-base-mode "Shortcut-Story"
                     "Major mode for viewing Shortcut stories.

\\{shortcut-story-mode-map}"
                     :group 'shortcut
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
  "Insert the story DESCRIPTION with proper formatting.
If DESCRIPTION is empty, shows a placeholder."
  (magit-insert-section (description)
    (magit-insert-heading "Description")
    (if (and description (not (string-empty-p description)))
        (progn
          (insert (shortcut--fontify-markdown description))
          (insert "\n\n"))
      (insert (propertize "empty" 'font-lock-face 'shortcut-placeholder))
      (insert "\n\n"))))

(defun shortcut--story-insert-tasks (tasks)
  "Insert TASKS as a checklist using Emacs checkbox widgets.
If there are no tasks, shows a placeholder."
  (magit-insert-section (tasks)
    (magit-insert-heading "Tasks")
    (if (and tasks (> (length tasks) 0))
        (progn
          (seq-doseq (task tasks)
            (let* ((complete (not (eq :json-false (alist-get 'complete task))))
                   (description (alist-get 'description task))
                   (task-id (alist-get 'id task)))
              (insert "  ")
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
                                            (shortcut-story-refresh))))))
              (insert " ")
              (let ((formatted-desc (shortcut--fontify-markdown description)))
                (if complete
                    (insert (propertize formatted-desc 'font-lock-face 'shortcut-placeholder))
                  (insert formatted-desc)))
              (insert "\n")))
          (insert "\n")
          (widget-setup))
      (insert (propertize "empty" 'font-lock-face 'shortcut-placeholder))
      (insert "\n\n"))))

(defun shortcut--story-link-invert-verb (verb)
  "Invert the relationship VERB for story links.
When the current story is the subject, we need to invert the verb.
For example: \"blocks\" becomes \"blocked by\", \"relates to\" stays \"relates to\"."
  (pcase verb
    ("blocks" "blocked by")
    ("duplicates" "duplicated by")
    ("relates to" "relates to")
    (_ verb)))

(defun shortcut--story-insert-links (story-links)
  "Insert STORY-LINKS showing relationships between stories.
If there are no story links, shows a placeholder."
  (magit-insert-section (story-links)
    (magit-insert-heading "Story Links")
    (if (and story-links (> (length story-links) 0))
        (progn
          (seq-doseq (link story-links)
            (let* ((subject-id (alist-get 'subject_id link))
                   (object-id (alist-get 'object_id link))
                   (verb (alist-get 'verb link))
                   ;; Determine which story ID to display and whether to invert verb
                   (is-subject (= subject-id shortcut-story--current-id))
                   (linked-id (if is-subject object-id subject-id))
                   (display-verb (if (not is-subject)
                                     (shortcut--story-link-invert-verb verb)
                                   verb))
                   ;; Get the linked story from cache if available
                   (linked-story (gethash (format "%s" linked-id) shortcut--story-cache))
                   (linked-name (when linked-story (alist-get 'name linked-story)))
                   (display-text (if linked-name
                                     (format "sc-%d %s" linked-id linked-name)
                                   (format "sc-%d" linked-id))))
              (insert "  ")
              (insert (propertize display-verb 'font-lock-face 'font-lock-keyword-face))
              (insert " ")
              ;; Make the story link clickable
              (insert (propertize display-text
                                  'font-lock-face 'shortcut-id
                                  'mouse-face 'highlight
                                  'help-echo "Click or press RET to view story"
                                  'keymap (let ((map (make-sparse-keymap)))
                                            (define-key map (kbd "RET")
                                              (lambda ()
                                                (interactive)
                                                (shortcut-story-get linked-id)))
                                            (define-key map (kbd "<mouse-1>")
                                              (lambda (event)
                                                (interactive "e")
                                                (mouse-set-point event)
                                                (shortcut-story-get linked-id)))
                                            (define-key map (kbd "<mouse-2>")
                                              (lambda (event)
                                                (interactive "e")
                                                (mouse-set-point event)
                                                (shortcut-story-get linked-id)))
                                            map)))
              (insert "\n")))
          (insert "\n"))
      (insert (propertize "empty" 'font-lock-face 'shortcut-placeholder))
      (insert "\n\n"))))

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
Builds a threaded view based on parent_id relationships.
If there are no comments, shows a placeholder."
  (magit-insert-section (comments nil t)
    (magit-insert-heading "Comments")
    (magit-insert-section-body
      (if (and comments (> (length comments) 0))
          ;; Insert only top-level comments (those without a parent_id or with null parent_id)
          (let ((top-level-comments (seq-filter (lambda (c)
                                                  (let ((parent-id (alist-get 'parent_id c)))
                                                    (or (null parent-id)
                                                        (eq parent-id :null))))
                                                comments)))
            (seq-doseq (comment top-level-comments)
              (shortcut--story-insert-comment comment comments)))
        (insert (propertize "empty" 'font-lock-face 'shortcut-placeholder))
        (insert "\n\n")))))

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
           (followers (alist-get 'follower_ids story))
           (requester-id (alist-get 'requested_by_id story))
           (estimate (alist-get 'estimate story))
           (epic-id (alist-get 'epic_id story))
           (iteration-id (alist-get 'iteration_id story))
           (group-id (alist-get 'group_id story))
           (deadline (alist-get 'deadline story))
           (created-at (alist-get 'created_at story))
           (updated-at (alist-get 'updated_at story))
           (completed-at (alist-get 'completed_at story))
           (description (alist-get 'description story))
           (tasks (alist-get 'tasks story))
           (story-links (alist-get 'story_links story))
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
        (when group-id
          (let ((team-name (shortcut--group-name group-id)))
            (when team-name
              (shortcut--story-insert-header "Team" team-name))))
        (when estimate
          (shortcut--story-insert-header "Estimate" (format "%d points" estimate)))
        (when epic-id
          (insert (propertize (format "%-15s" "Epic:")
                              'font-lock-face 'shortcut-story-header))
          (let* ((epic-name (shortcut--epic-name epic-id))
                 (text (if epic-name
                           (format "sc-%d %s" epic-id epic-name)
                         (format "sc-%d" epic-id))))
            (insert (propertize text
                                'font-lock-face 'shortcut-id
                                'mouse-face 'highlight
                                'help-echo "Click or press RET to view epic"
                                'keymap (let ((map (make-sparse-keymap)))
                                          (define-key map (kbd "RET")
                                            (lambda ()
                                              (interactive)
                                              (shortcut-epic-get epic-id)))
                                          (define-key map (kbd "<mouse-1>")
                                            (lambda (event)
                                              (interactive "e")
                                              (mouse-set-point event)
                                              (shortcut-epic-get epic-id)))
                                          (define-key map (kbd "<mouse-2>")
                                            (lambda (event)
                                              (interactive "e")
                                              (mouse-set-point event)
                                              (shortcut-epic-get epic-id)))
                                          map)))
            (insert "\n")))
        (when iteration-id
          (shortcut--story-insert-header "Iteration" (format "sc-%d" iteration-id) 'shortcut-id))

        (shortcut--story-insert-labels labels)

        (when owners
          (shortcut--story-insert-header "Owners"
                                         (mapconcat #'shortcut--member-name
                                                    owners ", ")))

        (when followers
          (shortcut--story-insert-header "Followers"
                                         (mapconcat #'shortcut--member-name
                                                    followers ", ")))

        (when requester-id
          (shortcut--story-insert-header "Requester"
                                         (shortcut--member-name requester-id)))

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
      (shortcut--story-insert-links story-links)
      (shortcut--story-insert-description description)
      (shortcut--story-insert-comments comments))))

(defun shortcut--story-affixation-function (candidates)
  "Affixation function for story completion.
CANDIDATES is a list of display keys from the alist (strings in format
\\'ID TITLE\\').  Returns a list of (candidate prefix suffix) for each
candidate, adding \\'sc-\\' prefix."
  (mapcar (lambda (candidate)
            (list candidate
                  (propertize "sc-" 'face 'shortcut-id)
                  ""))
          candidates))

(defun shortcut--story-annotation-function (candidate)
  "Annotation function for story completion.
CANDIDATE is a display key string in format \"ID TITLE\".
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
CANDIDATE is a display key string in format \"ID TITLE\".
TRANSFORM is either nil (return group title) or non-nil (return transformed
candidate).  Groups stories by their epic name, with stories without epics
in \"No Epic\" group."
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
When called interactively, prompts for the story ID using `completing-read'.
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

(defvar-keymap shortcut-epic-mode-map
  :parent shortcut-base-mode-map
  :doc "Keymap for `shortcut-epic-mode'."
  "g" #'shortcut-epic-refresh
  "C-c C-o" #'shortcut-epic-browse-url
  "RET" #'shortcut-epic-ret
  "M-w" #'shortcut-epic-copy-id)

(defvar-local shortcut-epic--current-id nil
  "The ID of the epic currently displayed in this buffer.")

(defvar-local shortcut-epic--current-state-id nil
  "The current state ID of the epic displayed in this buffer.")

(define-derived-mode shortcut-epic-mode shortcut-base-mode "Shortcut-Epic"
                     "Major mode for viewing Shortcut epics.

\\{shortcut-epic-mode-map}"
                     :group 'shortcut)

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
When called interactively, prompts for the epic ID using `completing-read'.
Supports dynamic searching - type to search for epics via the API,
or select from cached epics."
  (interactive
   (let* (;; Use completion table function for dynamic search
          (id-str (completing-read "Epic ID: "
                                   #'shortcut--epic-completion-table
                                   nil nil))
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
  (condition-case nil
      (let* ((member (shortcut--member-current))
             (workspace (alist-get 'workspace2 member)))
        (or (alist-get 'name workspace) "Unknown"))
    (error "Unknown")))

(defun shortcut--current-user-name ()
  "Get the name of the current authenticated user.
Returns the user name as a string, or \"Unknown\" if lookup fails."
  (condition-case nil
      (or (alist-get 'name (shortcut--member-current)) "Unknown")
    (error "Unknown")))

(defun shortcut--current-user-mention-name ()
  "Get the mention name of the current authenticated user.
Returns the mention name as a string, or nil if lookup fails.
The mention name is used in search queries (e.g., requester:username)."
  (condition-case nil
      (let* ((member (shortcut--member-current)))
        (alist-get 'mention_name member))
    (error nil)))

;;; Transient Interface

(defun shortcut-story-create ()
  "Create a new Shortcut story.
This command is not yet implemented."
  (interactive)
  (user-error "Story creation is not yet implemented"))

(defun shortcut-epic-create ()
  "Create a new Shortcut epic.
This command is not yet implemented."
  (interactive)
  (user-error "Epic creation is not yet implemented"))

(defun shortcut-story-list ()
  "List all stories.
This command is not yet implemented."
  (interactive)
  (user-error "Story listing is not yet implemented"))

(defun shortcut-epic-list ()
  "List all epics.
This command is not yet implemented."
  (interactive)
  (user-error "Epic listing is not yet implemented"))

(defun shortcut-story-cache-populate (query)
  "Pre-populate the story cache with stories matching QUERY.
Prompts for a query string and searches for stories using the Shortcut API.
Results are added to the story cache for faster completion."
  (interactive "sSearch query: ")
  (message "Searching for stories...")
  (let ((results (shortcut--stories-search query)))
    (message "Added %d stories to cache" (length results))))

(transient-define-prefix shortcut-dispatch ()
  "Dispatch Shortcut commands."
  :transient-non-suffix #'transient--do-call
  [:description
   (lambda () (format "Shortcut: %s (%s)"
                      (shortcut--workspace-name)
                      (shortcut--current-user-name)))
   ["Visit"
    ("v s" "story" shortcut-story-get)
    ("v e" "epic" shortcut-epic-get)]
   ["List"
    ("l s" "stories requested by me" shortcut-stories-list-requested-by-me)
    ("l o" "stories owned by me" shortcut-stories-list-owned-by-me)
    ("l e" "epics" shortcut-epic-list :transient nil :inapt-if (lambda () t))]
   ["Create"
    ("c s" "story" shortcut-story-create :transient nil :inapt-if (lambda () t))
    ("c e" "epic" shortcut-epic-create :transient nil :inapt-if (lambda () t))]
   ["Experimental"
    ("x c" "pre-populate story cache with..." shortcut-story-cache-populate)
    ("x C" "clear story cache" shortcut--clear-story-cache)
    ("x X" "clear ALL caches" shortcut--clear-all-caches)]])

(provide 'shortcut)

;;; shortcut.el ends here
