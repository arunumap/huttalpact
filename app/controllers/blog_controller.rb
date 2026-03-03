class BlogController < ApplicationController
  include Pagy::Backend

  allow_unauthenticated_access
  prepend_before_action :resume_session
  skip_before_action :redirect_to_onboarding
  before_action :set_categories, only: :index
  before_action :set_post, only: :show
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  layout "marketing"

  def index
    @selected_category = BlogCategory.find_by(slug: params[:category]) if params[:category].present?
    scope = BlogPost.for_index
    scope = scope.where(blog_category_id: @selected_category.id) if @selected_category
    @pagy, @blog_posts = pagy(scope, limit: 10)
  end

  def show
    @previous_post = @blog_post.previous_post
    @next_post = @blog_post.next_post
  end

  def feed
    @blog_posts = BlogPost.for_index.limit(25)
  end

  private

  def set_categories
    @categories = BlogCategory.ordered
  end

  def set_post
    @blog_post = BlogPost.includes(:admin_user, :blog_category).published.find_by!(slug: params[:slug])
  end

  def render_not_found
    render file: Rails.public_path.join("404.html"), layout: false, status: :not_found
  end
end
