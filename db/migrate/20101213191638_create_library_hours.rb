class CreateLibraryHours < ActiveRecord::Migration[5.1]
  def self.up
    create_table :library_hours do |t|
      t.integer :library_id, null: false
      t.date :date, null: false
      t.datetime :opens
      t.datetime :closes
      t.text :note

      t.timestamps null: true
    end

    add_index :library_hours, [:library_id, :date]
  end

  def self.down
    drop_table :library_hours
  end
end
