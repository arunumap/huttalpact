class Admin::AiExtractionConfigsController < Admin::BaseController
  before_action :set_config, only: %i[show activate]

  def index
    @configs_by_type = AiExtractionConfig::EXTRACTION_TYPES.index_with do |type|
      AiExtractionConfig.for_type(type).order(version: :desc).to_a
    end
    @active_configs = AiExtractionConfig.active.index_by(&:extraction_type)
  end

  def show
    @previous_version = AiExtractionConfig
      .for_type(@config.extraction_type)
      .where("version < ?", @config.version)
      .order(version: :desc)
      .first
  end

  def new
    type = params[:extraction_type]
    unless AiExtractionConfig::EXTRACTION_TYPES.include?(type)
      redirect_to admin_ai_extraction_configs_path, alert: "Invalid extraction type"
      return
    end

    source = AiExtractionConfig.active_for(type)
    @config = AiExtractionConfig.new(
      extraction_type: type,
      ai_model: source.ai_model,
      max_tokens: source.max_tokens,
      temperature: source.temperature,
      top_p: source.top_p,
      top_k: source.top_k,
      input_cost_per_million: source.input_cost_per_million,
      output_cost_per_million: source.output_cost_per_million,
      request_timeout: source.request_timeout
    )
  end

  def create
    @config = AiExtractionConfig.new(config_params)
    @config.created_by = Current.admin_user

    activate_now = params[:activate] == "1"

    if @config.save
      @config.activate! if activate_now
      redirect_to admin_ai_extraction_config_path(@config),
                  notice: "Config v#{@config.version} created#{activate_now ? ' and activated' : ''}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def activate
    @config.activate!
    redirect_to admin_ai_extraction_configs_path,
                notice: "#{@config.type_label} v#{@config.version} is now active."
  end

  private

  def set_config
    @config = AiExtractionConfig.find(params[:id])
  end

  def config_params
    params.require(:ai_extraction_config).permit(
      :extraction_type, :ai_model, :max_tokens,
      :temperature, :top_p, :top_k,
      :input_cost_per_million, :output_cost_per_million,
      :request_timeout, :notes
    )
  end
end
