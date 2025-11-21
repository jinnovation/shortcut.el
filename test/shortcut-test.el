;;; shortcut-test.el --- Tests for shortcut.el -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

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

;;; shortcut-test.el ends here
