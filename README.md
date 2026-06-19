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
  bitfield :my_bits, 1 => :seller, 2 => :active, 4 => :sensible
end

user = User.new(seller: true, active: true)
user.seller # => true
user.sensible? # => false
user.my_bits # => 3
```

### Always declare explicit bits

`bitfield :my_bits, 1 => :seller, 2 => :active, 4 => :sensible` maps each name to an explicit bit,
so the mapping is locked even if you reorder the list. The positional shorthand
`bitfield :my_bits, :seller, :active, :sensible` instead maps each name to `2**index`, which means
**inserting, removing, or reordering a name silently shifts every later bit and corrupts stored
data**. By default a positional declaration now emits a warning; see
[`Bitfields.positional_bits`](#positional-bit-safety).

 - records bitfield_changes `user.bitfield_changes # => {"seller" => [false, true], "active" => [false, true]}` (also `seller_was` / `seller_change` / `seller_changed?` / `seller_became_true?` / `seller_became_false?`)
   - Individual added methods (i.e, `seller_was`, `seller_changed?`, etc..) can be deactivated with `bitfield ..., added_instance_methods: false`
   - **Note**: when used in the context of an `after_save` callback, `_was` returns the current value and `_changed?` returns `false`, since the previous changes have been persisted.
 - convenient queries `User.with_bitfields(seller: true, active: false)` and `User.without_bitfields(seller: true)`
 - adds scopes `User.seller.sensible.first` (deactivate with `bitfield ..., scopes: false`)
 - builds sql `User.bitfield_sql(active: true, sensible: false) # => '(users.my_bits & 6) = 2'`
 - builds sql with OR condition `User.bitfield_sql({ active: true, sensible: true }, query_mode: :bit_operator_or) # => '(users.my_bits & 2) = 2 OR (users.my_bits & 4) = 4'`
 - builds index-using sql with `bitfield ... , query_mode: :in_list` and `User.bitfield_sql(active: true, sensible: false) # => 'users.my_bits IN (2, 3)'` (2 and 1+2) often slower than :bit_operator sql especially for high number of bits
 - builds update sql `User.set_bitfield_sql(active: true, sensible: false) == 'my_bits = (my_bits | 6) - 4'`
 - **faster sql than any other bitfield lib** through combination of multiple bits into a single sql statement
 - gives access to bits `User.bitfields[:my_bits][:sensible] # => 4`
 - converts hash to bits `User.bitfield_bits(seller: true) # => 1`

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
t.integer :my_bits, default: 0, null: false
# OR
add_column :users, :my_bits, :integer, default: 0, null: false
```

Instance Methods
================

### Global Bitfield Methods
| Method Name        | Example (`user = User.new(seller: true, active: true`)  | Result                                                      |
|--------------------|---------------------------------------------------------|-------------------------------------------------------------|
| `bitfield_values`  | `user.bitfield_values`                                  | `{"seller" => true, "active" => true, "sensible" => false}` |
| `bitfield_changes` | `user.bitfield_changes`                                 | `{"seller" => [false, true], "active" => [false, true]}`    |

### Individual Bit Methods
#### Model Getters / Setters
| Method Name    | Example (`user = User.new`) | Result  |
|----------------|-----------------------------|---------|
| `#{bit_name}`  | `user.seller`               | `false` |
| `#{bit_name}=` | `user.seller = true`        | `true`  |
| `#{bit_name}?` | `user.seller?`              | `true`  |

#### Dirty Methods:

Some, not all, [`ActiveRecord::AttributeMethods::Dirty`](https://api.rubyonrails.org/v5.1.7/classes/ActiveRecord/AttributeMethods/Dirty.html) and [`ActiveModel::Dirty`](https://api.rubyonrails.org/v5.1.7/classes/ActiveModel/Dirty.html) methods can be used on each bitfield:

##### Before Model Persistence
| Method Name                        | Example (`user = User.new`)        | Result          |
|------------------------------------|------------------------------------|-----------------|
| `#{bit_name}_was`                  | `user.seller_was`                  | `false`         |
| `#{bit_name}_in_database`          | `user.seller_in_database`          | `false`         |
| `#{bit_name}_change`               | `user.seller_change`               | `[false, true]` |
| `#{bit_name}_change_to_be_saved`   | `user.seller_change_to_be_saved`   | `[false, true]` |
| `#{bit_name}_changed?`             | `user.seller_changed?`             | `true`          |
| `will_save_change_to_#{bit_name}?` | `user.will_save_change_to_seller?` | `true`          |
| `#{bit_name}_became_true?`         | `user.seller_became_true?`         | `true`          |
| `#{bit_name}_became_false?`        | `user.seller_became_false?`        | `false`         |


##### After Model Persistence
| Method Name                    | Example (`user = User.create(seller: true)`)      | Result          |
|--------------------------------|---------------------------------------------------|-----------------|
| `#{bit_name}_before_last_save` | `user.seller_before_last_save`                    | `false`         |
| `saved_change_to_#{bit_name}`  | `user.saved_change_to_seller`                     | `[false, true]` |
| `saved_change_to_#{bit_name}?` | `user.saved_change_to_seller?`                    | `true`          |

  - **Note**: These methods are dynamically defined for each bitfield, and function separately from the real `ActiveRecord::AttributeMethods::Dirty`/`ActiveModel::Dirty` methods. As such, generic methods (e.g. `attribute_before_last_save(:attribute)`) will not work.

Examples
========
Update all users

```ruby
User.seller.not_sensible.update_all(User.set_bitfield_sql(seller: true, active: true))
```

Delete the shop when a user is no longer a seller

```ruby
before_save :delete_shop, if: -> { |u| u.seller_change == [true, false] }
```

List fields and their respective values

```ruby
user = User.new(active: true)
user.bitfield_values(:my_bits) # => { seller: false, active: true, sensible: false }
```

Querying through associations

```ruby
# `with_bitfields` builds an Arel predicate, so it composes with eager loading. A raw string
# condition would silently match nothing here on modern ActiveRecord.
Team.includes(:members).references(:members).merge(User.with_bitfields(seller: true))
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
bitfield :bits, :seller, nil, :sensible # seller => 1, sensible => 4 (bit 2 left unused)
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

![performance](http://chart.apis.google.com/chart?chtt=bit-operator+vs+IN+--+with+index&chd=s:CEGIKNPRUW,DEHJLOQSVX,CFHKMPSYXZ,DHJMPSVYbe,DHLPRVZbfi,FKOUZeinsx,FLQWbglqw2,HNTZfkqw19,BDEGHJLMOP,BDEGIKLNOQ,BDFGIKLNPQ,BDFGILMNPR,BDFHJKMOQR,BDFHJLMOQS,BDFHJLNPRT,BDFHJLNPRT&chxt=x,y&chxl=0:|100K|200K|300K|400K|500K|600K|700K|800K|900K|1000K|1:|0|1441.671ms&cht=lc&chs=600x500&chdl=2bits+%28in%29|3bits+%28in%29|4bits+%28in%29|6bits+%28in%29|8bits+%28in%29|10bits+%28in%29|12bits+%28in%29|14bits+%28in%29|2bits+%28bit%29|3bits+%28bit%29|4bits+%28bit%29|6bits+%28bit%29|8bits+%28bit%29|10bits+%28bit%29|12bits+%28bit%29|14bits+%28bit%29&chco=0000ff,0000ee,0000dd,0000cc,0000bb,0000aa,000099,000088,ff0000,ee0000,dd0000,cc0000,bb0000,aa0000,990000,880000)

Testing With RSpec
=========

To assert that a specific flag is a bitfield flag and has the `active?`, `active`, and `active=` methods and behavior use the following matcher:

````ruby
require 'bitfields/rspec'

describe User do
  it { is_expected.to have_a_bitfield :active }
end
````

Supported versions
===================
Ruby >= 3.1 and ActiveRecord 6.1 – 8.0, tested on CI.

Authors
=======
### [Contributors](http://github.com/grosser/bitfields/contributors)
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
