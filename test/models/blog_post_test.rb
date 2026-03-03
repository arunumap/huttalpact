require "test_helper"

class BlogPostTest < ActiveSupport::TestCase
  test "valid fixture is valid" do
    assert blog_posts(:published_one).valid?
  end

  test "published scope excludes drafts" do
    assert_includes BlogPost.published, blog_posts(:published_one)
    assert_not_includes BlogPost.published, blog_posts(:draft_one)
  end

  test "draft and archived scopes" do
    assert_includes BlogPost.draft, blog_posts(:draft_one)
    assert_not_includes BlogPost.draft, blog_posts(:published_one)

    assert_includes BlogPost.archived, blog_posts(:archived_one)
    assert_not_includes BlogPost.archived, blog_posts(:published_one)
  end

  test "recent scope orders newest first" do
    posts = BlogPost.where(id: [ blog_posts(:published_one).id, blog_posts(:published_two).id ]).recent.to_a
    assert_equal [ blog_posts(:published_two), blog_posts(:published_one) ], posts
  end

  test "in_category scope filters by slug" do
    result = BlogPost.in_category(blog_categories(:guides).slug)

    assert_includes result, blog_posts(:published_one)
    assert_not_includes result, blog_posts(:published_two)
  end

  test "sets published_at when status is published" do
    post = BlogPost.create!(
      title: "New published post",
      body: "Hello world",
      status: "published",
      admin_user: admin_users(:one)
    )

    assert_not_nil post.published_at
  end

  test "requires admin user" do
    post = BlogPost.new(title: "No author", body: "Body", status: "draft")

    assert_not post.valid?
    assert_includes post.errors[:admin_user], "must exist"
  end

  test "generates slug from title" do
    post = BlogPost.create!(
      title: "My New Post",
      body: "Body",
      status: "draft",
      admin_user: admin_users(:one)
    )

    assert_equal "my-new-post", post.slug
  end

  test "renders markdown body" do
    post = BlogPost.new(title: "MD", body: "## Hello", status: "draft", admin_user: admin_users(:one))

    assert_match "<h2>Hello</h2>", post.rendered_body
  end

  test "reading_time is at least one" do
    post = BlogPost.new(title: "Short", body: "Short body", status: "draft")
    assert_equal 1, post.reading_time
  end

  test "display_excerpt falls back to body" do
    post = BlogPost.new(title: "Fallback", body: "# Heading\n\nBody content", status: "draft")
    assert_match(/Heading Body content/, post.display_excerpt)
  end
end
