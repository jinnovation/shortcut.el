;;; fixtures.el --- Test fixtures for shortcut.el -*- lexical-binding: t; -*-

;; Copyright (C) 2024

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Test fixtures and mock data for shortcut.el tests

;;; Code:

(defvar shortcut-test-story-fixture
  '((id . 12345)
    (name . "Test Story")
    (description . "This is a test story")
    (story_type . "feature")
    (workflow_state_id . 500000001)
    (workflow_id . 500000000)
    (created_at . "2024-01-01T10:00:00Z")
    (updated_at . "2024-01-01T12:00:00Z")
    (completed . :json-false)
    (archived . :json-false)
    (started . t)
    (started_at . "2024-01-01T11:00:00Z")
    (completed_at . nil)
    (app_url . "https://app.shortcut.com/org/story/12345")
    (entity_type . "story")
    (owner_ids . ["uuid-owner-1"])
    (follower_ids . ["uuid-follower-1" "uuid-follower-2"])
    (requested_by_id . "uuid-requester-1")
    (epic_id . nil)
    (iteration_id . nil)
    (estimate . 3)
    (position . 1000)
    (blocked . :json-false)
    (blocker . :json-false)
    (external_links . [])
    (labels . [])
    (tasks . [])
    (comments . [])
    (files . [])
    (linked_files . [])
    (branches . [])
    (commits . [])
    (pull_requests . []))
  "A sample story object matching the Shortcut API specification.")

(provide 'fixtures)
;;; fixtures.el ends here
