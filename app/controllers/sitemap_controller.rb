# frozen_string_literal: true

class SitemapController < ApplicationController
  skip_before_action :require_authentication

  def index
    @static_pages = [
      { url: root_url, changefreq: "weekly", priority: "1.0" },
      { url: solutions_url, changefreq: "monthly", priority: "0.8" },
      { url: pricing_url, changefreq: "monthly", priority: "0.8" },
      { url: blog_url, changefreq: "weekly", priority: "0.7" },
      { url: privacy_url, changefreq: "yearly", priority: "0.3" },
      { url: url_for(controller: "pages", action: "terms", only_path: false), changefreq: "yearly", priority: "0.3" }
    ]
    @solution_pages = SolutionCatalog.public_solutions

    @blog_posts = BlogPost.published.order(published_at: :desc).select(:slug, :updated_at)

    respond_to do |format|
      format.xml
    end
  end
end
