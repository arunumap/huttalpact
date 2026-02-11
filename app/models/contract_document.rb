class ContractDocument < ApplicationRecord
  belongs_to :contract
  has_many :key_clauses, foreign_key: :source_document_id, dependent: :destroy

  has_one_attached :file

  validates :file, presence: true

  EXTRACTION_STATUSES = %w[pending processing completed failed].freeze
  DOCUMENT_TYPES = %w[main_contract addendum amendment exhibit sow other].freeze
  MAX_FILE_SIZE = 25.megabytes
  ALLOWED_CONTENT_TYPES = %w[
    application/pdf
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    text/plain
  ].freeze

  validates :extraction_status, inclusion: { in: EXTRACTION_STATUSES }
  validates :document_type, inclusion: { in: DOCUMENT_TYPES }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :acceptable_file_type
  validate :acceptable_file_size

  scope :pending, -> { where(extraction_status: "pending") }
  scope :completed, -> { where(extraction_status: "completed") }
  scope :failed, -> { where(extraction_status: "failed") }
  scope :ordered, -> { order(position: :asc, created_at: :asc) }

  after_create_commit :enqueue_extraction
  after_destroy :trigger_re_extraction_or_cleanup

  def filename
    file.attached? ? file.filename.to_s : "Unknown"
  end

  def content_type
    file.attached? ? file.content_type : nil
  end

  def file_size
    file.attached? ? file.byte_size : 0
  end

  def file_size_human
    number = file_size.to_f
    units = %w[B KB MB GB]
    unit_index = 0
    while number >= 1024 && unit_index < units.length - 1
      number /= 1024
      unit_index += 1
    end
    "#{number.round(1)} #{units[unit_index]}"
  end

  def pdf?
    content_type == "application/pdf"
  end

  def docx?
    content_type&.include?("wordprocessingml")
  end

  def text?
    content_type&.start_with?("text/")
  end

  def pending?
    extraction_status == "pending"
  end

  def processing?
    extraction_status == "processing"
  end

  def completed?
    extraction_status == "completed"
  end

  def failed?
    extraction_status == "failed"
  end

  def extraction_status_label
    extraction_status.titleize
  end

  def document_type_label
    document_type.titleize.gsub("_", " ")
  end

  private

  def enqueue_extraction
    ExtractContractDocumentJob.perform_later(id)
  end

  def trigger_re_extraction_or_cleanup
    remaining = contract.contract_documents.where.not(id: id)

    if remaining.completed.any?
      # Re-extract from remaining documents (full mode — no new_document_id)
      contract.update!(extraction_status: "pending")
      AiExtractContractJob.perform_later(contract.id)
    elsif remaining.none?
      # No documents left — clear AI data
      contract.update!(
        extraction_status: "pending",
        ai_extracted_data: nil,
        last_changes_summary: nil
      )
    end
  end

  def acceptable_file_type
    return unless file.attached?

    unless ALLOWED_CONTENT_TYPES.include?(file.content_type)
      errors.add(:file, "must be a PDF, DOCX, or plain text file (got #{file.content_type})")
    end
  end

  def acceptable_file_size
    return unless file.attached?

    if file.byte_size > MAX_FILE_SIZE
      errors.add(:file, "is too large (#{(file.byte_size / 1.megabyte.to_f).round(1)} MB). Maximum size is #{MAX_FILE_SIZE / 1.megabyte} MB")
    end
  end
end
