class Admin::BlogPostsController < Admin::BaseController
  before_action :set_blog_post, only: %i[show edit update destroy publish unpublish]
  before_action :set_categories, only: %i[new create edit update]
  before_action :set_admin_users, only: %i[edit update]

  def index
    @status = params[:status].presence
    @category_id = params[:category_id].presence
    @query = params[:query].to_s.strip

    scope = BlogPost.includes(:admin_user, :blog_category).order(created_at: :desc)
    scope = scope.where(status: @status) if BlogPost::STATUSES.include?(@status)
    scope = scope.where(blog_category_id: @category_id) if @category_id.present?
    if @query.present?
      scope = scope.where("title ILIKE ?", "%#{BlogPost.sanitize_sql_like(@query)}%")
    end

    @pagy, @blog_posts = pagy(scope, limit: 25)
    @categories = BlogCategory.ordered
  end

  def show
  end

  def new
    @blog_post = BlogPost.new
  end

  def create
    @blog_post = Current.admin_user.blog_posts.new(blog_post_params)
    if @blog_post.save
      redirect_to admin_blog_post_path(@blog_post), notice: "Blog post created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @blog_post.update(blog_post_params)
      redirect_to admin_blog_post_path(@blog_post), notice: "Blog post updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @blog_post.destroy
    redirect_to admin_blog_posts_path, notice: "Blog post deleted."
  end

  def publish
    if @blog_post.update(status: "published", published_at: @blog_post.published_at || Time.current)
      redirect_to admin_blog_post_path(@blog_post), notice: "Blog post published."
    else
      redirect_to admin_blog_post_path(@blog_post), alert: @blog_post.errors.full_messages.to_sentence
    end
  end

  def unpublish
    @blog_post.update(status: "draft")
    redirect_to admin_blog_post_path(@blog_post), notice: "Blog post moved to draft."
  end

  private

  def set_blog_post
    @blog_post = BlogPost.find(params[:id])
  end

  def set_categories
    @categories = BlogCategory.ordered
  end

  def set_admin_users
    @admin_users = AdminUser.order(:first_name, :last_name, :email_address)
  end

  def blog_post_params
    params.require(:blog_post).permit(
      :admin_user_id,
      :title,
      :slug,
      :body,
      :excerpt,
      :meta_description,
      :canonical_url,
      :og_image_url,
      :status,
      :published_at,
      :blog_category_id,
      :featured_image
    )
  end
end
