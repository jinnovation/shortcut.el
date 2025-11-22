;;; shortcut-test.el --- Tests for shortcut.el -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

(when (require 'undercover nil t)
  (undercover "*.el"
              (:report-file "./coverage/lcov-buttercup.info")
              (:report-format 'lcov)
              (:merge-report nil)
              (:send-report nil)))

(require 'buttercup)
(require 'shortcut)
(load (expand-file-name "fixtures.el" (file-name-directory (or load-file-name buffer-file-name))))

(describe "shortcut--story-get"
  (before-each
    ;; Clear the cache before each test
    (clrhash shortcut--story-cache))

  (it "should fetch and cache a story from the API"
    (let ((story-id 12345))
      ;; Mock the API request function to return fixture data
      (spy-on 'shortcut--api-request
              :and-return-value shortcut-test-story-fixture)

      ;; Call the function under test
      (let ((result (shortcut--story-get story-id)))
        ;; Verify API was called with correct endpoint
        (expect 'shortcut--api-request
                :to-have-been-called-with "/stories/12345")

        ;; Verify the result matches the fixture
        (expect result :to-equal shortcut-test-story-fixture)

        ;; Verify the story ID is in the result
        (expect (alist-get 'id result) :to-equal story-id)

        ;; Verify the story name is correct
        (expect (alist-get 'name result) :to-equal "Test Story")

        ;; Verify the story was cached (cache uses string keys)
        (expect (gethash (format "%s" story-id) shortcut--story-cache) :not :to-be nil)))))

(describe "shortcut--epic-get"
  (before-each
    ;; Clear the cache before each test
    (clrhash shortcut--epic-cache))

  (it "should fetch and cache an epic from the API"
    (let ((epic-id 67890))
      ;; Mock the API request function to return fixture data
      (spy-on 'shortcut--api-request
              :and-return-value shortcut-test-epic-fixture)

      ;; Call the function under test
      (let ((result (shortcut--epic-get epic-id)))
        ;; Verify API was called with correct endpoint
        (expect 'shortcut--api-request
                :to-have-been-called-with "/epics/67890")

        ;; Verify the result matches the fixture
        (expect result :to-equal shortcut-test-epic-fixture)

        ;; Verify the epic ID is in the result
        (expect (alist-get 'id result) :to-equal epic-id)

        ;; Verify the epic name is correct
        (expect (alist-get 'name result) :to-equal "Test Epic")

        ;; Verify the epic was cached (cache uses string keys)
        (expect (gethash (format "%s" epic-id) shortcut--epic-cache) :not :to-be nil))))

  (it "should return cached epic on second call without hitting API"
    (let ((epic-id 67890))
      ;; Mock the API request function
      (spy-on 'shortcut--api-request
              :and-return-value shortcut-test-epic-fixture)

      ;; First call - should hit API
      (shortcut--epic-get epic-id)
      (expect 'shortcut--api-request :to-have-been-called-times 1)

      ;; Second call - should use cache
      (let ((result (shortcut--epic-get epic-id)))
        ;; API should still only have been called once
        (expect 'shortcut--api-request :to-have-been-called-times 1)

        ;; Result should still be correct (cached version with subset of fields)
        (expect (alist-get 'id result) :to-equal epic-id)
        (expect (alist-get 'name result) :to-equal "Test Epic")
        (expect (alist-get 'state result) :to-equal "in progress")
        (expect (alist-get 'app_url result) :to-equal "https://app.shortcut.com/org/epic/67890")
        (expect (alist-get 'description result) :to-equal "This is a test epic")))))

(describe "shortcut--workflow-get"
  (before-each
    ;; Clear the cache before each test
    (clrhash shortcut--workflow-cache))

  (it "should fetch and cache a workflow from the API"
    (let ((workflow-id 500000000))
      ;; Mock the API request function to return fixture data
      (spy-on 'shortcut--api-request
              :and-return-value shortcut-test-workflow-fixture)

      ;; Call the function under test
      (let ((result (shortcut--workflow-get workflow-id)))
        ;; Verify API was called with correct endpoint
        (expect 'shortcut--api-request
                :to-have-been-called-with "/workflows/500000000")

        ;; Verify the result matches the fixture
        (expect result :to-equal shortcut-test-workflow-fixture)

        ;; Verify the workflow ID is in the result
        (expect (alist-get 'id result) :to-equal workflow-id)

        ;; Verify the workflow name is correct
        (expect (alist-get 'name result) :to-equal "Default Workflow")

        ;; Verify the workflow was cached (cache uses string keys)
        (expect (gethash (format "%s" workflow-id) shortcut--workflow-cache) :not :to-be nil))))

  (it "should return cached workflow on second call without hitting API"
    (let ((workflow-id 500000000))
      ;; Mock the API request function
      (spy-on 'shortcut--api-request
              :and-return-value shortcut-test-workflow-fixture)

      ;; First call - should hit API
      (shortcut--workflow-get workflow-id)
      (expect 'shortcut--api-request :to-have-been-called-times 1)

      ;; Second call - should use cache
      (let ((result (shortcut--workflow-get workflow-id)))
        ;; API should still only have been called once
        (expect 'shortcut--api-request :to-have-been-called-times 1)

        ;; Result should still be correct (full fixture since workflow caches everything)
        (expect result :to-equal shortcut-test-workflow-fixture)))))

(describe "shortcut-member-get"
  (before-each
    ;; Clear the cache before each test
    (clrhash shortcut--member-cache))

  (it "should fetch and cache a member from the API"
    (let ((member-id "uuid-member-123"))
      ;; Mock the API request function to return fixture data
      (spy-on 'shortcut--api-request
              :and-return-value shortcut-test-member-fixture)

      ;; Call the function under test
      (let ((result (shortcut-member-get member-id)))
        ;; Verify API was called with correct endpoint
        (expect 'shortcut--api-request
                :to-have-been-called-with "/members/uuid-member-123")

        ;; Verify the result matches the fixture
        (expect result :to-equal shortcut-test-member-fixture)

        ;; Verify the member ID is in the result
        (expect (alist-get 'id result) :to-equal member-id)

        ;; Verify the member name is accessible via profile
        (let ((profile (alist-get 'profile result)))
          (expect (alist-get 'name profile) :to-equal "Test User")
          (expect (alist-get 'mention_name profile) :to-equal "testuser"))

        ;; Verify the member was cached (cache uses string keys)
        (expect (gethash member-id shortcut--member-cache) :not :to-be nil))))

  (it "should return cached member on second call without hitting API"
    (let ((member-id "uuid-member-123"))
      ;; Mock the API request function
      (spy-on 'shortcut--api-request
              :and-return-value shortcut-test-member-fixture)

      ;; First call - should hit API
      (shortcut-member-get member-id)
      (expect 'shortcut--api-request :to-have-been-called-times 1)

      ;; Second call - should use cache
      (let ((result (shortcut-member-get member-id)))
        ;; API should still only have been called once
        (expect 'shortcut--api-request :to-have-been-called-times 1)

        ;; Result should still be correct
        (expect result :to-equal shortcut-test-member-fixture)))))

(describe "shortcut--member-name"
  (before-each
    ;; Clear the cache before each test
    (clrhash shortcut--member-cache))

  (it "should return member name from profile"
    (let ((member-id "uuid-member-123"))
      ;; Mock shortcut-member-get to return fixture
      (spy-on 'shortcut-member-get
              :and-return-value shortcut-test-member-fixture)

      ;; Call the function under test
      (let ((result (shortcut--member-name member-id)))
        ;; Should return the name from the profile
        (expect result :to-equal "Test User"))))

  (it "should fall back to member-level name if profile name is missing"
    (let ((member-id "uuid-member-456")
          (member-without-profile-name
           '((id . "uuid-member-456")
             (name . "Fallback User")
             (profile . ((id . "uuid-profile-456")
                         (mention_name . "fallbackuser"))))))
      ;; Mock shortcut-member-get to return member without profile name
      (spy-on 'shortcut-member-get
              :and-return-value member-without-profile-name)

      ;; Call the function under test
      (let ((result (shortcut--member-name member-id)))
        ;; Should return the name from the member object itself
        (expect result :to-equal "Fallback User"))))

  (it "should return member-id as string if name lookup fails completely"
    (let ((member-id "uuid-member-789")
          (member-without-names
           '((id . "uuid-member-789")
             (profile . ((id . "uuid-profile-789")
                         (mention_name . "noname"))))))
      ;; Mock shortcut-member-get to return member without any name
      (spy-on 'shortcut-member-get
              :and-return-value member-without-names)

      ;; Call the function under test
      (let ((result (shortcut--member-name member-id)))
        ;; Should return the member-id as a string
        (expect result :to-equal "uuid-member-789"))))

  (it "should return member-id as string on error"
    (let ((member-id "uuid-member-error"))
      ;; Mock shortcut-member-get to throw an error
      (spy-on 'shortcut-member-get
              :and-call-fake (lambda (_) (error "API error")))

      ;; Call the function under test
      (let ((result (shortcut--member-name member-id)))
        ;; Should return the member-id as a string
        (expect result :to-equal "uuid-member-error")))))

(describe "shortcut--epic-health"
  (before-each
    ;; Clear the cache before each test
    (clrhash shortcut--epic-cache))

  (it "should return health status, message, and updated-at as list"
    (let ((epic-id 67890))
      ;; Mock shortcut--epic-get to return fixture with health
      (spy-on 'shortcut--epic-get
              :and-return-value shortcut-test-epic-fixture)

      ;; Call the function under test
      (let ((result (shortcut--epic-health epic-id)))
        ;; Should return a list (STATUS MESSAGE UPDATED-AT)
        (expect (listp result) :to-be-truthy)
        (expect (nth 0 result) :to-equal "On Track")
        (expect (nth 1 result) :to-equal "All tasks on schedule")
        (expect (nth 2 result) :to-equal "2024-01-15T14:00:00Z"))))

  (it "should return nil when epic-id is nil"
    (let ((result (shortcut--epic-health nil)))
      ;; Should return nil for nil epic-id
      (expect result :to-be nil)))

  (it "should return nil when health field is missing"
    (let ((epic-id 99999)
          (epic-without-health
           '((id . 99999)
             (name . "Epic Without Health")
             (state . "in progress"))))
      ;; Mock shortcut--epic-get to return epic without health
      (spy-on 'shortcut--epic-get
              :and-return-value epic-without-health)

      ;; Call the function under test
      (let ((result (shortcut--epic-health epic-id)))
        ;; Should return nil when health field is missing
        (expect result :to-be nil))))

  (it "should return nil on API error"
    (let ((epic-id 88888))
      ;; Mock shortcut--epic-get to throw an error
      (spy-on 'shortcut--epic-get
              :and-call-fake (lambda (_) (error "API error")))

      ;; Call the function under test
      (let ((result (shortcut--epic-health epic-id)))
        ;; Should return nil on error
        (expect result :to-be nil))))

  (it "should handle health with status but no text or updated-at"
    (let ((epic-id 77777)
          (epic-with-status-only
           '((id . 77777)
             (name . "Epic With Status Only")
             (health . ((status . "At Risk"))))))
      ;; Mock shortcut--epic-get to return epic with status but no text
      (spy-on 'shortcut--epic-get
              :and-return-value epic-with-status-only)

      ;; Call the function under test
      (let ((result (shortcut--epic-health epic-id)))
        ;; Should return list with status and nil for text and updated-at
        (expect (listp result) :to-be-truthy)
        (expect (nth 0 result) :to-equal "At Risk")
        (expect (nth 1 result) :to-be nil)
        (expect (nth 2 result) :to-be nil)))))

(describe "shortcut--story-create"
  (before-each
    ;; Clear the cache before each test
    (clrhash shortcut--story-cache))

  (it "should create a story via POST to /stories endpoint"
    (let ((params shortcut-test-story-create-params))
      ;; Mock the API request to return a created story
      (spy-on 'shortcut--api-request
              :and-return-value shortcut-test-story-fixture)

      ;; Call the function under test
      (let ((result (shortcut--story-create params)))
        ;; Verify API was called with correct method and endpoint
        (expect 'shortcut--api-request
                :to-have-been-called-with "/stories" "POST" params)

        ;; Verify the result matches the fixture
        (expect result :to-equal shortcut-test-story-fixture)

        ;; Verify the story was cached (cache uses string keys)
        (let ((story-id (alist-get 'id result)))
          (expect (gethash (format "%s" story-id) shortcut--story-cache)
                  :not :to-be nil)))))

  (it "should handle story creation with minimal required fields"
    (let ((minimal-params '((name . "Minimal Story")
                            (workflow_state_id . 500000001))))
      ;; Mock the API request
      (spy-on 'shortcut--api-request
              :and-return-value shortcut-test-story-fixture)

      ;; Call the function under test
      (shortcut--story-create minimal-params)

      ;; Verify API was called with minimal params
      (expect 'shortcut--api-request
              :to-have-been-called-with "/stories" "POST" minimal-params))))

(describe "shortcut--workflow-default-state-id"
  (before-each
    ;; Clear the cache before each test
    (clrhash shortcut--workflow-cache)
    (clrhash shortcut--workflow-state-cache))

  (it "should return the first 'unstarted' state when available"
    (let ((workflow-id 500000000))
      ;; Mock workflow-get to return the fixture
      (spy-on 'shortcut--workflow-get
              :and-return-value shortcut-test-workflow-fixture)

      ;; Call the function under test
      (let ((result (shortcut--workflow-default-state-id workflow-id)))
        ;; Should return the ID of the 'Unstarted' state (first unstarted state)
        (expect result :to-equal 500000001))))

  (it "should return the first 'backlog' state when available"
    (let ((workflow-id 500000100))
      ;; Mock workflow-get to return the backlog fixture
      (spy-on 'shortcut--workflow-get
              :and-return-value shortcut-test-workflow-fixture-with-backlog)

      ;; Call the function under test
      (let ((result (shortcut--workflow-default-state-id workflow-id)))
        ;; Should return the ID of the 'Backlog' state
        (expect result :to-equal 500000101))))

  (it "should return the first state if no backlog or unstarted state exists"
    (let ((workflow-id 999999)
          (custom-workflow '((id . 999999)
                             (states . [((id . 800000001)
                                         (name . "First State")
                                         (type . "started"))
                                        ((id . 800000002)
                                         (name . "Second State")
                                         (type . "done"))]))))
      ;; Mock workflow-get to return a custom workflow with no backlog/unstarted
      (spy-on 'shortcut--workflow-get
              :and-return-value custom-workflow)

      ;; Call the function under test
      (let ((result (shortcut--workflow-default-state-id workflow-id)))
        ;; Should return the ID of the first state
        (expect result :to-equal 800000001)))))

(describe "shortcut--buttonize-id"
  (it "should format ID without name"
    (let ((result (shortcut--buttonize-id 123 'story)))
      (expect result :to-equal "sc-123")))

  (it "should format ID with name"
    (let ((result (shortcut--buttonize-id 123 'story "My Story")))
      (expect result :to-equal "sc-123 My Story")))

  (it "should apply correct text properties"
    (let ((result (shortcut--buttonize-id 123 'story)))
      (expect (get-text-property 0 'font-lock-face result) :to-equal 'shortcut-id)
      (expect (get-text-property 0 'mouse-face result) :to-equal 'highlight)))

  (it "should create help-echo with entity type"
    (let ((result-story (shortcut--buttonize-id 123 'story))
          (result-epic (shortcut--buttonize-id 456 'epic)))
      (expect (get-text-property 0 'help-echo result-story) :to-equal "Click or press RET to view story")
      (expect (get-text-property 0 'help-echo result-epic) :to-equal "Click or press RET to view epic")))

  (it "should set up keymap with RET, mouse-1, and mouse-2"
    (let* ((result (shortcut--buttonize-id 123 'story))
           (keymap (get-text-property 0 'keymap result)))
      (expect (keymapp keymap) :to-be-truthy)
      (expect (lookup-key keymap (kbd "RET")) :to-be-truthy)
      (expect (lookup-key keymap (kbd "<mouse-1>")) :to-be-truthy)
      (expect (lookup-key keymap (kbd "<mouse-2>")) :to-be-truthy))))

(describe "shortcut--buttonize-story-id"
  (it "should return propertized string with sc-ID format"
    (let ((result (shortcut--buttonize-story-id 12345)))
      (expect result :to-equal "sc-12345")
      (expect (get-text-property 0 'font-lock-face result) :to-equal 'shortcut-id)
      (expect (get-text-property 0 'mouse-face result) :to-equal 'highlight)
      (expect (get-text-property 0 'help-echo result) :to-match "view story")))

  (it "should include name when provided"
    (let ((result (shortcut--buttonize-story-id 12345 "Test Story")))
      (expect result :to-equal "sc-12345 Test Story")))

  (it "should have clickable keymap with RET binding"
    (let* ((result (shortcut--buttonize-story-id 12345))
           (keymap (get-text-property 0 'keymap result)))
      (expect keymap :not :to-be nil)
      (expect (lookup-key keymap (kbd "RET")) :not :to-be nil)
      (expect (lookup-key keymap (kbd "<mouse-1>")) :not :to-be nil))))

(describe "shortcut--buttonize-epic-id"
  (it "should return propertized string for epic"
    (let ((result (shortcut--buttonize-epic-id 67890)))
      (expect result :to-equal "sc-67890")
      (expect (get-text-property 0 'help-echo result) :to-match "view epic")))

  (it "should include epic name when provided"
    (let ((result (shortcut--buttonize-epic-id 67890 "Test Epic")))
      (expect result :to-equal "sc-67890 Test Epic"))))

(describe "shortcut--buttonize-iteration-id"
  :var (shortcut-iteration-get-exists)

  (before-all
    ;; Check if shortcut-iteration-get function exists
    (setq shortcut-iteration-get-exists (fboundp 'shortcut-iteration-get)))

  (it "should return propertized string for iteration"
    (assume shortcut-iteration-get-exists "shortcut-iteration-get not yet implemented")
    (let ((result (shortcut--buttonize-iteration-id 999)))
      (expect result :to-equal "sc-999")
      (expect (get-text-property 0 'help-echo result) :to-match "view iteration")))

  (it "should include iteration name when provided"
    (assume shortcut-iteration-get-exists "shortcut-iteration-get not yet implemented")
    (let ((result (shortcut--buttonize-iteration-id 999 "Sprint 10")))
      (expect result :to-equal "sc-999 Sprint 10"))))

;;; shortcut-test.el ends here
