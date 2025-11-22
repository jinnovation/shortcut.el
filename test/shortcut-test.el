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

(describe "shortcut--iteration-get"
  (before-each
    ;; Clear the cache before each test
    (clrhash shortcut--iteration-cache))

  (it "should fetch and cache an iteration from the API"
    (let ((iteration-id 11111))
      ;; Mock the API request function to return fixture data
      (spy-on 'shortcut--api-request
              :and-return-value shortcut-test-iteration-fixture)

      ;; Call the function under test
      (let ((result (shortcut--iteration-get iteration-id)))
        ;; Verify API was called with correct endpoint
        (expect 'shortcut--api-request
                :to-have-been-called-with "/iterations/11111")

        ;; Verify the result matches the fixture
        (expect result :to-equal shortcut-test-iteration-fixture)

        ;; Verify the iteration ID is in the result
        (expect (alist-get 'id result) :to-equal iteration-id)

        ;; Verify the iteration name is correct
        (expect (alist-get 'name result) :to-equal "Sprint 42")

        ;; Verify the iteration was cached (cache uses string keys)
        (expect (gethash (format "%s" iteration-id) shortcut--iteration-cache) :not :to-be nil))))

  (it "should return cached iteration on second call without hitting API"
    (let ((iteration-id 11111))
      ;; Mock the API request function
      (spy-on 'shortcut--api-request
              :and-return-value shortcut-test-iteration-fixture)

      ;; First call - should hit API
      (shortcut--iteration-get iteration-id)
      (expect 'shortcut--api-request :to-have-been-called-times 1)

      ;; Second call - should use cache
      (let ((result (shortcut--iteration-get iteration-id)))
        ;; API should still only have been called once
        (expect 'shortcut--api-request :to-have-been-called-times 1)

        ;; Result should still be correct (cached version with subset of fields)
        (expect (alist-get 'id result) :to-equal iteration-id)
        (expect (alist-get 'name result) :to-equal "Sprint 42")
        (expect (alist-get 'status result) :to-equal "started")
        (expect (alist-get 'app_url result) :to-equal "https://app.shortcut.com/org/iteration/11111")
        (expect (alist-get 'description result) :to-equal "Q4 2024 Sprint 42")))))

(describe "shortcut--iteration-name"
  (before-each
    ;; Clear the cache before each test
    (clrhash shortcut--iteration-cache))

  (it "should return the iteration name"
    (let ((iteration-id 11111))
      ;; Mock the API request function to return fixture data
      (spy-on 'shortcut--api-request
              :and-return-value shortcut-test-iteration-fixture)

      ;; Call the function under test
      (let ((result (shortcut--iteration-name iteration-id)))
        ;; Verify the result is the iteration name
        (expect result :to-equal "Sprint 42"))))

  (it "should return nil for nil iteration-id"
    (let ((result (shortcut--iteration-name nil)))
      (expect result :to-be nil))))

(describe "shortcut--iteration-cache-candidates"
  (before-each
    ;; Clear the cache before each test
    (clrhash shortcut--iteration-cache))

  (it "should return formatted candidates from cache"
    ;; Add test iteration to cache
    (shortcut--iteration-cache-add shortcut-test-iteration-fixture)

    ;; Call the function under test
    (let ((result (shortcut--iteration-cache-candidates)))
      ;; Verify we got one candidate
      (expect (length result) :to-equal 1)

      ;; Verify the candidate format (cons cell with display key and ID)
      (let* ((candidate (car result))
             (display-key (car candidate))
             (id (cdr candidate)))
        ;; Verify ID is correct
        (expect id :to-equal "11111")

        ;; Verify display key contains both ID and name
        (expect display-key :to-match "11111")
        (expect display-key :to-match "Sprint 42")))))

(describe "shortcut--iteration-completion-table"
  (before-each
    ;; Clear the cache before each test
    (clrhash shortcut--iteration-cache))

  (it "should be a valid completion table function"
    ;; Verify the function is defined and callable
    (expect (fboundp 'shortcut--iteration-completion-table) :to-be-truthy)))

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

(describe "shortcut--iterations-search"
  (before-each
    ;; Clear the cache before each test
    (clrhash shortcut--iteration-cache))

  (it "should search for iterations and return formatted candidates"
    (let ((search-response
           '((total . 2)
             (data . [((id . 11111)
                       (name . "Sprint 42")
                       (status . "started"))
                      ((id . 22222)
                       (name . "Sprint 43")
                       (status . "unstarted"))])
             (next . nil))))
      ;; Mock the API request to return search results
      (spy-on 'shortcut--api-request
              :and-return-value search-response)

      ;; Call the function under test
      (let ((result (shortcut--iterations-search "Sprint")))
        ;; Verify API was called with correct search endpoint
        (expect 'shortcut--api-request
                :to-have-been-called)

        ;; Verify the result is an alist
        (expect (listp result) :to-be-truthy)
        (expect (length result) :to-equal 2)

        ;; Verify the candidates are in the correct format (display-key . id)
        (let ((first-candidate (car result))
              (second-candidate (cadr result)))
          ;; Results should be sorted by ID descending (most recent first)
          (expect (cdr first-candidate) :to-equal "22222")
          (expect (cdr second-candidate) :to-equal "11111")

          ;; Display keys should contain ID and name
          (expect (car first-candidate) :to-match "22222")
          (expect (car first-candidate) :to-match "Sprint 43")
          (expect (car second-candidate) :to-match "11111")
          (expect (car second-candidate) :to-match "Sprint 42"))

        ;; Verify iterations were cached
        (expect (gethash "11111" shortcut--iteration-cache) :not :to-be nil)
        (expect (gethash "22222" shortcut--iteration-cache) :not :to-be nil))))

  (it "should handle empty search input with default query"
    (spy-on 'shortcut--api-request
            :and-return-value '((total . 0) (data . []) (next . nil)))

    (shortcut--iterations-search "")

    ;; Verify API was called
    (expect 'shortcut--api-request :to-have-been-called))

  (it "should return empty list on API error"
    (spy-on 'shortcut--api-request
            :and-call-fake (lambda (&rest _) (error "API error")))

    (let ((result (shortcut--iterations-search "test")))
      ;; Should return empty list on error
      (expect result :to-equal '()))))

(describe "shortcut--iteration-should-search-p"
  (it "should return t when input meets minimum character threshold"
    ;; Assuming shortcut-story-search-min-chars is 2 (default)
    (let ((shortcut-story-search-min-chars 2))
      (expect (shortcut--iteration-should-search-p "ab") :to-be-truthy)
      (expect (shortcut--iteration-should-search-p "abc") :to-be-truthy)))

  (it "should return nil when input is below minimum character threshold"
    (let ((shortcut-story-search-min-chars 2))
      (expect (shortcut--iteration-should-search-p "a") :not :to-be-truthy)
      (expect (shortcut--iteration-should-search-p "") :not :to-be-truthy))))

(describe "shortcut--iteration-merge-candidates"
  (before-each
    ;; Clear and populate cache for testing
    (clrhash shortcut--iteration-cache)
    (puthash "11111" '((id . 11111) (name . "Sprint 42")) shortcut--iteration-cache)
    (puthash "22222" '((id . 22222) (name . "Sprint 43")) shortcut--iteration-cache)
    (puthash "33333" '((id . 33333) (name . "Sprint 44")) shortcut--iteration-cache))

  (it "should merge cache and search results without duplicates"
    (let ((cache-candidates '(("11111 Sprint 42" . "11111")
                              ("22222 Sprint 43" . "22222")))
          (search-ids '("22222" "33333"))) ; 22222 is duplicate
      (let ((result (shortcut--iteration-merge-candidates cache-candidates search-ids)))
        ;; Should have 3 unique IDs
        (expect (length result) :to-equal 3)
        ;; Should contain all three IDs
        (let ((ids (mapcar #'cdr result)))
          (expect (member "11111" ids) :to-be-truthy)
          (expect (member "22222" ids) :to-be-truthy)
          (expect (member "33333" ids) :to-be-truthy)))))

  (it "should use cached names for display keys"
    (let ((cache-candidates '())
          (search-ids '("11111")))
      (let* ((result (shortcut--iteration-merge-candidates cache-candidates search-ids))
             (first-candidate (car result)))
        ;; Display key should include name from cache
        (expect (car first-candidate) :to-match "Sprint 42")))))

(describe "shortcut--iteration-completion-table"
  (before-each
    ;; Clear the cache before each test
    (clrhash shortcut--iteration-cache))

  (it "should be a valid completion table function"
    ;; Verify the function is defined and callable
    (expect (fboundp 'shortcut--iteration-completion-table) :to-be-truthy))

  (it "should return metadata with correct category"
    (let ((metadata (shortcut--iteration-completion-table "" nil 'metadata)))
      ;; Should return metadata alist
      (expect (eq (car metadata) 'metadata) :to-be-truthy)
      ;; Should have shortcut-iteration category
      (expect (alist-get 'category (cdr metadata)) :to-equal 'shortcut-iteration))))

;;; shortcut-test.el ends here
