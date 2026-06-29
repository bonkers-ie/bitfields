require 'spec_helper'

class User < ActiveRecord::Base
  include Bitfields

  bitfield :bits, 1 => :vendor, 2 => :zany, 4 => :interesting
end

class UserWithBitfieldOptions < ActiveRecord::Base
  include Bitfields

  bitfield :bits, 1 => :vendor, 2 => :zany, 4 => :interesting, :scopes => false
end

class UserWithInstanceOptions < ActiveRecord::Base
  self.table_name = 'users'
  include Bitfields

  bitfield :bits, 1 => :vendor, 2 => :zany, 4 => :interesting, :added_instance_methods => false
end

class MultiBitUser < ActiveRecord::Base
  self.table_name = 'users'
  include Bitfields

  bitfield :bits, 1 => :vendor, 2 => :zany, 4 => :interesting
  bitfield :more_bits, 1 => :one, 2 => :two, 4 => :four
end

class UserWithoutScopes < ActiveRecord::Base
  self.table_name = 'users'
  include Bitfields

  bitfield :bits, 1 => :vendor, 2 => :zany, 4 => :interesting, :scopes => false
end

class UserWithoutSetBitfield < ActiveRecord::Base
  self.table_name = 'users'
  include Bitfields
end

class InheritedUser < User
end

class GrandchildInheritedUser < InheritedUser
end

# other children should not disturb the inheritance
class OtherInheritedUser < UserWithoutSetBitfield
  self.table_name = 'users'
  bitfield :bits, 1 => :vendor_inherited
end

class InheritedUserWithoutSetBitfield < UserWithoutSetBitfield
end

class OverwrittenUser < User
  bitfield :bits, 1 => :vendor_inherited
end

class BitOperatorMode < ActiveRecord::Base
  self.table_name = 'users'
  include Bitfields

  bitfield :bits, 1 => :vendor, 2 => :zany, :query_mode => :bit_operator
end

class WithoutThePowerOfTwo < ActiveRecord::Base
  self.table_name = 'users'
  include Bitfields

  bitfield :bits, :vendor, :zany, :interesting, query_mode: :bit_operator
end

class WithoutThePowerOfTwoWithoutOptions < ActiveRecord::Base
  self.table_name = 'users'
  include Bitfields

  bitfield :bits, :vendor, :zany
end

class CheckRaise < ActiveRecord::Base
  self.table_name = 'users'
  include Bitfields
end

class ManyBitsUser < User
  self.table_name = 'users'
end

class Team < ActiveRecord::Base
  has_many :members, class_name: 'User'
end

class UserWithExplicitBits < ActiveRecord::Base
  self.table_name = 'users'
  include Bitfields

  bitfield :bits, 1 => :vendor, 2 => :zany, 4 => :interesting
  belongs_to :team, optional: true
end

describe Bitfields do
  before do
    User.delete_all
  end

  describe :bitfields do
    it 'parses them correctly' do
      expect(User.bitfields).to eq({ bits: { vendor: 1, zany: 2, interesting: 4 } })
    end

    it 'is fast for huge number of bits' do
      bits = {}
      0.upto(20) do |bit|
        bits[2**bit] = "my_bit_#{bit}"
      end

      expect do
        Timeout.timeout(0.2) do
          ManyBitsUser.class_eval { bitfield :bits, bits }
        end
      end.not_to raise_error
    end
  end

  describe :bitfield_options do
    it 'parses them correctly when not set' do
      expect(User.bitfield_options).to eq({ bits: {} })
    end

    it 'parses them correctly when set' do
      expect(UserWithBitfieldOptions.bitfield_options).to eq({ bits: { scopes: false } })
      expect(UserWithInstanceOptions.bitfield_options).to eq({ bits: { added_instance_methods: false } })
    end
  end

  describe :bitfield_column do
    it 'raises a nice error when i use a unknown bitfield' do
      expect do
        User.bitfield_column(:xxx)
      end.to raise_error(RuntimeError, 'Unknown bitfield xxx')
    end
  end

  describe :bitfield_values do
    it 'contains all bits with values' do
      expect(User.new.bitfield_values(:bits)).to eq({ zany: false, interesting: false, vendor: false })
      expect(User.new(bits: 15).bitfield_values(:bits)).to eq({ zany: true, interesting: true, vendor: true })
    end
  end

  describe :bitfield_bits do
    it 'works on empty' do
      expect(User.bitfield_bits({})).to eq(0)
    end

    it 'adds multiple values' do
      expect(User.bitfield_bits(zany: true, interesting: true, vendor: true)).to eq(7)
    end

    it 'ignores false' do
      expect(User.bitfield_bits(zany: false, interesting: true, vendor: true)).to eq(5)
    end

    it 'fails on unknown bits' do
      expect { User.bitfield_bits(foo: true) }.to raise_error(KeyError)
    end
  end

  describe 'attribute accessors' do
    it 'has everything on false by default' do
      expect(User.new.vendor).to be(false)
      expect(User.new.vendor?).to be(false)
    end

    it 'is true when set to true' do
      expect(User.new(vendor: true).vendor).to be(true)
    end

    it 'is true when set to truthy' do
      expect(User.new(vendor: 1).vendor).to be(true)
    end

    it 'is false when set to false' do
      expect(User.new(vendor: false).vendor).to be(false)
    end

    it 'is false when set to falsy' do
      expect(User.new(vendor: 'false').vendor).to be(false)
    end

    it 'stays true when set to true twice' do
      u = User.new
      u.vendor = true
      u.vendor = true
      expect(u.vendor).to be(true)
      expect(u.bits).to eq(1)
    end

    it 'stays false when set to false twice' do
      u = User.new(bits: 3)
      u.vendor = false
      u.vendor = false
      expect(u.vendor).to be(false)
      expect(u.bits).to eq(2)
    end

    it 'changes the bits when setting to false' do
      user = User.new(bits: 7)
      user.vendor = false
      expect(user.bits).to eq(6)
    end

    it 'does not get negative when unsetting high bits' do
      user = User.new(vendor: true)
      user.interesting = false
      expect(user.bits).to eq(1)
    end

    it 'changes the bits when setting to true' do
      user = User.new(bits: 2)
      user.vendor = true
      expect(user.bits).to eq(3)
    end

    it 'does not get too high when setting high bits' do
      user = User.new(bits: 7)
      user.vendor = true
      expect(user.bits).to eq(7)
    end

    context 'when instantiating a new record' do
      it 'has _was' do
        user = User.new(vendor: true)
        expect(user.vendor_was).to be(false)
        user.save!
        expect(user.vendor_was).to be(true)
      end

      it 'has _changed?' do
        user = User.new(vendor: true)
        expect(user.vendor_changed?).to be(true)
        user.save!
        expect(user.vendor_changed?).to be(false)
      end

      it 'has _change' do
        user = User.new(vendor: true)
        expect(user.vendor_change).to eq([false, true])
        user.save!
        expect(user.vendor_change).to be_nil
        user.vendor = false
        expect(user.vendor_change).to eq([true, false])
      end

      it 'has _before_last_save' do
        user = User.new(vendor: true)
        expect(user.vendor_before_last_save).to be_nil
        user.save!
        expect(user.vendor_before_last_save).to be(false)
      end

      it 'has _change_to_be_saved' do
        user = User.new(vendor: true)
        expect(user.vendor_change_to_be_saved).to eq([false, true])
        user.save!
        expect(user.vendor_change_to_be_saved).to be_nil
      end

      it 'has _in_database' do
        user = User.new(vendor: true)
        expect(user.vendor_in_database).to be(false)
        user.save!
        expect(user.vendor_in_database).to be(true)
      end

      it 'has saved_change_to_' do
        user = User.new(vendor: true)
        expect(user.saved_change_to_vendor).to be_nil
        user.save!
        expect(user.saved_change_to_vendor).to eq([false, true])
      end

      it 'has saved_change_to_?' do
        user = User.new(vendor: true)
        expect(user.saved_change_to_vendor?).to be(false)
        user.save!
        expect(user.saved_change_to_vendor?).to be(true)
      end

      it 'has will_save_change_to_?' do
        user = User.new(vendor: true)
        expect(user.will_save_change_to_vendor?).to be(true)
        user.save!
        expect(user.will_save_change_to_vendor?).to be(false)
        user.vendor = false
        expect(user.will_save_change_to_vendor?).to be(true)
      end
    end

    context 'when creating a new model' do
      it 'has _was' do
        user = User.create!(vendor: true)
        user.vendor = false
        expect(user.vendor_was).to be(true)
        user.save!
        expect(user.vendor_was).to be(false)
      end

      it 'has _changed?' do
        user = User.create!(vendor: true)
        expect(user.vendor_changed?).to be(false)
        user.vendor = false
        expect(user.vendor_changed?).to be(true)
        user.save!
        expect(user.vendor_changed?).to be(false)
      end

      it 'has _change' do
        user = User.create!(vendor: true)
        expect(user.vendor_change).to be_nil
        user.vendor = false
        expect(user.vendor_change).to eq([true, false])
        user.save!
        expect(user.vendor_change).to be_nil
      end

      it 'has _before_last_save' do
        user = User.create!(vendor: true)
        expect(user.vendor_before_last_save).to be(false)
        user.vendor = false
        user.save!
        expect(user.vendor_before_last_save).to be(true)
      end

      it 'has _change_to_be_saved' do
        user = User.create!(vendor: true)
        expect(user.vendor_change_to_be_saved).to be_nil
        user.vendor = false
        expect(user.vendor_change_to_be_saved).to eq([true, false])
        user.save!
        expect(user.vendor_change_to_be_saved).to be_nil
      end

      it 'has _in_database' do
        user = User.create!(vendor: true)
        expect(user.vendor_in_database).to be(true)
        user.vendor = false
        user.save!
        expect(user.vendor_in_database).to be(false)
      end

      it 'has saved_change_to_' do
        user = User.create!(vendor: true)
        expect(user.saved_change_to_vendor).to eq([false, true])
      end

      it 'has saved_change_to_?' do
        user = User.create!(vendor: true)
        expect(user.saved_change_to_vendor?).to be(true)
      end

      it 'has will_save_change_to_?' do
        user = User.create!(vendor: true)
        expect(user.will_save_change_to_vendor?).to be(false)
        user.vendor = false
        expect(user.will_save_change_to_vendor?).to be(true)
        user.save!
        expect(user.will_save_change_to_vendor?).to be(false)
        user.vendor = true
        expect(user.will_save_change_to_vendor?).to be(true)
      end
    end

    context 'when loading a model from the database' do
      it 'has _was' do
        User.create!(vendor: true)
        user = User.last
        user.vendor
        user.vendor = false
        expect(user.vendor_was).to be(true)
        user.save!
        expect(user.vendor_was).to be(false)
      end

      it 'has _changed?' do
        User.create!(vendor: true)
        user = User.last
        expect(user.vendor_changed?).to be(false)
        user.vendor = false
        expect(user.vendor_changed?).to be(true)
        user.save!
        expect(user.vendor_changed?).to be(false)
      end

      it 'has _change' do
        User.create!(vendor: true)
        user = User.last
        expect(user.vendor_change).to be_nil
        user.vendor = false
        expect(user.vendor_change).to eq([true, false])
        user.save!
        expect(user.vendor_change).to be_nil
      end

      it 'has _before_last_save' do
        User.create!(vendor: true)
        user = User.last
        expect(user.vendor_before_last_save).to be_nil
        user.vendor = false
        user.save!
        expect(user.vendor_before_last_save).to be(true)
      end

      it 'has _change_to_be_saved' do
        User.create!(vendor: true)
        user = User.last
        expect(user.vendor_change_to_be_saved).to be_nil
        user.vendor = false
        expect(user.vendor_change_to_be_saved).to eq([true, false])
        user.save!
        expect(user.vendor_change_to_be_saved).to be_nil
      end

      it 'has _in_database' do
        User.create!(vendor: true)
        user = User.last
        expect(user.vendor_in_database).to be(true)
        user.vendor = false
        user.save!
        expect(user.vendor_in_database).to be(false)
      end

      it 'has saved_change_to_' do
        User.create!(vendor: true)
        user = User.last
        expect(user.saved_change_to_vendor).to be_nil
        user.vendor = false
        expect(user.saved_change_to_vendor).to be_nil
        user.save!
        expect(user.saved_change_to_vendor).to eq([true, false])
      end

      it 'has saved_change_to_?' do
        User.create!(vendor: true)
        user = User.last
        expect(user.saved_change_to_vendor?).to be(false)
        user.vendor = false
        expect(user.saved_change_to_vendor?).to be(false)
        user.save!
        expect(user.saved_change_to_vendor?).to be(true)
      end

      it 'has will_save_change_to_?' do
        User.create!(vendor: true)
        user = User.last
        expect(user.will_save_change_to_vendor?).to be(false)
        user.vendor = false
        expect(user.will_save_change_to_vendor?).to be(true)
        user.save!
        expect(user.will_save_change_to_vendor?).to be(false)
        user.vendor = true
        expect(user.will_save_change_to_vendor?).to be(true)
      end

      context 'when the model loaded from the database does not select the bitfield column' do
        it 'does not try to assign the bitfield attributes' do
          User.create!(vendor: true)

          expect do
            User.select(:id).last
          end.not_to raise_error
        end
      end
    end

    it 'has _became_true?' do
      user = User.new
      expect(user.vendor_became_true?).to be(false)
      user.vendor = true
      expect(user.vendor_became_true?).to be(true)
      user.save!
      expect(user.vendor_became_true?).to be(false)
      user.vendor = true
      expect(user.vendor_became_true?).to be(false)
    end

    it 'has _became_false?' do
      user = User.new
      expect(user.vendor_became_false?).to be(false)
      user.vendor = true
      expect(user.vendor_became_false?).to be(false)
      user.save!
      expect(user.vendor_became_false?).to be(false)
      user.vendor = false
      expect(user.vendor_became_false?).to be(true)
    end

    context 'when :added_instance_methods is false' do
      %i[
        vendor vendor? vendor= vendor_was vendor_changed? vendor_change vendor_became_true? vendor_became_false?
      ].each do |meth|
        it "does not generate the #{meth} method" do
          expect(UserWithInstanceOptions.new.respond_to?(meth)).to be(false)
        end
      end

      it 'does not define an after_find method' do
        expect(UserWithInstanceOptions.new.respond_to?(:after_find)).to be(false)
      end
    end

    it 'does still have the main bitfield method' do
      expect(UserWithInstanceOptions.new.bits).to eq 0
    end
  end

  describe '#bitfield_changes' do
    it 'has no changes by default' do
      expect(User.new.bitfield_changes).to eq({})
    end

    it 'records a change when setting' do
      u = User.new(vendor: true)
      expect(u.changes).to eq({ 'bits' => [0, 1] })
      expect(u.bitfield_changes).to eq({ 'vendor' => [false, true] })
    end
  end

  describe :bitfield_sql do
    it 'includes true states' do
      # 2, 1+2, 2+4, 1+2+4
      expect(User.bitfield_sql({ zany: true }, query_mode: :in_list)).to eq('users.bits IN (2,3,6,7)')
    end

    it 'includes invalid states' do
      expect(User.bitfield_sql({ zany: false }, query_mode: :in_list)).to eq('users.bits IN (0,1,4,5)') # 0, 1, 4, 4+1
    end

    it 'can combine multiple fields' do
      # 1+2, 1+2+4
      expect(User.bitfield_sql({ vendor: true, zany: true }, query_mode: :in_list)).to eq('users.bits IN (3,7)')
    end

    it 'can combine multiple fields with different values' do
      # 1, 1+4
      expect(User.bitfield_sql({ vendor: true, zany: false }, query_mode: :in_list)).to eq('users.bits IN (1,5)')
    end

    it 'combines multiple columns into one sql' do
      sql = MultiBitUser.bitfield_sql({ vendor: true, zany: false, one: true, four: true },
                                      query_mode: :in_list)
      expect(sql).to eq('users.bits IN (1,5) AND users.more_bits IN (5,7)') # 1, 1+4 AND 1+4, 1+2+4
    end

    it 'produces working sql' do
      MultiBitUser.create!(vendor: true, one: true)
      u2 = MultiBitUser.create!(vendor: true, one: false)
      MultiBitUser.create!(vendor: false, one: false)
      conditions = MultiBitUser.bitfield_sql({ vendor: true, one: false }, query_mode: :in_list)
      expect(MultiBitUser.where(conditions)).to eq([u2])
    end

    describe 'with bit operator mode' do
      it 'generates bit-operator sql' do
        expect(BitOperatorMode.bitfield_sql(vendor: true)).to eq('(users.bits & 1) = 1')
      end

      it 'generates sql for each bit' do
        expect(BitOperatorMode.bitfield_sql(vendor: true, zany: false)).to eq('(users.bits & 3) = 1')
      end

      it 'generates working sql' do
        BitOperatorMode.create!(vendor: true, zany: true)
        u2 = BitOperatorMode.create!(vendor: true, zany: false)
        BitOperatorMode.create!(vendor: false, zany: false)

        conditions = MultiBitUser.bitfield_sql(vendor: true, zany: false)
        expect(BitOperatorMode.where(conditions)).to eq([u2])
      end
    end

    describe 'with OR' do
      it 'generates sql for each bit' do
        expect(User.bitfield_sql({ vendor: true, zany: true, interesting: false },
                                 query_mode: :bit_operator_or)).to eq('(users.bits & 3) <> 0 OR (users.bits & 4) <> 4')
      end

      it 'generates sql for only ON' do
        expect(User.bitfield_sql({ vendor: true, zany: true },
                                 query_mode: :bit_operator_or)).to eq('(users.bits & 3) <> 0')
      end

      it 'generates sql for only OFF' do
        expect(User.bitfield_sql({ vendor: false, interesting: false },
                                 query_mode: :bit_operator_or)).to eq('(users.bits & 5) <> 5')
      end

      it 'generates working sql' do
        u1 = User.create!(vendor: true, zany: true)
        u2 = User.create!(vendor: true, zany: false)
        u3 = User.create!(vendor: false, zany: false)
        u4 = User.create!(interesting: true, zany: false)

        conditions = User.bitfield_sql({ vendor: true, zany: true }, query_mode: :bit_operator_or)
        expect(User.where(conditions)).to eq([u1, u2])

        conditions = User.bitfield_sql({ vendor: true, zany: false }, query_mode: :bit_operator_or)
        expect(User.where(conditions)).to eq([u1, u2, u3, u4])

        conditions = User.bitfield_sql({ vendor: false, zany: false }, query_mode: :bit_operator_or)
        expect(User.where(conditions)).to eq([u2, u3, u4])
      end

      it 'generates working sql for multiple ON bits' do
        u1 = User.create!(vendor: true)
        u2 = User.create!(zany: true)
        u3 = User.create!(interesting: true)
        u4 = User.create! # all off

        conditions = User.bitfield_sql({ vendor: true, zany: true, interesting: true },
                                       query_mode: :bit_operator_or)
        expect(User.where(conditions)).to eq([u1, u2, u3])

        conditions = User.bitfield_sql({ vendor: true, interesting: true }, query_mode: :bit_operator_or)
        expect(User.where(conditions)).to eq([u1, u3])

        conditions = User.bitfield_sql({ vendor: true }, query_mode: :bit_operator_or)
        expect(User.where(conditions)).to eq([u1])

        conditions = User.bitfield_sql({ vendor: true, zany: true, interesting: false },
                                       query_mode: :bit_operator_or)
        expect(User.where(conditions)).to eq([u1, u2, u4])
      end

      it 'generates working sql for multiple OFF bits' do
        u1 = User.create!(vendor: false, zany: true,  interesting: true)
        u2 = User.create!(vendor: true, zany: false,  interesting: true)
        u3 = User.create!(vendor: true, zany: true,  interesting: false)
        u4 = User.create!(vendor: true, zany: true,  interesting: true) # all ON

        conditions = User.bitfield_sql({ vendor: false, zany: false, interesting: false },
                                       query_mode: :bit_operator_or)
        expect(User.where(conditions)).to eq([u1, u2, u3])

        conditions = User.bitfield_sql({ vendor: false, interesting: false }, query_mode: :bit_operator_or)
        expect(User.where(conditions)).to eq([u1, u3])

        conditions = User.bitfield_sql({ vendor: false }, query_mode: :bit_operator_or)
        expect(User.where(conditions)).to eq([u1])

        conditions = User.bitfield_sql({ vendor: false, zany: false, interesting: true },
                                       query_mode: :bit_operator_or)
        expect(User.where(conditions)).to eq([u1, u2, u4])
      end
    end

    describe 'without the power of two' do
      it 'uses correct bits' do
        u = WithoutThePowerOfTwo.create!(vendor: false, zany: true, interesting: true)
        expect(u.bits).to eq(6)
      end

      it 'has all fields' do
        u = WithoutThePowerOfTwo.create!(vendor: false, zany: true)
        expect(u.vendor).to be(false)
        expect(u.zany).to be(true)
        expect(WithoutThePowerOfTwo.bitfield_options).to eq({ bits: { query_mode: :bit_operator } })
      end

      it 'can e built without options' do
        u = WithoutThePowerOfTwoWithoutOptions.create!(vendor: false, zany: true)
        expect(u.vendor).to be(false)
        expect(u.zany).to be(true)
        expect(WithoutThePowerOfTwoWithoutOptions.bitfield_options).to eq({ bits: {} })
      end
    end

    it 'checks that bitfields are unique' do
      expect do
        CheckRaise.class_eval do
          bitfield :foo, :bar, :baz, :bar
        end
      end.to raise_error(Bitfields::DuplicateBitNameError)
    end

    it 'checks that bitfields are powers of two' do
      expect do
        CheckRaise.class_eval do
          bitfield :foo, 1 => :bar, 3 => :baz, 4 => :bar
        end
      end.to raise_error('3 is not a power of 2 !!')

      expect do
        CheckRaise.class_eval do
          bitfield :foo, 1 => :bar, -1 => :baz, 4 => :bar
        end
      end.to raise_error('-1 is not a power of 2 !!')
    end
  end

  describe :set_bitfield_sql do
    it 'sets a single bit' do
      expect(User.set_bitfield_sql(vendor: true)).to eq('bits = (bits | 1) - 0')
    end

    it 'unsets a single bit' do
      expect(User.set_bitfield_sql(vendor: false)).to eq('bits = (bits | 1) - 1')
    end

    it 'sets multiple bits' do
      expect(User.set_bitfield_sql(vendor: true, zany: true)).to eq('bits = (bits | 3) - 0')
    end

    it 'unsets multiple bits' do
      expect(User.set_bitfield_sql(vendor: false, zany: false)).to eq('bits = (bits | 3) - 3')
    end

    it 'sets and unsets in one command' do
      expect(User.set_bitfield_sql(vendor: false, zany: true)).to eq('bits = (bits | 3) - 1')
    end

    it 'sets and unsets for multiple columns in one sql' do
      sql = MultiBitUser.set_bitfield_sql(vendor: false, zany: true, one: true, two: false)
      expect(sql).to eq('bits = (bits | 3) - 1, more_bits = (more_bits | 3) - 2')
    end

    it 'produces working sql' do
      u = MultiBitUser.create!(vendor: true, zany: true, interesting: false, one: true, two: false,
                               four: false)
      sql = MultiBitUser.set_bitfield_sql(vendor: false, zany: true, one: true, two: false)
      MultiBitUser.update_all(sql)
      u.reload
      expect(u.vendor).to be(false)
      expect(u.zany).to be(true)
      expect(u.interesting).to be(false)
      expect(u.one).to be(true)
      expect(u.two).to be(false)
      expect(u.four).to be(false)
    end
  end

  describe 'named scopes' do
    let!(:vendor) { User.create!(vendor: true, zany: false) }
    let!(:vendor_and_zany) { User.create!(vendor: true, zany: true) }

    it 'creates them when nothing was passed' do
      expect(User.respond_to?(:vendor)).to be(true)
      expect(User.respond_to?(:not_vendor)).to be(true)
    end

    it 'does not create them when false was passed' do
      expect(UserWithoutScopes.respond_to?(:vendor)).to be(false)
      expect(UserWithoutScopes.respond_to?(:not_vendor)).to be(false)
    end

    it 'produces working positive scopes' do
      expect(User.zany.vendor.to_a).to eq([vendor_and_zany])
    end

    it 'produces working negative scopes' do
      expect(User.not_zany.vendor.to_a).to eq([vendor])
    end
  end

  describe 'overwriting' do
    it 'does not change base class' do
      expect(OverwrittenUser.bitfields[:bits][:vendor_inherited]).not_to be_nil
      expect(User.bitfields[:bits][:vendor_inherited]).to be_nil
    end

    it 'has inherited methods' do
      expect(User.respond_to?(:vendor)).to be(true)
      expect(OverwrittenUser.respond_to?(:vendor)).to be(true)
    end
  end

  describe 'inheritance' do
    it 'knows overwritten values and normal' do
      expect(User.bitfields).to eq({ bits: { vendor: 1, zany: 2, interesting: 4 } })
      expect(OverwrittenUser.bitfields).to eq({ bits: { vendor_inherited: 1 } })
    end

    it 'knows overwritten values when overwriting' do
      expect(OverwrittenUser.bitfield_column(:vendor_inherited)).to eq(:bits)
    end

    it 'does not know old values when overwriting' do
      expect do
        OverwrittenUser.bitfield_column(:vendor)
      end.to raise_error(RuntimeError)
    end

    it 'knows inherited values without overwriting' do
      expect(InheritedUser.bitfield_column(:vendor)).to eq(:bits)
    end

    it 'has inherited scopes' do
      expect(InheritedUser).to respond_to(:not_vendor)
    end

    it 'has inherited methods' do
      expect(InheritedUser.new).to respond_to(:vendor?)
    end

    it 'knows grandchild inherited values without overwriting' do
      expect(GrandchildInheritedUser.bitfield_column(:vendor)).to eq(:bits)
    end

    it 'inherits no bitfields for a user without bitfields set' do
      expect(InheritedUserWithoutSetBitfield.bitfields).to be_nil
    end
  end

  describe 'Bitfields.positional_bits' do
    around do |example|
      previous = described_class.positional_bits
      example.run
    ensure
      described_class.positional_bits = previous
    end

    def declare_positional
      Class.new(ActiveRecord::Base) do
        self.table_name = 'users'
        include Bitfields

        bitfield :bits, :vendor, :zany
      end
    end

    it 'declares positional bits silently when :allow' do
      described_class.positional_bits = :allow
      expect { declare_positional }.not_to output.to_stderr
    end

    it 'warns about positional bits when :warn (the default)' do
      described_class.positional_bits = :warn
      expect { declare_positional }.to output(/positional bit names/).to_stderr
    end

    it 'raises on positional bits when :forbid' do
      described_class.positional_bits = :forbid
      expect { declare_positional }.to raise_error(Bitfields::PositionalBitsError, /positional bit names/)
    end

    it 'still allows explicit bit declarations when :forbid' do
      described_class.positional_bits = :forbid
      expect do
        Class.new(ActiveRecord::Base) do
          self.table_name = 'users'
          include Bitfields

          bitfield :bits, 1 => :vendor, 2 => :zany
        end
      end.not_to raise_error
    end

    it 'rejects an unknown mode' do
      described_class.positional_bits = :nonsense
      expect { declare_positional }.to raise_error(ArgumentError, /must be one of/)
    end
  end

  describe 'positional placeholders' do
    around do |example|
      previous = described_class.positional_bits
      described_class.positional_bits = :allow
      example.run
    ensure
      described_class.positional_bits = previous
    end

    it 'reserves a bit position with nil so later bits do not shift' do
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = 'users'
        include Bitfields

        bitfield :bits, :vendor, nil, :interesting
      end
      expect(klass.bitfields[:bits]).to eq(vendor: 1, interesting: 4)
    end

    it 'reserves a bit position with :_skip' do
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = 'users'
        include Bitfields

        bitfield :bits, :vendor, :_skip, :interesting
      end
      expect(klass.bitfields[:bits]).to eq(vendor: 1, interesting: 4)
    end
  end

  describe 'unique bit names across columns (issue #21)' do
    it 'raises when the same bit name is used in two columns' do
      expect do
        Class.new(ActiveRecord::Base) do
          self.table_name = 'users'
          include Bitfields

          bitfield :bits, 1 => :flag
          bitfield :more_bits, 1 => :flag
        end
      end.to raise_error(Bitfields::DuplicateBitNameError, /flag/)
    end

    it 'allows distinct bit names across columns' do
      expect do
        Class.new(ActiveRecord::Base) do
          self.table_name = 'users'
          include Bitfields

          bitfield :bits, 1 => :one
          bitfield :more_bits, 1 => :two
        end
      end.not_to raise_error
    end
  end

  describe :with_bitfields do
    before { User.delete_all }

    let!(:vendor) { User.create!(vendor: true, zany: false) }
    let!(:zany) { User.create!(vendor: false, zany: true) }

    it 'returns rows matching a single bit' do
      expect(User.with_bitfields(vendor: true).to_a).to eq([vendor])
    end

    it 'returns rows matching on and off bits' do
      expect(User.with_bitfields(vendor: true, zany: false).to_a).to eq([vendor])
    end

    it 'negates with without_bitfields' do
      expect(User.without_bitfields(vendor: true).to_a).to eq([zany])
    end

    it 'is chainable as a relation' do
      expect(User.with_bitfields(vendor: true)).to be_a(ActiveRecord::Relation)
      expect(User.with_bitfields(vendor: true).not_zany.to_a).to eq([vendor])
    end
  end

  describe 'querying through eager-loaded associations (issue #45)' do
    before do
      User.delete_all
      Team.delete_all
    end

    # An Arel predicate carries its table relation, so unlike a string condition it triggers the
    # join and filters correctly when composed via includes/references/merge on ActiveRecord >= 6.1.
    it 'filters on a bitfield of an included association' do
      with_vendor = Team.create!(name: 'vendors')
      without_vendor = Team.create!(name: 'others')
      UserWithExplicitBits.create!(vendor: true, team: with_vendor)
      UserWithExplicitBits.create!(vendor: false, team: without_vendor)

      result = Team.includes(:members).references(:members).merge(User.with_bitfields(vendor: true))
      expect(result.to_a).to eq([with_vendor])
    end
  end

  describe 'rspec matchers' do
    subject { User.new }

    it { is_expected.to have_a_bitfield :vendor }
    it { is_expected.not_to have_a_bitfield :pickle_eater }
  end
end
