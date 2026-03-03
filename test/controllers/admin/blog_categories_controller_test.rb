require "test_helper"

class Admin::BlogCategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin_user = admin_users(:one)
    @category = blog_categories(:guides)
  end

  test "requires admin authentication" do
    get admin_blog_categories_path
    assert_redirected_to new_admin_session_path
  end

  test "index renders for admin" do
    sign_in_as_admin(@admin_user)

    get admin_blog_categories_path

    assert_response :success
    assert_match @category.name, response.body
  end

  test "create category" do
    sign_in_as_admin(@admin_user)

    assert_difference "BlogCategory.count", 1 do
      post admin_blog_categories_path, params: {
        blog_category: {
          name: "Compliance",
          position: 3
        }
      }
    end

    assert_redirected_to admin_blog_categories_path
  end

  test "destroy prevented when category has posts" do
    sign_in_as_admin(@admin_user)

    assert_no_difference "BlogCategory.count" do
      delete admin_blog_category_path(@category)
    end

    assert_redirected_to admin_blog_categories_path
  end

  test "destroy reassigns posts when target provided" do
    sign_in_as_admin(@admin_user)
    target = blog_categories(:product_updates)

    assert_difference "BlogCategory.count", -1 do
      delete admin_blog_category_path(@category), params: { reassign_to_id: target.id }
    end

    assert_redirected_to admin_blog_categories_path
    assert_equal target.id, blog_posts(:published_one).reload.blog_category_id
  end
end
