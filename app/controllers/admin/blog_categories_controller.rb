class Admin::BlogCategoriesController < Admin::BaseController
  before_action :set_blog_category, only: %i[edit update destroy]

  def index
    @categories = BlogCategory.ordered
    @blog_category = BlogCategory.new
  end

  def new
    @blog_category = BlogCategory.new
  end

  def create
    @blog_category = BlogCategory.new(blog_category_params)
    if @blog_category.save
      redirect_to admin_blog_categories_path, notice: "Category created."
    else
      @categories = BlogCategory.ordered
      render :index, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @blog_category.update(blog_category_params)
      redirect_to admin_blog_categories_path, notice: "Category updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @blog_category.blog_posts.exists?
      reassign_to = BlogCategory.find_by(id: params[:reassign_to_id])

      if reassign_to.present? && reassign_to != @blog_category
        BlogPost.transaction do
          @blog_category.blog_posts.update_all(blog_category_id: reassign_to.id)
          @blog_category.destroy!
        end

        redirect_to admin_blog_categories_path, notice: "Category deleted and posts reassigned."
        return
      end

      redirect_to admin_blog_categories_path, alert: "Cannot delete category with existing blog posts."
      return
    end

    @blog_category.destroy
    redirect_to admin_blog_categories_path, notice: "Category deleted."
  end

  private

  def set_blog_category
    @blog_category = BlogCategory.find(params[:id])
  end

  def blog_category_params
    params.require(:blog_category).permit(:name, :slug, :description, :position)
  end
end
