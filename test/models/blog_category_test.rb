require "test_helper"

class BlogCategoryTest < ActiveSupport::TestCase
  test "valid fixture is valid" do
    assert blog_categories(:guides).valid?
  end

  test "generates slug from name" do
    category = BlogCategory.create!(name: "Contract Tips")
    assert_equal "contract-tips", category.slug
  end

  test "ordered scope sorts by position then name" do
    a = BlogCategory.create!(name: "B Category", position: 2)
    b = BlogCategory.create!(name: "A Category", position: 2)
    c = BlogCategory.create!(name: "C Category", position: 1)

    assert_equal [ c, b, a ], BlogCategory.ordered.where(id: [ a.id, b.id, c.id ]).to_a
  end
end
