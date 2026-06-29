require 'active_record'

# connect
ActiveRecord::Base.establish_connection(
  adapter:  'sqlite3',
  database: ':memory:'
)

# create tables
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define(version: 1) do
  create_table :teams do |t|
    t.string :name
  end

  create_table :users do |t|
    t.integer :bits, default: 0, null: false
    t.integer :more_bits, default: 0, null: false
    t.integer :team_id
  end
end
