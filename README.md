# bonkers-bitfields

[![CI](https://github.com/bonkers-ie/bitfields/actions/workflows/ci.yml/badge.svg)](https://github.com/bonkers-ie/bitfields/actions/workflows/ci.yml)

Save migrations and columns by storing multiple booleans in a single integer.<br/>
e.g. true-false-false = 1, false-true-false = 2,  true-false-true = 5 (1,2,4,8,..)

> This is a maintained fork of [grosser/bitfields](https://github.com/grosser/bitfields),
> published on RubyGems as **`bonkers-bitfields`**. The library is still required as
> `bitfields` and the module is still `Bitfields`, so existing code does not change.

```ruby
class User < ActiveRecord::Base
  include Bitfields
  bitfield :flags, 1 => :vendor, 2 => :zany, 4 => :interesting
end

user = User.new(vendor: true, zany: true)
user.vendor # => true
user.interesting? # => false
user.flags # => 3
```

### Always declare explicit bits

`bitfield :flags, 1 => :vendor, 2 => :zany, 4 => :interesting` maps each name to an explicit bit,
so the mapping is locked even if you reorder the list. The positional shorthand
`bitfield :flags, :vendor, :zany, :interesting` instead maps each name to `2**index`, which means
**inserting, removing, or reordering a name silently shifts every later bit and corrupts stored
data**. By default a positional declaration now emits a warning; see
[`Bitfields.positional_bits`](#positional-bit-safety).

 - records bitfield_changes `user.bitfield_changes # => {"vendor" => [false, true], "zany" => [false, true]}` (also `vendor_was` / `vendor_change` / `vendor_changed?` / `vendor_became_true?` / `vendor_became_false?`)
   - Individual added methods (i.e, `vendor_was`, `vendor_changed?`, etc..) can be deactivated with `bitfield ..., added_instance_methods: false`
   - **Note**: when used in the context of an `after_save` callback, `_was` returns the current value and `_changed?` returns `false`, since the previous changes have been persisted.
 - convenient queries `User.with_bitfields(vendor: true, zany: false)` and `User.without_bitfields(vendor: true)`
 - adds scopes `User.vendor.interesting.first` (deactivate with `bitfield ..., scopes: false`)
 - builds sql `User.bitfield_sql(zany: true, interesting: false) # => '(users.flags & 6) = 2'`
 - builds sql with OR condition `User.bitfield_sql({ zany: true, interesting: true }, query_mode: :bit_operator_or) # => '(users.flags & 2) = 2 OR (users.flags & 4) = 4'`
 - builds index-using sql with `bitfield ... , query_mode: :in_list` and `User.bitfield_sql(zany: true, interesting: false) # => 'users.flags IN (2, 3)'` (2 and 1+2) often slower than :bit_operator sql especially for high number of bits
 - builds update sql `User.set_bitfield_sql(zany: true, interesting: false) == 'flags = (flags | 6) - 4'`
 - **faster sql than any other bitfield lib** through combination of multiple bits into a single sql statement
 - gives access to bits `User.bitfields[:flags][:interesting] # => 4`
 - converts hash to bits `User.bitfield_bits(vendor: true) # => 1`

Bit names must be unique per model: declaring the same name in two columns raises
`Bitfields::DuplicateBitNameError`.

Install
=======

```bash
gem install bonkers-bitfields
```

```ruby
# Gemfile
gem "bonkers-bitfields"
```

```ruby
require "bitfields" # the library path and the Bitfields module are unchanged
```

### Migration
ALWAYS set a default, bitfield queries will not work for NULL

```ruby
t.integer :flags, default: 0, null: false
# OR
add_column :users, :flags, :integer, default: 0, null: false
```

Instance Methods
================

### Global Bitfield Methods
| Method Name        | Example (`user = User.new(vendor: true, zany: true`)  | Result                                                      |
|--------------------|---------------------------------------------------------|-------------------------------------------------------------|
| `bitfield_values`  | `user.bitfield_values`                                  | `{"vendor" => true, "zany" => true, "interesting" => false}` |
| `bitfield_changes` | `user.bitfield_changes`                                 | `{"vendor" => [false, true], "zany" => [false, true]}`    |

### Individual Bit Methods
#### Model Getters / Setters
| Method Name    | Example (`user = User.new`) | Result  |
|----------------|-----------------------------|---------|
| `#{bit_name}`  | `user.vendor`               | `false` |
| `#{bit_name}=` | `user.vendor = true`        | `true`  |
| `#{bit_name}?` | `user.vendor = true; user.vendor?` | `true`  |

#### Dirty Methods:

Some, not all, [`ActiveRecord::AttributeMethods::Dirty`](https://api.rubyonrails.org/classes/ActiveRecord/AttributeMethods/Dirty.html) and [`ActiveModel::Dirty`](https://api.rubyonrails.org/classes/ActiveModel/Dirty.html) methods can be used on each bitfield:

##### Before Model Persistence
| Method Name                        | Example (`user = User.new`)        | Result          |
|------------------------------------|------------------------------------|-----------------|
| `#{bit_name}_was`                  | `user.vendor_was`                  | `false`         |
| `#{bit_name}_in_database`          | `user.vendor_in_database`          | `false`         |
| `#{bit_name}_change`               | `user.vendor_change`               | `[false, true]` |
| `#{bit_name}_change_to_be_saved`   | `user.vendor_change_to_be_saved`   | `[false, true]` |
| `#{bit_name}_changed?`             | `user.vendor_changed?`             | `true`          |
| `will_save_change_to_#{bit_name}?` | `user.will_save_change_to_vendor?` | `true`          |
| `#{bit_name}_became_true?`         | `user.vendor_became_true?`         | `true`          |
| `#{bit_name}_became_false?`        | `user.vendor_became_false?`        | `false`         |


##### After Model Persistence
| Method Name                    | Example (`user = User.create(vendor: true)`)      | Result          |
|--------------------------------|---------------------------------------------------|-----------------|
| `#{bit_name}_before_last_save` | `user.vendor_before_last_save`                    | `false`         |
| `saved_change_to_#{bit_name}`  | `user.saved_change_to_vendor`                     | `[false, true]` |
| `saved_change_to_#{bit_name}?` | `user.saved_change_to_vendor?`                    | `true`          |

  - **Note**: These methods are dynamically defined for each bitfield, and function separately from the real `ActiveRecord::AttributeMethods::Dirty`/`ActiveModel::Dirty` methods. As such, generic methods (e.g. `attribute_before_last_save(:attribute)`) will not work.

Examples
========
Update all users

```ruby
User.vendor.not_interesting.update_all(User.set_bitfield_sql(vendor: true, zany: true))
```

Delete the shop when a user is no longer a vendor

```ruby
before_save :delete_shop, if: -> { |u| u.vendor_change == [true, false] }
```

List fields and their respective values

```ruby
user = User.new(zany: true)
user.bitfield_values(:flags) # => { vendor: false, zany: true, interesting: false }
```

Querying through associations

```ruby
# `with_bitfields` builds an Arel predicate, so it composes with eager loading. A raw string
# condition would silently match nothing here on modern ActiveRecord.
Team.includes(:members).references(:members).merge(User.with_bitfields(vendor: true))
```

<a name="positional-bit-safety"></a>
Positional bit safety
=====================
Control how the positional shorthand (`bitfield :bits, :foo, :bar`) is treated:

```ruby
Bitfields.positional_bits = :warn   # default: warn that positional bits are fragile
Bitfields.positional_bits = :forbid # raise Bitfields::PositionalBitsError instead
Bitfields.positional_bits = :allow  # legacy behaviour, no warning
```

If you keep positional declarations, you can reserve a bit position with `nil` or `:_skip` so
removing a bit does not shift the bits after it:

```ruby
bitfield :bits, :vendor, nil, :interesting # vendor => 1, interesting => 4 (bit 2 left unused)
```

TIPS
====
 - [Defaults for new records] set via db migration or name the bit foo_off to avoid confusion, setting via after_initialize [does not work](https://github.com/grosser/bitfields/commit/2170dc546e2c4f1187089909a80e8602631d0796)
 - It is slow to do: `#{bitfield_sql(...)} AND #{bitfield_sql(...)}`, merge both into one hash
 - bit_operator is faster in most cases, use `query_mode: :in_list` sparingly
 - Standard mysql integer is 4 byte -> 32 bitfields
 - Prefer explicit bits `bitfield :bits, 1 => :foo, 2 => :bar, 4 => :baz` (or `2**0 => :foo, 2**1 => :bar`) over the positional shorthand `bitfield :bits, :foo, :bar, :baz`

Query-mode Benchmark
=========
The `query_mode: :in_list` is slower for most queries and scales miserably with the number of bits.<br/>
*Stay with the default query-mode*. Only use :in_list if your edge-case shows better performance.

Run the benchmark yourself with `ruby benchmark/bit_operator_vs_in.rb`: across 2–14 bits, `:bit_operator`
stays roughly flat while `:in_list` grows steeply with the number of bits.

Testing With RSpec
=========

To assert that a specific flag is a bitfield flag and has the `zany?`, `zany`, and `zany=` methods and behavior use the following matcher:

````ruby
require 'bitfields/rspec'

describe User do
  it { is_expected.to have_a_bitfield :zany }
end
````

Supported versions
===================
Ruby >= 3.1 and ActiveRecord 6.1 – 8.0, tested on CI.

Authors
=======
### [Contributors](https://github.com/bonkers-ie/bitfields/contributors)
 - [Ben Walsh](https://github.com/benwalsh)
 - [Hellekin O. Wolf](https://github.com/hellekin)
 - [John Wilkinson](https://github.com/jcwilk)
 - [PeppyHeppy](https://github.com/peppyheppy)
 - [kmcbride](https://github.com/kmcbride)
 - [Justin Aiken](https://github.com/JustinAiken)
 - [szTheory](https://github.com/szTheory)
 - [Reed G. Law](https://github.com/reedlaw)
 - [Rael Gugelmin Cunha](https://github.com/reedlaw)
 - [Alan Wong](https://github.com/naganowl)
 - [Andrew Bates](https://github.com/a-bates)
 - [Shirish Pampoorickal](https://github.com/shirish-pampoorickal)
 - [Sergey Kojin](https://github.com/skojin)

Originally by [Michael Grosser](http://grosser.it) (michael@grosser.it).<br/>
Maintained as `bonkers-bitfields` by [Bonkers.ie](https://github.com/bonkers-ie).<br/>
License: MIT
