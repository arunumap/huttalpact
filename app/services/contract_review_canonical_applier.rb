class ContractReviewCanonicalApplier
  def initialize(review)
    @review = review
    @contract = review.contract
    @resolver = ContractReviewValueResolver.new(@contract)
  end

  def call
    data = @resolver.snapshot.deep_dup

    reviewed_direct_fields.each do |field|
      @resolver.assign_value(data:, field_key: field.field_key, value: field.approved_value, field_index: field.field_index)
    end

    ActiveRecord::Base.transaction do
      apply_contract_attributes!(data)
      apply_lease_detail!(data["lease_details"])
      sync_rent_escalations!(Array(data["rent_escalations"]))
      sync_lease_options!(Array(data["lease_options"]))
      sync_lease_milestones!(Array(data["lease_milestones"]))
    end
  end

  private

  def reviewed_direct_fields
    ContractReviewField.unscoped
      .where(contract_review_id: @review.id, source_type: "direct")
      .where.not(review_status: "pending")
      .order(:field_key, :field_index)
  end

  def apply_contract_attributes!(data)
    @contract.update!(
      title: data["title"],
      vendor_name: data["vendor_name"],
      premises_address: data["premises_address"],
      contract_type: data["contract_type"],
      direction: data["direction"],
      start_date: data["start_date"],
      end_date: data["end_date"],
      next_renewal_date: data["next_renewal_date"],
      monthly_value: data["monthly_value"],
      total_value: data["total_value"],
      auto_renews: data["auto_renews"],
      renewal_term: data["renewal_term"],
      notice_period_days: data["notice_period_days"],
      ai_summary: data["summary"]
    )
  end

  def apply_lease_detail!(attributes)
    return if attributes.blank? && @contract.lease_detail.blank?

    detail = @contract.lease_detail || @contract.build_lease_detail
    detail.assign_attributes(attributes.to_h.symbolize_keys)
    detail.save!
  end

  def sync_rent_escalations!(rows)
    sync_collection!(
      association: @contract.rent_escalations.order(:position, :created_at),
      rows:,
      extra_attributes: ->(index) { { position: index } }
    )
  end

  def sync_lease_options!(rows)
    sync_collection!(
      association: @contract.lease_options.order(:position, :created_at),
      rows:,
      extra_attributes: ->(index) { { position: index } }
    )
  end

  def sync_lease_milestones!(rows)
    sync_collection!(
      association: @contract.lease_milestones.order(:created_at),
      rows:,
      extra_attributes: ->(_index) { { organization: @contract.organization } }
    )
  end

  def sync_collection!(association:, rows:, extra_attributes:)
    existing_records = association.to_a

    rows.each_with_index do |attributes, index|
      record = existing_records[index] || association.klass.new(contract: @contract)
      record.assign_attributes(attributes.to_h.symbolize_keys.merge(extra_attributes.call(index)))
      record.save!
    end

    existing_records.drop(rows.length).each(&:destroy!)
  end
end
