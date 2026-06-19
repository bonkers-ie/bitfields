# frozen_string_literal: true

require 'bitfields/version'
require 'active_support'

module Bitfields
  TRUE_VALUES = [true, 1, '1', 't', 'T', 'true', 'TRUE'].freeze # taken from ActiveRecord::ConnectionAdapters::Column

  # Symbols/values that reserve a positional bit without naming it, so removing a bit
  # leaves a gap instead of silently shifting every later bit down.
  POSITIONAL_PLACEHOLDERS = [nil, :_skip].freeze
  POSITIONAL_MODES = %i[allow warn forbid].freeze

  class DuplicateBitNameError < ArgumentError; end
  class InvalidBitError < ArgumentError; end
  class PositionalBitsError < ArgumentError; end

  class << self
    # How to treat the positional shorthand `bitfield :col, :a, :b` (maps each name to 2**index,
    # so reordering/inserting/removing a name silently shifts stored bits):
    #   :warn (default) - emit a warning, :forbid - raise, :allow - stay silent (legacy behaviour)
    attr_writer :positional_bits

    def positional_bits
      @positional_bits ||= :warn
    end

    def included(base)
      class << base
        attr_accessor :bitfields, :bitfield_options, :bitfield_args

        # all the args passed into .bitfield so children can initialize from parents
        def bitfield_args
          @bitfield_args ||= []
        end

        def inherited(subclass)
          super
          subclass.bitfield_args = bitfield_args.dup
          subclass.bitfield_args.each do |column, options|
            subclass.send :store_bitfield_values, column, options.dup
          end
        end
      end

      base.extend Bitfields::ClassMethods
    end

    def extract_bits(options)
      options.keys.grep(Numeric).each_with_object({}) do |bit, bitfields|
        unless bit.is_a?(Integer) && bit.positive? && bit.nobits?(bit - 1)
          raise InvalidBitError, "#{bit} is not a power of 2 !!"
        end

        bit_name = options.delete(bit).to_sym
        raise DuplicateBitNameError if bitfields.key?(bit_name)

        bitfields[bit_name] = bit
      end
    end
  end

  module ClassMethods
    def bitfield(column, *args)
      column = column.to_sym
      options = extract_bitfield_options(column, args)
      bitfield_args << [column, options.dup]

      store_bitfield_values column, options
      add_bitfield_methods column, options
    end

    def bitfield_bits(values)
      bits = bitfields.values.reduce({}, :merge)
      values.sum { |bit, on| on ? bits.fetch(bit) : 0 }
    end

    def bitfield_column(bit_name)
      found = bitfields.find { |_, bits| bits.key?(bit_name.to_sym) }
      raise "Unknown bitfield #{bit_name}" unless found

      found.first
    end

    def bitfield_sql(bit_values, options = {})
      bits = group_bits_by_column(bit_values).sort_by { |column, _| column.to_s }
      bits.map { |column, values| bitfield_sql_by_column(column, values, options) }.join(' AND ')
    end

    # rubocop:disable Naming/AccessorMethodName -- public API name, kept for backwards compatibility
    def set_bitfield_sql(bit_values)
      bits = group_bits_by_column(bit_values).sort_by { |column, _| column.to_s }
      bits.map { |column, values| set_bitfield_sql_by_column(column, values) }.join(', ')
    end
    # rubocop:enable Naming/AccessorMethodName

    # Arel-based predicate for the given bits. Unlike the string SQL built by bitfield_sql,
    # an Arel predicate carries its table relation, so it composes with eager loading
    # (`includes`/`references`/`merge`) without the silent no-match that strings cause on
    # ActiveRecord >= 6.1.
    def bitfield_arel(bit_values)
      predicates = group_bits_by_column(bit_values).sort_by { |column, _| column.to_s }.map do |column, values|
        bitfield_arel_by_column(column, values)
      end
      predicates.reduce(:and)
    end

    # Convenient named query: `User.with_bitfields(seller: true, insane: false)`
    def with_bitfields(bit_values)
      where(bitfield_arel(bit_values))
    end

    def without_bitfields(bit_values)
      where.not(bitfield_arel(bit_values))
    end

    private

    def extract_bitfield_options(column, args)
      options = args.last.is_a?(Hash) ? args.pop.dup : {}
      return options if args.empty?

      enforce_positional_policy(column)
      args.each_with_index do |field, index|
        next if POSITIONAL_PLACEHOLDERS.include?(field)

        options[2**index] = field # add fields given in normal args to options
      end
      options
    end

    def enforce_positional_policy(column)
      case Bitfields.positional_bits
      when :allow then nil
      when :warn then warn(positional_bits_message(column))
      when :forbid then raise PositionalBitsError, positional_bits_message(column)
      else raise ArgumentError, "Bitfields.positional_bits must be one of #{POSITIONAL_MODES.inspect}"
      end
    end

    def positional_bits_message(column)
      "#{name}: bitfield #{column.inspect} uses positional bit names, which silently shift stored " \
        'bits if the list is reordered or an entry is removed. Declare explicit bits instead, ' \
        "e.g. `bitfield #{column.inspect}, 1 => :first, 2 => :second`."
    end

    def store_bitfield_values(column, options)
      self.bitfields ||= {}
      self.bitfield_options ||= {}
      extracted = Bitfields.extract_bits(options)
      ensure_unique_bit_names!(column, extracted)
      bitfields[column] = extracted
      bitfield_options[column] = options
    end

    def ensure_unique_bit_names!(column, extracted)
      taken = bitfields.except(column).values.flat_map(&:keys)
      duplicate = extracted.keys.find { |bit_name| taken.include?(bit_name) }
      return unless duplicate

      raise DuplicateBitNameError,
            "#{name}: bit name #{duplicate.inspect} is already defined on another bitfield column " \
            '(bit names must be unique per model)'
    end

    def add_bitfield_methods(column, options)
      bitfields[column].each_key do |bit_name|
        if options[:added_instance_methods] != false
          define_method(bit_name) { bitfield_value(bit_name) }
          define_method("#{bit_name}?") { bitfield_value(bit_name) }
          define_method("#{bit_name}=") { |value| set_bitfield_value(bit_name, value) }

          # Dirty methods usable in before_save contexts
          define_method("#{bit_name}_was") { bitfield_value_was(bit_name) }
          alias_method "#{bit_name}_in_database", "#{bit_name}_was"

          define_method("#{bit_name}_change") { bitfield_value_change(bit_name) }
          alias_method "#{bit_name}_change_to_be_saved", "#{bit_name}_change"

          define_method("#{bit_name}_changed?") { bitfield_value_change(bit_name).present? }
          alias_method "will_save_change_to_#{bit_name}?", "#{bit_name}_changed?"

          define_method("#{bit_name}_became_true?") do
            value = bitfield_value(bit_name)
            value && send("#{bit_name}_was") != value
          end
          define_method("#{bit_name}_became_false?") do
            value = bitfield_value(bit_name)
            !value && send("#{bit_name}_was") != value
          end

          # Dirty methods usable in after_save contexts
          define_method("#{bit_name}_before_last_save") { bitfield_value_before_last_save(bit_name) }
          define_method("saved_change_to_#{bit_name}") { saved_change_to_bitfield_value(bit_name) }
          define_method("saved_change_to_#{bit_name}?") { saved_change_to_bitfield_value(bit_name).present? }
        end

        if options[:scopes] != false
          scope bit_name, bitfield_scope_options(bit_name => true)
          scope "not_#{bit_name}", bitfield_scope_options(bit_name => false)
        end
      end

      include Bitfields::InstanceMethods
    end

    def bitfield_scope_options(bit_values)
      -> { where(bitfield_arel(bit_values)) }
    end

    def bitfield_sql_by_column(column, bit_values, options = {})
      mode = options[:query_mode] || bitfield_options[column][:query_mode] || :bit_operator
      case mode
      when :in_list
        max = (bitfields[column].values.max * 2) - 1
        bits = (0..max).to_a # all possible bits
        bit_values.each do |bit_name, value|
          bit = bitfields[column][bit_name]
          # reject values with: bit off for true, bit on for false
          bits.reject! { |i| i & bit == (value ? 0 : bit) }
        end
        "#{table_name}.#{column} IN (#{bits.join(',')})"
      when :bit_operator
        on, off = bit_values_to_on_off(column, bit_values)
        "(#{table_name}.#{column} & #{on + off}) = #{on}"
      when :bit_operator_or
        on, off = bit_values_to_on_off(column, bit_values)
        result = []
        result << "(#{table_name}.#{column} & #{on}) <> 0" if on != 0
        result << "(#{table_name}.#{column} & #{off}) <> #{off}" if off != 0
        result.join(' OR ')
      else raise("bitfields: unknown query mode #{mode.inspect}")
      end
    end

    def set_bitfield_sql_by_column(column, bit_values)
      on, off = bit_values_to_on_off(column, bit_values)
      "#{column} = (#{column} | #{on + off}) - #{off}"
    end

    def bitfield_arel_by_column(column, bit_values)
      attribute = arel_table[column]
      on, off = bit_values_to_on_off(column, bit_values)
      predicates = []
      predicates << (attribute & on).eq(on) unless on.zero?
      predicates << (attribute & off).eq(0) unless off.zero?
      predicates.reduce(:and)
    end

    def group_bits_by_column(bit_values)
      columns = {}
      bit_values.each do |bit_name, value|
        column = bitfield_column(bit_name.to_sym)
        columns[column] ||= {}
        columns[column][bit_name.to_sym] = value
      end
      columns
    end

    def bit_values_to_on_off(column, bit_values)
      on = off = 0
      bit_values.each do |bit_name, value|
        bit = bitfields[column][bit_name]
        value ? on += bit : off += bit
      end
      [on, off]
    end
  end

  module InstanceMethods
    def bitfield_values(column)
      self.class.bitfields[column.to_sym].keys.to_h { |bit_name| [bit_name, bitfield_value(bit_name)] }
    end

    def bitfield_changes
      self.class.bitfields.values.flat_map(&:keys).each_with_object({}) do |bit, changes|
        old = bitfield_value_was(bit)
        current = bitfield_value(bit)
        changes[bit.to_s] = [old, current] unless old == current
      end
    end

    private

    def bitfield_value(bit_name)
      _, bit, current_value = bitfield_info(bit_name)
      current_value & bit != 0
    end

    def bitfield_value_was(bit_name)
      column, bit, = bitfield_info(bit_name)
      send("#{column}_was") & bit != 0
    end

    def bitfield_value_before_last_save(bit_name)
      column, bit, = bitfield_info(bit_name)
      column_before_last_save = send("#{column}_before_last_save")
      column_before_last_save.nil? ? nil : column_before_last_save & bit != 0
    end

    def bitfield_value_change(bit_name)
      values = [bitfield_value_was(bit_name), bitfield_value(bit_name)]
      values unless values[0] == values[1]
    end

    def saved_change_to_bitfield_value(bit_name)
      value_before_last_save = bitfield_value_before_last_save(bit_name)
      current_value = bitfield_value(bit_name)
      return if value_before_last_save.nil? || (value_before_last_save == current_value)

      [value_before_last_save, current_value]
    end

    def set_bitfield_value(bit_name, value)
      column, bit, current_value = bitfield_info(bit_name)
      new_value = TRUE_VALUES.include?(value)
      old_value = bitfield_value(bit_name)
      return if new_value == old_value

      # 8 + 1 == 9 // 8 + 8 == 8 // 1 - 8 == 1 // 8 - 8 == 0
      new_bits = new_value ? current_value | bit : (current_value | bit) - bit
      send("#{column}=", new_bits)
    end

    def bitfield_info(bit_name)
      column = self.class.bitfield_column(bit_name)
      [
        column,
        self.class.bitfields[column][bit_name], # bit
        send(column) || 0 # current value
      ]
    end
  end
end
