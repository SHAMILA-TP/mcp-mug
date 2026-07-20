class CreateOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :orders do |t|
      t.references :mug, null: false, foreign_key: true
      t.integer :quantity
      t.string :customer_identifier

      t.timestamps
    end
  end
end
