class CreateMugs < ActiveRecord::Migration[8.0]
  def change
    create_table :mugs do |t|
      t.string :size
      t.integer :price_cents
      t.integer :stock

      t.timestamps
    end
  end
end
