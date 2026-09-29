# Example: an outdoor shop's product categories

A worked run of this skill on `tests/fixtures/addon-sample-30.csv`: 30 product categories from a
made-up UK outdoor shop at `shop.example.com`. The data is synthetic.

The store context given in step 2 was: a UK shop selling outdoor clothing, footwear and camping kit
to walkers and campers; British English; the default length; drop the shared delivery and returns
text.

The work went in three batches, largest group first, each appended to `rewrites.jsonl` and checked
with `apply`:

1. The 8 terms of `template-7c1e2a` ("Shop our range of {name} at great prices. Free UK delivery on
   orders over £50.").
2. The other three groups (boilerplate, duplicate, near duplicate), plus one revision of a batch 1
   description.
3. The remaining 11 terms, found with `show --done rewrites.jsonl`.

Result: 29 descriptions changed, 1 kept, `PASSED`. Only `term_taxonomy.description` differs from the
original file.

- `outdoor-shop-rewrites.jsonl`: the rewrites as recorded, revisions included.
- `outdoor-shop-rewritten.csv`: the file to import.

## Five rows before and after

**Waterproof Jackets** (`template`, group `template-7c1e2a`)

Before: `<p>Shop our range of Waterproof Jackets at great prices. Free UK delivery on orders over £50.</p>`

After: `<p>Jackets to keep the rain out. A waterproof is the outer layer you pull on when the weather turns, worn over a base layer or fleece so you can add or remove warmth underneath as the day changes.</p><p>For cold, dry days, see Insulated Jackets. For wind and light showers on the move, see Softshell Jackets.</p>`

**Walking Boots** (`template`, same group)

Before: `<p>Shop our range of Walking Boots at great prices. Free UK delivery on orders over £50.</p>`

After: `<p>Walking boots for hill walking, long days on rough paths and wet, muddy ground, where you want more support around the ankle than a shoe gives.</p><p>Wear them with proper walking socks. For lighter, faster walking on drier trails, see Trail Shoes.</p>`

**Rucksacks** (`boilerplate`, group `boilerplate-41d09f`). The unique sentence and its link are kept;
the shared returns paragraph is dropped.

Before: `<p>Daypacks and bigger rucksacks for multi-day trips. See our <a href="https://shop.example.com/rucksack-fitting/">rucksack fitting guide</a>.</p><p>Not happy with your order? Return it within 30 days for a full refund. Returns are free for UK customers.</p>`

After: `<p>Daypacks for a day on the hill, and bigger rucksacks for multi-day trips with a tent and sleeping bag to carry. A good fit makes more difference than any feature, so see our <a href="https://shop.example.com/rucksack-fitting/">rucksack fitting guide</a> before you choose.</p>`

**Walking Poles** (`near_duplicate`, group `near-9b3e70`). The stock claim is dropped: nothing in the
file supports it.

Before: `Great quality outdoor gear for every adventure, in stock and ready to ship.`

After: `<p>Walking poles take some of the load off your knees on steep descents and help your balance on rough or slippery ground. They are usually used in pairs and fold or telescope down to strap onto a rucksack.</p>`

**Misc 2** (`placeholder,short`). Kept: no products, and a name that says nothing about what belongs
in it.

Before: `TBC`

After: `TBC` (unchanged)
