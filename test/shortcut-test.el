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

;;; shortcut-test.el ends here
