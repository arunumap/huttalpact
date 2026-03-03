require "test_helper"

class MarkdownRendererServiceTest < ActiveSupport::TestCase
  test "renders headings and links" do
    html = MarkdownRendererService.call("## Title\n\nVisit https://example.com")

    assert_match(/<h2>Title<\/h2>/, html)
    assert_match(/<a href=\"https:\/\/example.com\"/, html)
  end

  test "renders fenced code blocks" do
    html = MarkdownRendererService.call("```ruby\nputs 'hi'\n```")

    assert_match(/<pre><code class=\"language-ruby\">/, html)
    assert_match(/puts 'hi'/, html)
  end

  test "renders tables" do
    markdown = <<~MD
      | Name | Value |
      | ---- | ----- |
      | A    | B     |
    MD

    html = MarkdownRendererService.call(markdown)

    assert_match(/<table>/, html)
    assert_match(/<th>Name<\/th>/, html)
    assert_match(/<td>B<\/td>/, html)
  end

  test "renders footnotes" do
    markdown = "A note.[^1]\n\n[^1]: Footnote text"

    html = MarkdownRendererService.call(markdown)

    assert_match(/Footnote text/, html)
    assert_match(/<sup/, html)
  end

  test "filters raw html" do
    html = MarkdownRendererService.call("<script>alert('x')</script>Safe")

    assert_no_match(/<script>/, html)
    assert_match(/Safe/, html)
  end
end
