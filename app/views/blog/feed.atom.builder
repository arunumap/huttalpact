atom_feed do |feed|
  feed.title("PactBadger Blog")
  feed.subtitle("Contract management insights and product updates")
  feed.updated(@blog_posts.first&.updated_at || Time.current)
  feed.id(blog_url)

  @blog_posts.each do |post|
    feed.entry(post, url: blog_post_url(post.slug)) do |entry|
      entry.title(post.title)
      entry.content(render_blog_markdown(post), type: "html")
      entry.author { |author| author.name(post.admin_user&.full_name || "PactBadger Team") }
      entry.updated(post.updated_at)
      entry.published(post.published_at || post.created_at)
      entry.summary(post.display_excerpt)
    end
  end
end
