class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Use UUID as default primary key for all models
  self.implicit_order_column = "created_at"
end
