require "csv"

class ContractsController < ApplicationController
  include Pagy::Backend

  before_action :set_contract, only: %i[edit update destroy]
  before_action :capture_contract_title, only: %i[destroy]
  before_action :enforce_contract_limit!, only: %i[new create]

  def index
    contracts = Contract.not_draft.order(created_at: :desc)
    contracts = contracts.search(params[:search]) if params[:search].present?
    contracts = contracts.by_status(params[:status]) if params[:status].present?
    contracts = contracts.by_type(params[:contract_type]) if params[:contract_type].present?
    contracts = contracts.by_direction(params[:direction]) if params[:direction].present?

    respond_to do |format|
      format.html do
        @pagy, @contracts = pagy(contracts)
        @drafts = Contract.draft.order(updated_at: :desc)
      end
      format.csv do
        @contracts = contracts
        log_audit("exported", details: "Exported #{@contracts.count} contracts to CSV")
        send_data generate_csv(@contracts), filename: "contracts-#{Date.current}.csv", type: "text/csv"
      end
    end
  end

  def show
    @contract = Contract.includes(:contract_documents, :key_clauses).find(params[:id])
    @audit_logs = @contract.audit_logs.includes(:user).recent.limit(10)
    log_audit("viewed", contract: @contract)
  end

  def new
    @contract = Contract.new
  end

  def create
    @contract = Contract.new(contract_params)
    @contract.uploaded_by = Current.user

    if @contract.save
      # Attach uploaded documents if provided (supports multiple files)
      uploaded_files = Array(params[:contract_documents]).compact_blank
      # Also support legacy single-file param
      uploaded_files << params[:contract_document] if params[:contract_document].present? && uploaded_files.empty?

      uploaded_files.each do |file|
        @contract.contract_documents.create!(file: file)
        # Text extraction + AI extraction will be chained automatically via after_create_commit
      end

      GenerateContractAlertsJob.perform_later(@contract.id)
      log_audit("created", contract: @contract, details: "Created contract: #{@contract.title}")
      redirect_to @contract, notice: "Contract was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def create_draft
    uploaded_files = Array(params[:contract_documents]).compact_blank

    if uploaded_files.empty?
      redirect_to new_contract_path, alert: "Please upload at least one document."
      return
    end

    @contract = ContractDraftCreatorService.new(
      user: Current.user,
      organization: current_organization,
      files: uploaded_files
    ).call

    log_audit("created", contract: @contract, details: "Created draft contract for AI extraction")
    redirect_to edit_contract_path(@contract), notice: "Uploading and extracting contract details..."
  rescue ArgumentError, ActiveRecord::RecordInvalid
    redirect_to new_contract_path, alert: "Could not create draft contract."
  end

  def update
    was_draft = @contract.draft?

    # When finalizing a draft, enforce contract limit
    if was_draft && contract_params[:status] != "draft"
      if current_organization&.at_contract_limit?
        @contract.errors.add(:base, "Contract limit reached. Please upgrade your plan.")
        render :edit, status: :unprocessable_entity
        return
      end
    end

    if @contract.update(contract_params)
      if was_draft
        GenerateContractAlertsJob.perform_later(@contract.id)
        log_audit("updated", contract: @contract, details: "Finalized draft contract: #{@contract.title}")
        redirect_to @contract, notice: "Contract was successfully created."
      else
        if date_fields_changed?
          GenerateContractAlertsJob.perform_later(@contract.id)
        end
        log_audit("updated", contract: @contract, details: "Updated fields: #{@contract.previous_changes.keys.join(', ')}")
        redirect_to @contract, notice: "Contract was successfully updated."
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    log_audit("deleted", contract: @contract, details: "Deleted contract: #{@saved_contract_title}")
    @contract.destroy!
    redirect_to contracts_path, notice: "Contract was successfully deleted.", status: :see_other
  end

  def bulk_archive
    ids = Array(params[:ids]).compact_blank
    if ids.empty?
      redirect_to contracts_path, alert: "No contracts selected."
      return
    end

    contracts = Contract.where(id: ids).where.not(status: "archived")
    count = contracts.count

    if count.zero?
      redirect_to contracts_path, notice: "Selected contracts are already archived."
      return
    end

    contract_ids = contracts.pluck(:id)
    contracts.update_all(status: "archived")

    # Cancel any pending alerts for archived contracts
    Alert.where(contract_id: contract_ids, status: "pending").update_all(status: "cancelled")

    Contract.where(id: contract_ids).each do |c|
      log_audit("updated", contract: c, details: "Archived via bulk action")
    end
    redirect_to contracts_path, notice: "#{count} #{'contract'.pluralize(count)} archived."
  end

  def bulk_export
    ids = Array(params[:ids]).compact_blank
    if ids.empty?
      redirect_to contracts_path, alert: "No contracts selected."
      return
    end

    contracts = Contract.where(id: ids).order(created_at: :desc)
    log_audit("exported", details: "Bulk exported #{contracts.count} contracts to CSV")
    send_data generate_csv(contracts), filename: "contracts-#{Date.current}.csv", type: "text/csv"
  end

  private

  def set_contract
    @contract = Contract.find(params[:id])
  end

  def contract_params
    params.require(:contract).permit(
      :title, :vendor_name, :status, :contract_type, :direction,
      :start_date, :end_date, :next_renewal_date, :notice_period_days,
      :monthly_value, :total_value, :auto_renews, :renewal_term, :notes
    )
  end

  def date_fields_changed?
    (@contract.previous_changes.keys & %w[end_date next_renewal_date notice_period_days status]).any?
  end

  def capture_contract_title
    @saved_contract_title = @contract.title
  end

  def generate_csv(contracts)
    CSV.generate(headers: true) do |csv|
      csv << %w[Title Vendor Status Type Direction Start\ Date End\ Date Notice\ Period\ Days Monthly\ Value Total\ Value Auto\ Renews Renewal\ Term Notes]
      contracts.each do |c|
        csv << [
          c.title,
          c.vendor_name,
          c.status&.titleize,
          c.contract_type&.titleize&.gsub("_", " "),
          c.direction&.titleize,
          c.start_date,
          c.end_date,
          c.notice_period_days,
          c.monthly_value,
          c.total_value,
          c.auto_renews ? "Yes" : "No",
          c.renewal_term,
          c.notes
        ]
      end
    end
  end
end
