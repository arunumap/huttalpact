# frozen_string_literal: true

require "test_helper"

class SeoHelperTest < ActionView::TestCase
  include SeoHelper

  # Stub request object for helpers that need it
  def request
    @request ||= OpenStruct.new(original_url: "https://huttalpact.com/test?page=1")
  end

  # Stub image_url for tests
  def image_url(source)
    "https://huttalpact.com/assets/#{source}"
  end

  # Stub root_url for tests
  def root_url
    "https://huttalpact.com/"
  end

  test "seo_meta_tags includes description" do
    result = seo_meta_tags
    assert_match(/name="description"/, result)
    assert_match(/AI-powered contract tracking/, result)
  end

  test "seo_meta_tags includes robots directive" do
    result = seo_meta_tags
    assert_match(/name="robots"/, result)
    assert_match(/index, follow/, result)
  end

  test "seo_meta_tags includes canonical link" do
    result = seo_meta_tags
    assert_match(/rel="canonical"/, result)
  end

  test "seo_meta_tags strips query params from canonical" do
    content_for(:canonical_url, "https://huttalpact.com/pricing")
    result = seo_meta_tags
    assert_match(/huttalpact\.com\/pricing/, result)
  end

  test "seo_meta_tags includes Open Graph tags" do
    result = seo_meta_tags
    assert_match(/property="og:site_name"/, result)
    assert_match(/property="og:title"/, result)
    assert_match(/property="og:description"/, result)
    assert_match(/property="og:type"/, result)
    assert_match(/property="og:url"/, result)
    assert_match(/property="og:image"/, result)
  end

  test "seo_meta_tags includes Twitter card tags" do
    result = seo_meta_tags
    assert_match(/name="twitter:card"/, result)
    assert_match(/summary_large_image/, result)
    assert_match(/name="twitter:title"/, result)
    assert_match(/name="twitter:description"/, result)
  end

  test "seo_meta_tags uses custom description from content_for" do
    content_for(:meta_description, "Custom SEO description")
    result = seo_meta_tags
    assert_match(/Custom SEO description/, result)
  end

  test "seo_meta_tags uses custom robots from content_for" do
    content_for(:meta_robots, "noindex, nofollow")
    result = seo_meta_tags
    assert_match(/noindex, nofollow/, result)
  end

  test "structured_data organization returns valid JSON-LD" do
    result = structured_data(type: :organization)
    assert_match(/application\/ld\+json/, result)
    assert_match(/"@type":"Organization"/, result)
    assert_match(/"name":"HuttalPact"/, result)
  end

  test "structured_data software_application includes pricing offers" do
    result = structured_data(type: :software_application)
    assert_match(/"@type":"SoftwareApplication"/, result)
    assert_match(/"applicationCategory":"BusinessApplication"/, result)
    assert_match(/"price":"0"/, result)
    assert_match(/"price":"49"/, result)
    assert_match(/"price":"149"/, result)
  end

  test "structured_data faq renders FAQ schema" do
    items = [
      { question: "What is HuttalPact?", answer: "A contract tracker." },
      { question: "Is there a free plan?", answer: "Yes." }
    ]
    result = structured_data(type: :faq, items: items)
    assert_match(/"@type":"FAQPage"/, result)
    assert_match(/"What is HuttalPact\?"/, result)
    assert_match(/"A contract tracker."/, result)
  end

  test "structured_data faq returns nil for empty items" do
    result = structured_data(type: :faq, items: [])
    assert_nil result
  end

  test "structured_data breadcrumb renders breadcrumb schema" do
    items = [
      { name: "Home", url: "https://huttalpact.com/" },
      { name: "Pricing", url: "https://huttalpact.com/pricing" }
    ]
    result = structured_data(type: :breadcrumb, items: items)
    assert_match(/"@type":"BreadcrumbList"/, result)
    assert_match(/"position":1/, result)
    assert_match(/"name":"Pricing"/, result)
  end
end
