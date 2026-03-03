SitemapGenerator::Sitemap.default_host = ENV.fetch("APP_BASE_URL", "https://pactbadger.com")

SitemapGenerator::Sitemap.create do
  add root_path, changefreq: "weekly", priority: 1.0
  add pricing_path, changefreq: "weekly", priority: 0.9
  add blog_path, changefreq: "daily", priority: 0.9
  add privacy_path, changefreq: "monthly", priority: 0.5
  add terms_path, changefreq: "monthly", priority: 0.5

  BlogPost.published.find_each do |post|
    add blog_post_path(post.slug), lastmod: post.updated_at, changefreq: "weekly", priority: 0.8
  end
end
