module BlogHelper
  ALLOWED_MARKDOWN_TAGS = %w[
    p br hr h1 h2 h3 h4 h5 h6 strong em a blockquote ul ol li pre code
    table thead tbody tr th td img
  ].freeze

  ALLOWED_MARKDOWN_ATTRIBUTES = %w[href target rel src alt title class].freeze

  def render_blog_markdown(post)
    sanitize(
      post.rendered_body,
      tags: ALLOWED_MARKDOWN_TAGS,
      attributes: ALLOWED_MARKDOWN_ATTRIBUTES
    )
  end

  def blog_post_og_image(post)
    return post.og_image_url if post.og_image_url.present?
    return url_for(post.featured_image) if post.featured_image.attached?

    image_url(SeoHelper::DEFAULT_OG_IMAGE)
  rescue StandardError
    ""
  end
end
