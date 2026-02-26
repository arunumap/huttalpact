class Admin::StorageController < Admin::BaseController
  def show
    @blob_count = ActiveStorage::Blob.count
    @total_bytes = ActiveStorage::Blob.sum(:byte_size)
    @largest_blobs = ActiveStorage::Blob.order(byte_size: :desc).limit(20)
    @by_content_type = ActiveStorage::Blob.group(:content_type).sum(:byte_size)
    @orphaned_blob_count = ActiveStorage::Blob.left_joins(:attachments).where(active_storage_attachments: { id: nil }).count
  end
end
