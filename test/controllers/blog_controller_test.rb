require "test_helper"

class BlogControllerTest < ActionDispatch::IntegrationTest
  test "index is accessible and shows published posts" do
    get blog_path

    assert_response :success
    assert_match blog_posts(:published_one).title, response.body
    assert_match blog_posts(:published_two).title, response.body
    assert_no_match blog_posts(:draft_one).title, response.body
  end

  test "index filters by category" do
    get blog_path(category: blog_categories(:product_updates).slug)

    assert_response :success
    assert_match blog_posts(:published_two).title, response.body
    assert_no_match blog_posts(:published_one).title, response.body
  end

  test "show returns published post" do
    get blog_post_path(blog_posts(:published_one).slug)

    assert_response :success
    assert_match blog_posts(:published_one).title, response.body
    assert_match "application/ld+json", response.body
    assert_match "BlogPosting", response.body
    assert_match "meta name=\"description\"", response.body
    assert_match "rel=\"canonical\"", response.body
  end

  test "show returns 404 for draft post" do
    get blog_post_path(blog_posts(:draft_one).slug)

    assert_response :not_found
  end

  test "feed is accessible" do
    get blog_feed_path

    assert_response :success
    assert_match "application/atom+xml", response.media_type
  end
end
