class AiUsageLog < ApplicationRecord
  MODEL_INPUT_COST_PER_MILLION = 3.0
  MODEL_OUTPUT_COST_PER_MILLION = 15.0

  belongs_to :organization
  belongs_to :contract, optional: true

  validates :ai_model, presence: true
  validates :input_tokens, :output_tokens, :total_tokens, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :duration_ms, numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true
  validates :extraction_mode, inclusion: { in: %w[full incremental] }

  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }
  scope :by_org, ->(organization_id) { where(organization_id:) }
  scope :by_model, ->(ai_model) { where(ai_model:) }
  scope :since, ->(time) { where(created_at: time..) }
  scope :in_period, ->(start_time, end_time) { where(created_at: start_time..end_time) }

  before_validation :compute_total_tokens

  def self.daily_totals(days: 30)
    since(days.days.ago)
      .group("DATE(created_at)")
      .select(
        "DATE(created_at) AS usage_date",
        "COUNT(*) AS extraction_count",
        "SUM(input_tokens) AS input_tokens_sum",
        "SUM(output_tokens) AS output_tokens_sum",
        "SUM(total_tokens) AS total_tokens_sum"
      )
      .order("usage_date DESC")
  end

  def self.total_cost(scope = all)
    input_tokens = scope.sum(:input_tokens)
    output_tokens = scope.sum(:output_tokens)

    ((input_tokens / 1_000_000.0) * MODEL_INPUT_COST_PER_MILLION) +
      ((output_tokens / 1_000_000.0) * MODEL_OUTPUT_COST_PER_MILLION)
  end

  private

  def compute_total_tokens
    self.input_tokens ||= 0
    self.output_tokens ||= 0
    self.total_tokens = input_tokens + output_tokens
  end
end
