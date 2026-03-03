require "test_helper"

class Admin::BlogPostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin_user = admin_users(:one)
    @blog_post = blog_posts(:published_one)
  end

  test "requires admin authentication" do
    get admin_blog_posts_path
    assert_redirected_to new_admin_session_path
  end

  test "index renders for admin" do
    sign_in_as_admin(@admin_user)
    get admin_blog_posts_path

    assert_response :success
    assert_match @blog_post.title, response.body
  end

  test "create blog post" do
    sign_in_as_admin(@admin_user)

    assert_difference "BlogPost.count", 1 do
      post admin_blog_posts_path, params: {
        blog_post: {
          title: "New Admin Post",
          body: "Hello world",
          status: "draft",
          blog_category_id: blog_categories(:guides).id
        }
      }
    end

    assert_redirected_to admin_blog_post_path(BlogPost.order(:created_at).last)
  end

  test "publish sets published status" do
    sign_in_as_admin(@admin_user)

    post publish_admin_blog_post_path(blog_posts(:draft_one))

    assert_redirected_to admin_blog_post_path(blog_posts(:draft_one))
    assert_equal "published", blog_posts(:draft_one).reload.status
    assert_not_nil blog_posts(:draft_one).published_at
  end

  test "unpublish sets draft status" do
    sign_in_as_admin(@admin_user)

    post unpublish_admin_blog_post_path(@blog_post)

    assert_redirected_to admin_blog_post_path(@blog_post)
    assert_equal "draft", @blog_post.reload.status
  end
end
